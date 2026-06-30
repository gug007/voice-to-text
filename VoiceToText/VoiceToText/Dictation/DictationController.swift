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
    private var transcribingElapsedTask: Task<Void, Never>?
    /// Backstop that forces recovery if the machine wedges in `.transcribing`
    /// (a CoreML/VAD inference or network read that never returns). Without it
    /// the hotkey policy maps every press to `.none` and only relaunch recovers.
    private var transcribingWatchdog: Task<Void, Never>?
    /// Bumped on each entry into `.transcribing` and on watchdog recovery so a
    /// late-returning pipeline can't clobber a newer state after the watchdog
    /// (or a newer run) has already moved on.
    @ObservationIgnored
    private var transcriptionRunID: UInt64 = 0
    /// Audio of the transcription currently in flight, kept so a watchdog
    /// recovery can preserve it and offer Retry instead of silently dropping a
    /// possibly-valid recording. Overwritten on each run.
    @ObservationIgnored
    private var inFlightTranscriptionSamples: [Float]?
    /// Generous backstop: local engines emit no transcribe progress, so this
    /// can't reset on liveness. Sized well beyond any realistic transcription so
    /// it only catches a genuine wedge; a false fire still preserves the audio.
    private static let transcribingWatchdogTimeout: Duration = .seconds(600)
    private var reviewEscMonitor: Any?
    private var failureEscMonitor: Any?
    private var recordingLocalEscMonitor: Any?
    private var recordingEscEventTap: CFMachPort?
    private var recordingEscRunLoopSource: CFRunLoopSource?
    private var recordingEscEventTapContext: RecordingEscapeEventTapContext?
    @ObservationIgnored
    private let recordingEscapeSwallowState = RecordingEscapeSwallowState()
    private var recordingStartGate = RecordingStartGate()
    private var standaloneModifierEventCoordinator = StandaloneModifierEventCoordinator()
    private var resumeContext: ResumeContext?
    /// Audio kept around after a recoverable transcription failure so the
    /// user's Retry button can re-run the pipeline on the same samples
    /// (e.g. after a network blip). Backs both the failure HUD's Retry and
    /// the review banner's Retry after a failed Resume take. Cleared on
    /// success, dismissal, paste, review cancel, or when a new recording
    /// starts.
    private var lastFailedSamples: [Float]?

    /// In-flight AI action transform on the review text. Cancelled whenever
    /// the review session ends (paste, cancel, resume) so a slow response
    /// can't rewrite text the user already acted on. The generation counter
    /// keeps a cancelled task's cleanup from clobbering a newer run's state.
    @ObservationIgnored
    private var reviewActionTask: Task<Void, Never>?
    @ObservationIgnored
    private var reviewActionGeneration = 0

    /// The active live-streaming session, when the selected engine streams
    /// (e.g. ElevenLabs). Audio is piped to it during recording and it produces
    /// the final transcript via `finishStream()`. Nil for buffered engines and
    /// on the retry path (which falls back to buffered `transcribe`).
    @ObservationIgnored
    private var streamingEngine: (any StreamingTranscriptionEngine)?

    /// The model that owns the active streaming session, captured at recording
    /// start. Used for History attribution because a streaming transcript is
    /// produced by the already-open session, not by whatever model is active at
    /// stop time (the user can switch models mid-recording).
    @ObservationIgnored
    private var streamingModel: ModelDescriptor?

    /// History entry ids for the current review session's takes that haven't
    /// been committed yet. Each successful take is saved immediately (so audio
    /// and transcript stay paired), but if the user discards the review the
    /// entries are retracted — a Cancel must not leave the audio on disk.
    @ObservationIgnored
    private var pendingHistoryIDs: [UUID] = []

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
        installHotkeyHealthObservers()
    }

    /// Headless recovery for the standalone-modifier event tap, which the OS can
    /// silently invalidate (sleep/wake, fast-user-switch, Input-Monitoring/TCC
    /// change) without `retryHotkeyRegistrationIfNeeded`'s window-bound callers
    /// ever firing. Re-checks tap liveness on the events that accompany those
    /// transitions. No-op for the default Carbon hotkey, which can't die this way.
    private func installHotkeyHealthObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retryHotkeyRegistrationIfNeeded() }
            }
        }
    }

    func retryHotkeyRegistrationIfNeeded() {
        guard !HotkeyManager.shared.isHealthy else { return }
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

    /// Commands accepted from external triggers via the `voicetotext://` URL
    /// scheme. The URL host selects the command, e.g. `voicetotext://toggle`.
    /// Unknown or missing commands fall back to `.toggle`.
    enum ExternalCommand: String, CaseIterable {
        case toggle
        case start
        case stop
        case cancel

        init(url: URL) {
            let host = url.host.flatMap { $0.isEmpty ? nil : $0 }
            let raw = host ?? url.pathComponents.first { $0 != "/" }
            self = raw.flatMap { ExternalCommand(rawValue: $0.lowercased()) } ?? .toggle
        }
    }

    /// Entry point for external triggers (URL scheme). Routes through the same
    /// state-aware policy the global hotkey uses, so behaviour matches exactly.
    /// This never activates the app, so the transcript still pastes into the
    /// frontmost app — i.e. the one whose button was tapped.
    func handleExternalCommand(_ command: ExternalCommand) {
        AppLog.dictation.info(
            "external command \(command.rawValue), current state=\(String(describing: self.state))"
        )
        switch command {
        case .toggle:
            toggle()
        case .start:
            // Start only from a resting state; ignore if already busy.
            switch state {
            case .idle, .error:
                performHotkeyAction(.startRecording)
            default:
                break
            }
        case .stop:
            // Stop & transcribe only while actively recording.
            guard case .recording = state else { return }
            performHotkeyAction(.stopAndTranscribe)
        case .cancel:
            if recordingStartGate.hasActiveStart {
                cancelPendingRecording()
                return
            }
            performHotkeyAction(
                DictationHotkeyPolicy.action(mode: .toggle, state: hotkeyState, event: .cancel)
            )
        }
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
        cancelStreamingSession()
        finishRecordingSession(fallbackTo: .idle)
    }

    /// Stops feeding audio to a live-streaming engine and cancels its session
    /// without producing a transcript. Safe to call when no stream is active.
    /// Used on every recording exit path that isn't a normal finish.
    private func cancelStreamingSession() {
        recorder.onAudioChunk = nil
        streamingModel = nil
        guard let streaming = streamingEngine else { return }
        streamingEngine = nil
        Task { await streaming.cancelStream() }
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
        cancelReviewAction()
        removeReviewEscMonitor()
        lastFailedSamples = nil
        // The user discarded this dictation — pull its takes back out of History.
        discardPendingHistory()
        LiveHUDPanel.shared.hide()
        state = .idle
    }

    /// Keeps the current review session's saved takes in History.
    private func commitPendingHistory() {
        pendingHistoryIDs.removeAll()
    }

    /// Retracts (deletes) the current review session's saved takes, for when
    /// the user discards the dictation instead of keeping it.
    private func discardPendingHistory() {
        for id in pendingHistoryIDs {
            RecordingHistoryStore.shared.delete(id: id)
        }
        pendingHistoryIDs.removeAll()
    }

    private func dismissFailure() {
        guard case .error = state else { return }
        AppLog.dictation.info("Failure HUD dismissed")
        removeFailureEscMonitor()
        lastFailedSamples = nil
        // Safety net: a discarded session shouldn't leave takes behind.
        discardPendingHistory()
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
            // ⌘1–⌘9 run the matching review action. Matched by physical key
            // (kVK_ANSI_*) so layouts with shifted digit rows (e.g. AZERTY)
            // work; checked synchronously against this session's snapshot so
            // the shortcut always mirrors the visible chips and the event
            // passes through untouched otherwise; scoped to the review panel
            // so keystrokes in Settings can't rewrite the transcript.
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               let digit = Self.reviewActionDigitKeyCodes[event.keyCode] {
                let handlesDigit = MainActor.assumeIsolated {
                    LiveHUDPanel.shared.isReviewPanelEvent(event)
                        && LiveHUDState.shared.reviewShowsActions
                        && LiveHUDState.shared.reviewActions.indices.contains(digit - 1)
                }
                guard handlesDigit else { return event }
                Task { @MainActor in self?.runReviewAction(atIndex: digit - 1) }
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

    /// Failure HUD shares the key-accepting review panel, so Esc and Return
    /// land as local key events: Esc dismisses, Return retries (when retry
    /// is available — guarded by `lastFailedSamples`).
    private func installFailureEscMonitor() {
        removeFailureEscMonitor()
        failureEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in self?.dismissFailure() }
                return nil
            }
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                Task { @MainActor in self?.retryTranscription() }
                return nil
            }
            return event
        }
    }

    private func removeFailureEscMonitor() {
        if let failureEscMonitor {
            NSEvent.removeMonitor(failureEscMonitor)
            self.failureEscMonitor = nil
        }
    }

    // MARK: - Start

    private func startRecording(startID: RecordingStartGate.StartID) async {
        guard recordingStartGate.accepts(startID) else { return }
        removeFailureEscMonitor()
        lastFailedSamples = nil
        // A fresh dictation (not a Resume) starts a new review session: forget
        // any uncommitted history ids left over from a prior session so they
        // aren't retracted by this one's Cancel. (Resume keeps accumulating.)
        if resumeContext == nil { pendingHistoryIDs.removeAll() }
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
        guard let engine = preparedModel else {
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

            // Live-streaming engines: open the session and pipe audio in as it's
            // captured so partial transcripts show in the HUD while recording.
            // If the session can't open (auth/network), fall back to buffered.
            streamingEngine = nil
            streamingModel = nil
            recorder.onAudioChunk = nil
            if let streaming = engine as? any StreamingTranscriptionEngine {
                do {
                    try await streaming.startStream(contextPrompt: nil) { live in
                        Task { @MainActor in LiveHUDPanel.shared.setPartialTranscript(live) }
                    }
                    guard recordingStartGate.accepts(startID) else {
                        await streaming.cancelStream()
                        return
                    }
                    streamingEngine = streaming
                    streamingModel = descriptor
                    recorder.onAudioChunk = { samples in
                        streaming.feedAudio(samples)
                    }
                } catch {
                    AppLog.dictation.error("ElevenLabs stream failed to open: \(error.localizedDescription); using buffered transcription")
                }
            }

            try recorder.start()
            state = .recording
            recordingStartGate.finish(startID)
            let start = Date()
            recordStart = start
            // Resuming from review: keep the prior transcript on screen and
            // stream new words in at the caret, instead of the fresh-recording
            // HUD which clears the screen.
            if let resume = resumeContext {
                LiveHUDPanel.shared.showResumeRecording(
                    prefix: resume.prefix,
                    suffix: resume.suffix,
                    showsLiveText: streamingEngine != nil
                )
            } else {
                LiveHUDPanel.shared.show(
                    showsLiveText: streamingEngine != nil,
                    onStop: { [weak self] in Task { await self?.stopAndTranscribe() } },
                    onCancel: { [weak self] in self?.cancelRecording() }
                )
            }
            guard installRecordingEscMonitors() else {
                _ = recorder.stop()
                cancelStreamingSession()
                LiveHUDPanel.shared.hide()
                state = .error("Esc cancel could not be enabled. Check Accessibility or Input Monitoring in System Settings, then try again.")
                return
            }
            startElapsedTicker(from: start)
            AppLog.dictation.info("startRecording: recording started")
        } catch {
            recordingStartGate.finish(startID)
            cancelStreamingSession()
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

    private func enterTranscribing() {
        // Idempotent: retryTranscription enters transcribing synchronously
        // to close a state-race, and runTranscriptionPipeline calls this
        // again on its normal path. Skipping the duplicate keeps the elapsed
        // ticker from resetting to 0 mid-retry.
        guard state != .transcribing else { return }
        transcriptionRunID &+= 1
        state = .transcribing
        LiveHUDPanel.shared.showTranscribing()
        startTranscribingElapsedTicker(from: Date())
        armTranscribingWatchdog(runID: transcriptionRunID)
    }

    private func armTranscribingWatchdog(runID: UInt64) {
        transcribingWatchdog?.cancel()
        transcribingWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.transcribingWatchdogTimeout)
            guard let self, !Task.isCancelled,
                  self.state == .transcribing,
                  self.transcriptionRunID == runID else { return }
            AppLog.dictation.error("Transcription watchdog fired; forcing recovery")
            self.recoverFromStuckTranscribing()
        }
    }

    /// Forces the machine out of a wedged `.transcribing` so the hotkey works
    /// again. Fences the in-flight pipeline (bumping the run ID), tears down any
    /// streaming session, and surfaces a recoverable failure (which lands in
    /// `.error`/`.reviewing` — both re-arm the hotkey per the policy).
    private func recoverFromStuckTranscribing() {
        transcriptionRunID &+= 1
        stopTranscribingElapsedTicker()
        cancelStreamingSession()
        let samples = inFlightTranscriptionSamples
        enterFailureHUD(
            message: "Transcription is taking too long. Try again.",
            samples: samples,
            canRetry: samples != nil
        )
    }

    private func startTranscribingElapsedTicker(from start: Date) {
        transcribingElapsedTask?.cancel()
        transcribingElapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .transcribing else { return }
                LiveHUDPanel.shared.setTranscribingElapsed(Date().timeIntervalSince(start))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopTranscribingElapsedTicker() {
        transcribingElapsedTask?.cancel()
        transcribingElapsedTask = nil
        transcribingWatchdog?.cancel()
        transcribingWatchdog = nil
    }

    private func handleAudioConfigurationChange() {
        guard state == .recording else { return }
        AppLog.dictation.warning("Audio configuration changed mid-recording; bailing out")
        standaloneModifierEventCoordinator.reset()
        recordingStartGate.reset()
        stopElapsedTicker()
        removeRecordingEscMonitors()
        cancelStreamingSession()
        enterFailureHUD(message: "Audio input device changed. Try again.")
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
              samples.count >= DictationConfig.minTranscribeSamples else {
            enterFailureHUD(message: "Recording too short — try again.")
            return
        }

        await runTranscriptionPipeline(samples: samples)
    }

    private func retryTranscription() {
        guard case .error = state, let samples = lastFailedSamples else { return }
        AppLog.dictation.info("Retrying transcription on \(samples.count) cached samples")
        removeFailureEscMonitor()
        lastFailedSamples = nil
        // Synchronously transition to .transcribing so a hotkey press queued
        // between this click and the Task firing maps to .none (per policy)
        // instead of starting a competing recording that would race with the
        // pipeline's own enterTranscribing call below.
        enterTranscribing()
        Task { await runTranscriptionPipeline(samples: samples) }
    }

    /// Retry for a failed Resume take: the review HUD is back up showing the
    /// prior text with a failure banner, and the failed take's audio sits in
    /// `lastFailedSamples`. Rebuilds the splice context from the *current*
    /// text and caret — the user may have edited while the banner was showing
    /// — then re-runs the pipeline on the stashed samples, so on success the
    /// take lands at the caret exactly like a successful Resume would have.
    private func retryFailedResumeTranscription() {
        guard case .reviewing = state, let samples = lastFailedSamples else { return }
        AppLog.dictation.info("Retrying failed resume transcription on \(samples.count) cached samples")
        cancelReviewAction()
        lastFailedSamples = nil
        resumeContext = ResumeContext(
            fullText: LiveHUDPanel.shared.currentReviewText,
            cursorLocation: LiveHUDPanel.shared.currentCursorLocation
        )
        removeReviewEscMonitor()
        enterTranscribing()
        Task { await runTranscriptionPipeline(samples: samples) }
    }

    /// Runs VAD + transcription + post-processing on the given audio.
    /// On any recoverable failure, surfaces the error through the failure
    /// HUD with Retry; on success, hands off to the review/deliver flow.
    /// Reusable across first-pass and retry so they share one code path.
    private func runTranscriptionPipeline(samples: [Float]) async {
        guard let descriptor = ModelRegistry.shared.activeModel else {
            enterFailureHUD(message: "No active model selected.")
            return
        }

        enterTranscribing()
        let runID = transcriptionRunID
        inFlightTranscriptionSamples = samples
        defer { stopTranscribingElapsedTicker() }

        let voiced = await VoiceActivityGate.shared.isVoiced(samples)
        guard runID == transcriptionRunID else { return }
        guard voiced else {
            AppLog.dictation.info("Full buffer VAD silent; dropping")
            cancelStreamingSession()
            enterFailureHUD(message: "No speech detected — try again.")
            return
        }

        // Pick how the final transcript is produced: flush the live stream if
        // one is active, otherwise transcribe the buffered samples (local
        // engines, or a retry of a failed stream). Both share one error path.
        // The model that actually produces this transcript — for History
        // attribution. A streaming transcript comes from the session opened at
        // recording start (its model captured then), not whatever is active now.
        let recordedModel: ModelDescriptor
        let produce: () async throws -> String
        if let streaming = streamingEngine {
            // The audio source is done, so stop feeding it. finishStream tears
            // the socket down itself — this isn't a cancelStreamingSession case.
            streamingEngine = nil
            recordedModel = streamingModel ?? descriptor
            streamingModel = nil
            recorder.onAudioChunk = nil
            AppLog.dictation.info("Finishing live stream transcription")
            produce = { try await streaming.finishStream() }
        } else {
            recordedModel = descriptor
            guard let engine = await ModelRegistry.shared.prepareModel(id: descriptor.id) else {
                enterFailureHUD(
                    message: "Failed to prepare model for transcription.",
                    samples: samples,
                    canRetry: true
                )
                return
            }
            AppLog.dictation.info("Transcribing full buffer: \(samples.count) samples")
            produce = {
                try await engine.transcribe(
                    samples: samples,
                    contextPrompt: nil,
                    progress: { current, total in
                        Task { @MainActor in
                            LiveHUDPanel.shared.setTranscribingProgress(current: current, total: total)
                        }
                    }
                )
            }
        }

        let rawText: String
        do {
            rawText = try await produce()
        } catch {
            guard runID == transcriptionRunID else { return }
            AppLog.dictation.error("Transcription failed: \(error.localizedDescription)")
            enterFailureHUD(
                message: Self.transcriptionFailureMessage(for: error),
                samples: samples,
                canRetry: true
            )
            return
        }
        guard runID == transcriptionRunID else { return }

        let processed = TranscriptPostProcessor.process(rawText)
        if processed.isEmpty {
            enterFailureHUD(
                message: "Transcription returned empty text. Try speaking closer to the mic.",
                samples: samples,
                canRetry: true
            )
            return
        }

        lastFailedSamples = nil

        // Save the finished recording + transcript to History. Each take is its
        // own entry, so its audio matches its transcript exactly (Resume splices
        // text in the review buffer, but the saved audio is only this take).
        // Held as "pending" until the user keeps it (paste/deliver) so a review
        // Cancel can retract it — discarded dictation must not stay on disk.
        if let id = RecordingHistoryStore.shared.record(
            samples: samples,
            transcript: processed,
            model: recordedModel
        ) {
            pendingHistoryIDs.append(id)
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
            // No review step: the text is delivered and kept right away.
            commitPendingHistory()
            LiveHUDPanel.shared.hide()
            deliver(text: processed)
        }
    }

    /// Engine errors already read as complete sentences ("Transcription
    /// failed: …", "Model load failed: …"); only foreign errors need the
    /// prefix added for context.
    private static func transcriptionFailureMessage(for error: Error) -> String {
        if error is TranscriptionEngineError { return error.localizedDescription }
        return "Transcription failed: \(error.localizedDescription)"
    }

    /// Single entry point for transcription failures. Surfaces the error
    /// visually instead of silently hiding the HUD. When a Resume was in
    /// flight, restores the prior review text with the message as a banner —
    /// keeping the failed take's audio so the banner can offer Retry;
    /// otherwise shows the failure HUD with optional Retry. Retry is offered
    /// only when re-running the same audio could plausibly succeed.
    private func enterFailureHUD(
        message: String,
        samples: [Float]? = nil,
        canRetry: Bool = false
    ) {
        let retryAvailable = canRetry && samples != nil

        if let resume = resumeContext {
            resumeContext = nil
            lastFailedSamples = retryAvailable ? samples : nil
            var bannerRetry: (@MainActor () -> Void)?
            if retryAvailable {
                bannerRetry = { [weak self] in self?.retryFailedResumeTranscription() }
            }
            enterReview(
                text: resume.fullText,
                cursorLocation: resume.cursorLocation,
                banner: message,
                bannerRetry: bannerRetry
            )
            return
        }

        lastFailedSamples = retryAvailable ? samples : nil
        state = .error(message)

        LiveHUDPanel.shared.showFailure(
            message: message,
            canRetry: retryAvailable,
            onRetry: { [weak self] in self?.retryTranscription() },
            onCancel: { [weak self] in self?.dismissFailure() }
        )
        installFailureEscMonitor()
    }

    // MARK: - Review flow

    private func enterReview(
        text: String,
        cursorLocation: Int? = nil,
        banner: String? = nil,
        bannerRetry: (@MainActor () -> Void)? = nil
    ) {
        // Invalidate any action that slipped in during a previous session's
        // exit window (e.g. ⌘R then ⌘1 in quick succession) so a stale
        // transform can never overwrite this session's transcript.
        cancelReviewAction()
        state = .reviewing(text: text)
        LiveHUDPanel.shared.showReview(
            text: text,
            cursorLocation: cursorLocation,
            banner: banner,
            onPaste: { [weak self] in self?.confirmPaste() },
            onCancel: { [weak self] in self?.cancelReview() },
            onResume: { [weak self] in self?.resumeRecording() },
            onRetry: bannerRetry,
            onRunAction: { [weak self] action in self?.runReviewAction(action) }
        )
        installReviewEscMonitor()
    }

    // MARK: - Review actions

    /// Physical digit-row keys for ⌘1–⌘9 (kVK_ANSI_* codes are not
    /// contiguous). Positional matching keeps the shortcuts working on
    /// layouts where digits live on the shifted layer (e.g. AZERTY).
    private static let reviewActionDigitKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1, UInt16(kVK_ANSI_2): 2, UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4, UInt16(kVK_ANSI_5): 5, UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7, UInt16(kVK_ANSI_8): 8, UInt16(kVK_ANSI_9): 9,
    ]

    private func runReviewAction(atIndex index: Int) {
        let hud = LiveHUDState.shared
        guard hud.reviewShowsActions else { return }
        // ⌘1–⌘9 index into this session's snapshot, matching the chip order.
        let actions = hud.reviewActions
        guard actions.indices.contains(index) else { return }
        runReviewAction(actions[index])
    }

    /// Runs an AI action against the current review text. On success the
    /// transcript is replaced in place (with a Revert snapshot); failures
    /// surface as a banner above the editor. Paste/Cancel/Resume mid-run
    /// cancel the request and keep the text the user was looking at.
    private func runReviewAction(_ action: DictationAction) {
        guard case .reviewing = state else { return }
        // A pending resume means this review session is already on its way
        // out — don't start a transform that would race the next session.
        guard resumeContext == nil else { return }
        let hud = LiveHUDState.shared
        guard hud.runningActionId == nil else { return }
        let original = LiveHUDPanel.shared.currentReviewText
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        AppLog.dictation.info("Running review action: \(action.name)")
        reviewActionGeneration += 1
        let generation = reviewActionGeneration
        hud.reviewBanner = nil
        // Running an action dismisses a failed take's banner for good: drop
        // the retry affordance and its audio so an action-failure banner
        // can't resurrect a Retry button wired to the stale dictation take.
        hud.onRetry = nil
        lastFailedSamples = nil
        hud.runningActionId = action.id

        reviewActionTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.reviewActionGeneration == generation {
                    hud.runningActionId = nil
                    self.reviewActionTask = nil
                }
            }
            do {
                let transformed = try await ActionRunner.run(instruction: action.prompt, on: original)
                guard let self, self.reviewActionGeneration == generation,
                      case .reviewing = self.state else { return }
                // User edited the transcript while the action was in flight;
                // their edit wins — drop the now-stale transform.
                guard LiveHUDPanel.shared.currentReviewText == original else {
                    AppLog.dictation.info("Review action result dropped (text edited mid-run): \(action.name)")
                    return
                }
                // Unchanged result: applying it would only desync the recorded
                // caret from the visible one (the editor skips no-op syncs).
                guard transformed != original else {
                    AppLog.dictation.info("Review action returned unchanged text: \(action.name)")
                    return
                }
                hud.actionRevertStack.append(original)
                hud.selectedRange = NSRange(location: (transformed as NSString).length, length: 0)
                hud.reviewText = transformed
                self.state = .reviewing(text: transformed)
                AppLog.dictation.info("Review action succeeded: \(action.name)")
            } catch is CancellationError {
                // Review session ended first; nothing to surface.
            } catch {
                guard let self, self.reviewActionGeneration == generation,
                      case .reviewing = self.state else { return }
                AppLog.dictation.error("Review action failed: \(error.localizedDescription)")
                hud.reviewBanner = error.localizedDescription
            }
        }
    }

    private func cancelReviewAction() {
        reviewActionGeneration += 1
        reviewActionTask?.cancel()
        reviewActionTask = nil
        LiveHUDState.shared.runningActionId = nil
    }

    private func resumeRecording() {
        guard case .reviewing = state else { return }
        // Before any early return: a transform landing after review ends
        // would otherwise leave a shimmering chip on a dead session.
        cancelReviewAction()

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

    /// Closes a recording session when the user cancels or the session ends
    /// without producing a transcript. Restores the Review HUD if a Resume
    /// was in flight (so the prior text isn't lost), otherwise hides the
    /// HUD and returns to idle. Failures go through `enterFailureHUD` instead.
    private func finishRecordingSession(fallbackTo fallbackState: State) {
        if let resume = resumeContext {
            resumeContext = nil
            enterReview(
                text: resume.fullText,
                cursorLocation: resume.cursorLocation
            )
            return
        }
        LiveHUDPanel.shared.hide()
        state = fallbackState
    }

    private func confirmPaste() {
        guard case .reviewing = state else { return }
        cancelReviewAction()
        lastFailedSamples = nil
        // The user kept this dictation — its takes stay in History.
        commitPendingHistory()
        let edited = LiveHUDPanel.shared.currentReviewText
        removeReviewEscMonitor()
        LiveHUDPanel.shared.hide()

        // Wait for the hotkey-chord modifiers to release first — otherwise
        // Cmd+V lands as Cmd+Opt+V (or similar) and most apps drop it.
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
        // Lets the previously-focused app fully accept first-responder
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
