import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

private final class RecordingEscapeEventTapContext {
    weak var controller: DictationController?
    let swallowState: RecordingEscapeSwallowState
    let allowedModifierFlags: NSEvent.ModifierFlags
    let recordingShortcutKeyCode: UInt16?

    init(
        controller: DictationController,
        swallowState: RecordingEscapeSwallowState,
        allowedModifierFlags: NSEvent.ModifierFlags,
        recordingShortcutKeyCode: UInt16?
    ) {
        self.controller = controller
        self.swallowState = swallowState
        self.allowedModifierFlags = allowedModifierFlags
        self.recordingShortcutKeyCode = recordingShortcutKeyCode
    }
}

@Observable
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case preparing(modelDisplayName: String)
        case recording
        case transcribing
        case reviewing(text: String)
        case error(String)
    }

    static let shared = DictationController()

    private(set) var state: State = .idle

    private let recorder = AudioRecorder()
    private var recordStart: Date?
    private var elapsedTask: Task<Void, Never>?
    private var reviewEscMonitor: Any?
    private var recordingLocalEscMonitor: Any?
    private var recordingEscEventTap: CFMachPort?
    private var recordingEscRunLoopSource: CFRunLoopSource?
    private var recordingEscEventTapContext: RecordingEscapeEventTapContext?
    @ObservationIgnored
    private let recordingEscapeSwallowState = RecordingEscapeSwallowState()
    private var recordingStartGate = RecordingStartGate()
    private var standaloneModifierEventCoordinator = StandaloneModifierEventCoordinator()
    private var resumeContext: ResumeContext?

    /// Snapshot of the review text taken when the user clicks Resume.
    /// Splits the text at the caret so the next transcription can be
    /// spliced into the same position when recording finishes.
    private struct ResumeContext {
        let fullText: String
        let cursorLocation: Int
        let prefix: String
        let suffix: String

        init(fullText: String, cursorLocation: Int) {
            let ns = fullText as NSString
            let safeCursor = max(0, min(cursorLocation, ns.length))
            self.fullText = fullText
            self.cursorLocation = safeCursor
            self.prefix = ns.substring(to: safeCursor)
            self.suffix = ns.substring(from: safeCursor)
        }

        struct Splice {
            let text: String
            let caret: Int
        }

        /// Insert `transcript` at the original caret, adding a single space
        /// on each side only when neither neighbour already provides
        /// whitespace. Returns the caret position right after the insertion.
        func splicing(_ transcript: String) -> Splice {
            let leading = Self.needsSpace(after: prefix, before: transcript) ? " " : ""
            let trailing = Self.needsSpace(after: transcript, before: suffix) ? " " : ""
            let combined = prefix + leading + transcript + trailing + suffix
            let caret = (prefix as NSString).length
                + (leading as NSString).length
                + (transcript as NSString).length
            return Splice(text: combined, caret: caret)
        }

        private static func needsSpace(after left: String, before right: String) -> Bool {
            guard !left.isEmpty, !right.isEmpty else { return false }
            let leftEndsWhitespace = left.last?.isWhitespace ?? false
            let rightStartsWhitespace = right.first?.isWhitespace ?? false
            return !leftEndsWhitespace && !rightStartsWhitespace
        }
    }

    private var reviewBeforePaste: Bool {
        UserDefaults.standard.bool(forKey: "review.beforePaste")
    }

    private init() {
        Task.detached(priority: .utility) {
            await VoiceActivityGate.shared.prewarm()
        }
    }

    func installHotkey() {
        registerCurrentBinding()
        HotkeyStore.shared.onChange = { [weak self] in
            Task { @MainActor in self?.registerCurrentBinding() }
        }
    }

    func retryHotkeyRegistrationIfNeeded() {
        guard !HotkeyManager.shared.isRegistered else { return }
        registerCurrentBinding()
    }

    private func registerCurrentBinding() {
        let binding = HotkeyStore.shared.binding
        HotkeyManager.shared.register(binding: binding) { [weak self] event in
            Task { @MainActor in self?.handleHotkeyEvent(event) }
        }
    }

    func toggle() {
        AppLog.dictation.info("toggle called, current state=\(String(describing: self.state))")
        performHotkeyAction(
            DictationHotkeyPolicy.action(
                mode: .toggle,
                state: hotkeyState,
                event: .pressed
            )
        )
    }

    func handleHotkeyEvent(_ event: DictationHotkeyEvent) {
        AppLog.dictation.info("hotkey event \(String(describing: event)), current state=\(String(describing: self.state))")
        let mode = HotkeyStore.shared.mode
        let events = standaloneModifierEventCoordinator.normalize(
            event: event,
            mode: mode,
            state: hotkeyState
        )
        for normalizedEvent in events {
            handleNormalizedHotkeyEvent(normalizedEvent, mode: mode)
        }
    }

    private func handleNormalizedHotkeyEvent(
        _ event: DictationHotkeyEvent,
        mode: RecordingShortcutMode
    ) {
        if event == .cancel, recordingStartGate.hasActiveStart {
            cancelPendingRecording()
            return
        }

        if mode == .hold {
            if event == .pressed, recordingStartGate.hasPendingHoldStart {
                return
            }
            if event == .released, recordingStartGate.hasPendingHoldStart {
                cancelPendingRecording()
                return
            }
        }

        let action = DictationHotkeyPolicy.action(
            mode: mode,
            state: hotkeyState,
            event: event
        )
        performHotkeyAction(action, pendingHoldStart: mode == .hold && action == .startRecording)
    }

    private var hotkeyState: DictationHotkeyState {
        switch state {
        case .idle: return .idle
        case .preparing: return .preparing
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .reviewing: return .reviewing
        case .error: return .error
        }
    }

    private func performHotkeyAction(
        _ action: DictationHotkeyAction,
        pendingHoldStart: Bool = false
    ) {
        switch action {
        case .startRecording:
            guard AccessibilityPermission.isGranted else {
                AccessibilityPermission.promptForPermission()
                AppLog.dictation.warning("Missing Accessibility permission, could not start global hotkey recording")
                state = .error("Accessibility permission needed. Grant it in System Settings → Privacy & Security → Accessibility.")
                return
            }
            let startID = recordingStartGate.beginStart(pendingHold: pendingHoldStart)
            Task { await startRecording(startID: startID) }
        case .stopAndTranscribe:
            Task { await stopAndTranscribe() }
        case .confirmPaste:
            confirmPaste()
        case .cancelRecording:
            cancelRecording()
        case .cancelPendingRecording:
            cancelPendingRecording()
        case .none:
            break
        }
    }

    private func cancelRecording() {
        guard state == .recording else { return }
        AppLog.dictation.info("Recording cancelled")
        stopRecording(cancelledByEscape: false)
    }

    private func cancelRecordingFromEscape() {
        guard state == .recording else { return }
        AppLog.dictation.info("Recording cancelled by Escape")
        stopRecording(cancelledByEscape: true)
    }

    private func stopRecording(cancelledByEscape: Bool) {
        standaloneModifierEventCoordinator.reset()
        recordingStartGate.reset()
        stopElapsedTicker()
        if !cancelledByEscape {
            removeRecordingEscMonitors()
        }
        _ = recorder.stop()
        finishRecordingSession(fallbackTo: .idle)
    }

    private func cancelPendingRecording() {
        AppLog.dictation.info("Pending recording cancelled")
        standaloneModifierEventCoordinator.reset()
        recordingStartGate.cancelActiveStart()
        if case .preparing = state {
            finishRecordingSession(fallbackTo: .idle)
        }
    }

    private func cancelReview() {
        guard case .reviewing = state else { return }
        AppLog.dictation.info("Review cancelled")
        removeReviewEscMonitor()
        LiveHUDPanel.shared.hide()
        state = .idle
    }

    private func installRecordingEscMonitors() -> Bool {
        removeRecordingEscMonitors()
        let escapeSwallowState = recordingEscapeSwallowState
        let allowedModifierFlags = recordingEscapeAllowedModifierFlags
        let recordingShortcutKeyCode = recordingEscapeShortcutKeyCode
        recordingLocalEscMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.type == .keyUp,
               RecordingEscapePolicy.isEscape(keyCode: event.keyCode),
               escapeSwallowState.finishIfNeeded() {
                Task { @MainActor in self?.removeRecordingEscMonitors() }
                return nil
            }

            guard RecordingEscapePolicy.shouldStartCancel(
                isKeyDown: event.type == .keyDown,
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                allowedModifierFlags: allowedModifierFlags,
                recordingShortcutKeyCode: recordingShortcutKeyCode
            ) else { return event }
            if escapeSwallowState.begin() {
                Task { @MainActor in self?.cancelRecordingFromEscape() }
            }
            return nil
        }

        let context = RecordingEscapeEventTapContext(
            controller: self,
            swallowState: recordingEscapeSwallowState,
            allowedModifierFlags: allowedModifierFlags,
            recordingShortcutKeyCode: recordingShortcutKeyCode
        )
        recordingEscEventTapContext = context
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<RecordingEscapeEventTapContext>.fromOpaque(userData).takeUnretainedValue()
                guard let controller = context.controller else { return Unmanaged.passUnretained(event) }

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { controller.enableRecordingEscEventTap() }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                if type == .keyUp,
                   RecordingEscapePolicy.isEscape(keyCode: keyCode),
                   context.swallowState.finishIfNeeded() {
                    DispatchQueue.main.async { controller.removeRecordingEscMonitors() }
                    return nil
                }

                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                guard RecordingEscapePolicy.shouldStartCancel(
                    isKeyDown: type == .keyDown,
                    keyCode: keyCode,
                    modifierFlags: flags,
                    allowedModifierFlags: context.allowedModifierFlags,
                    recordingShortcutKeyCode: context.recordingShortcutKeyCode
                ) else {
                    return Unmanaged.passUnretained(event)
                }

                if context.swallowState.begin() {
                    DispatchQueue.main.async { controller.cancelRecordingFromEscape() }
                }
                return nil
            },
            userInfo: contextPtr
        ) else {
            AppLog.dictation.error("Recording Escape event tap creation failed")
            removeRecordingEscMonitors()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        recordingEscEventTap = tap
        recordingEscRunLoopSource = source
        enableRecordingEscEventTap()
        return true
    }

    private var recordingEscapeAllowedModifierFlags: NSEvent.ModifierFlags {
        guard HotkeyStore.shared.mode == .hold else { return [] }
        return Self.eventModifierFlags(forCarbonModifiers: HotkeyStore.shared.binding.modifiers)
    }

    private var recordingEscapeShortcutKeyCode: UInt16? {
        guard HotkeyStore.shared.mode == .hold else { return nil }
        return UInt16(truncatingIfNeeded: HotkeyStore.shared.binding.keyCode)
    }

    private static func eventModifierFlags(forCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    private func enableRecordingEscEventTap() {
        guard let recordingEscEventTap else { return }
        CGEvent.tapEnable(tap: recordingEscEventTap, enable: true)
    }

    private func removeRecordingEscMonitors() {
        recordingEscapeSwallowState.reset()
        if let recordingLocalEscMonitor {
            NSEvent.removeMonitor(recordingLocalEscMonitor)
            self.recordingLocalEscMonitor = nil
        }
        if let recordingEscRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), recordingEscRunLoopSource, .commonModes)
            self.recordingEscRunLoopSource = nil
        }
        if let recordingEscEventTap {
            CFMachPortInvalidate(recordingEscEventTap)
            self.recordingEscEventTap = nil
        }
        recordingEscEventTapContext = nil
    }

    private func installReviewEscMonitor() {
        removeReviewEscMonitor()
        // Local monitor: our review panel is key, so Esc is dispatched into our app.
        reviewEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in self?.cancelReview() }
                return nil
            }
            // ⌘R resumes recording with the new transcript spliced at the caret.
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "r" {
                Task { @MainActor in self?.resumeRecording() }
                return nil
            }
            return event
        }
    }

    private func removeReviewEscMonitor() {
        if let reviewEscMonitor {
            NSEvent.removeMonitor(reviewEscMonitor)
            self.reviewEscMonitor = nil
        }
    }

    // MARK: - Start

    private func startRecording(startID: RecordingStartGate.StartID) async {
        guard recordingStartGate.accepts(startID) else { return }
        AppLog.dictation.info("startRecording: requesting mic permission (current=\(String(describing: MicPermission.status.rawValue)))")
        let granted = await MicPermission.request()
        AppLog.dictation.info("startRecording: mic permission granted=\(granted)")
        guard recordingStartGate.accepts(startID) else { return }
        guard granted else {
            recordingStartGate.finish(startID)
            state = .error("Microphone access denied. Grant it in System Settings → Privacy → Microphone.")
            return
        }

        guard let descriptor = ModelRegistry.shared.activeModel else {
            AppLog.dictation.error("startRecording: no active model")
            recordingStartGate.finish(startID)
            state = .error("No active model selected.")
            return
        }

        AppLog.dictation.info("startRecording: active model=\(descriptor.id)")
        guard recordingStartGate.accepts(startID) else { return }
        state = .preparing(modelDisplayName: descriptor.displayName)
        let preparedModel = await ModelRegistry.shared.prepareModel(id: descriptor.id)
        guard recordingStartGate.accepts(startID) else { return }
        guard preparedModel != nil else {
            AppLog.dictation.error("startRecording: prepareModel returned nil")
            recordingStartGate.finish(startID)
            state = .error(preparationErrorMessage(for: descriptor))
            return
        }

        do {
            guard recordingStartGate.accepts(startID) else { return }
            recorder.onConfigurationChange = { [weak self] in
                self?.handleAudioConfigurationChange()
            }
            recorder.onLevel = { level in
                LiveHUDPanel.shared.setLevel(level)
            }
            try recorder.start()
            state = .recording
            recordingStartGate.finish(startID)
            let start = Date()
            recordStart = start
            LiveHUDPanel.shared.show()
            guard installRecordingEscMonitors() else {
                _ = recorder.stop()
                LiveHUDPanel.shared.hide()
                state = .error("Esc cancel could not be enabled. Check Accessibility or Input Monitoring in System Settings, then try again.")
                return
            }
            startElapsedTicker(from: start)
            AppLog.dictation.info("startRecording: recording started")
        } catch {
            recordingStartGate.finish(startID)
            AppLog.dictation.error("Recorder start failed: \(error.localizedDescription)")
            state = .error("Could not start recording: \(error.localizedDescription)")
        }
    }

    private func startElapsedTicker(from start: Date) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .recording else { return }
                LiveHUDPanel.shared.setElapsed(Date().timeIntervalSince(start))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopElapsedTicker() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private func handleAudioConfigurationChange() {
        guard state == .recording else { return }
        AppLog.dictation.warning("Audio configuration changed mid-recording; bailing out")
        standaloneModifierEventCoordinator.reset()
        recordingStartGate.reset()
        stopElapsedTicker()
        removeRecordingEscMonitors()
        finishRecordingSession(fallbackTo: .error("Audio input device changed. Try again."))
    }

    private func preparationErrorMessage(for descriptor: ModelDescriptor) -> String {
        if case .failed(let reason) = ModelRegistry.shared.readiness(for: descriptor.id) {
            return "Failed to load \(descriptor.displayName): \(reason)"
        }
        return "Failed to load \(descriptor.displayName)."
    }

    // MARK: - Stop

    private func stopAndTranscribe() async {
        standaloneModifierEventCoordinator.reset()
        recordingStartGate.reset()
        stopElapsedTicker()
        removeRecordingEscMonitors()
        let samples = await recorder.flushAndStop()
        AppLog.dictation.info("Captured \(samples.count) samples (\(Double(samples.count) / AudioConfig.targetSampleRate, format: .fixed(precision: 2))s)")

        guard !samples.isEmpty,
              samples.count >= DictationConfig.minTranscribeSamples,
              let descriptor = ModelRegistry.shared.activeModel else {
            finishRecordingSession(
                fallbackTo: .idle,
                resumeBanner: "Recording too short — try again."
            )
            return
        }

        state = .transcribing

        let voiced = await VoiceActivityGate.shared.isVoiced(samples)
        guard voiced else {
            AppLog.dictation.info("Full buffer VAD silent; dropping")
            finishRecordingSession(
                fallbackTo: .idle,
                resumeBanner: "No speech detected — try again."
            )
            return
        }

        guard let engine = await ModelRegistry.shared.prepareModel(id: descriptor.id) else {
            finishRecordingSession(fallbackTo: .error("Failed to prepare model for transcription."))
            return
        }

        let rawText: String
        do {
            AppLog.dictation.info("Transcribing full buffer: \(samples.count) samples")
            rawText = try await engine.transcribe(samples: samples, contextPrompt: nil)
        } catch {
            AppLog.dictation.error("Transcription failed: \(error.localizedDescription)")
            finishRecordingSession(fallbackTo: .error("Transcription failed: \(error.localizedDescription)"))
            return
        }

        let processed = TranscriptPostProcessor.process(rawText)
        if processed.isEmpty {
            finishRecordingSession(fallbackTo: .error("Transcription returned empty text. Try speaking closer to the mic."))
            return
        }

        // Resume always returns to review with the new transcript spliced at
        // the original caret; otherwise honor the user's review preference.
        if let resume = resumeContext {
            resumeContext = nil
            let spliced = resume.splicing(processed)
            enterReview(text: spliced.text, cursorLocation: spliced.caret)
        } else if reviewBeforePaste {
            enterReview(text: processed)
        } else {
            LiveHUDPanel.shared.hide()
            deliver(text: processed)
        }
    }

    // MARK: - Review flow

    private func enterReview(
        text: String,
        cursorLocation: Int? = nil,
        banner: String? = nil
    ) {
        state = .reviewing(text: text)
        LiveHUDPanel.shared.showReview(
            text: text,
            cursorLocation: cursorLocation,
            banner: banner,
            onPaste: { [weak self] in self?.confirmPaste() },
            onCancel: { [weak self] in self?.cancelReview() },
            onResume: { [weak self] in self?.resumeRecording() }
        )
        installReviewEscMonitor()
    }

    private func resumeRecording() {
        guard case .reviewing = state else { return }

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.promptForPermission()
            AppLog.dictation.warning("Missing Accessibility permission, could not resume recording")
            state = .error("Accessibility permission needed. Grant it in System Settings → Privacy & Security → Accessibility.")
            return
        }

        let context = ResumeContext(
            fullText: LiveHUDPanel.shared.currentReviewText,
            cursorLocation: LiveHUDPanel.shared.currentCursorLocation
        )
        AppLog.dictation.info("Resuming recording at cursor=\(context.cursorLocation) (prefix=\(context.prefix.count)ch, suffix=\(context.suffix.count)ch)")
        resumeContext = context
        removeReviewEscMonitor()

        let startID = recordingStartGate.beginStart(pendingHold: false)
        Task { await startRecording(startID: startID) }
    }

    /// Common cleanup after stopping a recording: when a resume is in flight,
    /// restore the review HUD with the user's original text and caret;
    /// otherwise hide the HUD and transition to `fallbackState`.
    ///
    /// `resumeBanner` surfaces a one-line notice in the restored Review HUD
    /// so the user sees *why* nothing was appended — without it, silent drops
    /// look like the app simply ate the recording (and any API charges).
    private func finishRecordingSession(
        fallbackTo fallbackState: State,
        resumeBanner: String? = nil
    ) {
        if let resume = resumeContext {
            resumeContext = nil
            let banner = resumeBanner ?? Self.errorMessage(from: fallbackState)
            enterReview(
                text: resume.fullText,
                cursorLocation: resume.cursorLocation,
                banner: banner
            )
            return
        }
        LiveHUDPanel.shared.hide()
        state = fallbackState
    }

    private static func errorMessage(from state: State) -> String? {
        if case .error(let message) = state { return message }
        return nil
    }

    private func confirmPaste() {
        guard case .reviewing = state else { return }
        let edited = LiveHUDPanel.shared.currentReviewText
        removeReviewEscMonitor()
        LiveHUDPanel.shared.hide()

        // Key status is released back to the previous app when our panel is
        // ordered out, AND we must not synthesize Cmd+V while the user is
        // still holding any modifier from the hotkey chord (e.g. ⌥ in ⌥Space):
        // otherwise Cmd+V becomes Cmd+Opt+V and most apps ignore or remap it,
        // so the text appears to vanish.
        Task { @MainActor [weak self] in
            await Self.waitForModifiersClear()
            self?.deliver(text: edited)
        }
    }

    private static func waitForModifiersClear() async {
        let deadline = ContinuousClock.now.advanced(by: PasteTiming.maxModifierWait)
        while !NSEvent.modifierFlags.intersection(PasteTiming.trackedModifiers).isEmpty,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: PasteTiming.pollInterval)
        }
        // Pad so the previously-focused app fully accepts first-responder
        // status before the synthetic Cmd+V key event lands.
        try? await Task.sleep(for: PasteTiming.focusSettleDelay)
    }

    private enum PasteTiming {
        static let trackedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        static let pollInterval: Duration = .milliseconds(15)
        static let maxModifierWait: Duration = .milliseconds(400)
        static let focusSettleDelay: Duration = .milliseconds(40)
    }

    // MARK: - Output

    private func deliver(text: String) {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.promptForPermission()
            AppLog.dictation.warning("Missing Accessibility permission, could not type: \(text)")
            state = .error("Accessibility permission needed. Grant it in System Settings → Privacy & Security → Accessibility.")
            return
        }

        KeystrokeOutput.type(text)
        state = .idle
    }
}
