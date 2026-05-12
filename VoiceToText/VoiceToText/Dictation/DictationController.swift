import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

private final class RecordingEscapeEventTapContext {
    weak var controller: DictationController?
    let swallowState: RecordingEscapeSwallowState

    init(controller: DictationController, swallowState: RecordingEscapeSwallowState) {
        self.controller = controller
        self.swallowState = swallowState
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

    private func registerCurrentBinding() {
        let binding = HotkeyStore.shared.binding
        HotkeyManager.shared.register(keyCode: binding.keyCode, modifiers: binding.modifiers) { [weak self] event in
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
        recordingStartGate.reset()
        stopElapsedTicker()
        if !cancelledByEscape {
            removeRecordingEscMonitors()
        }
        _ = recorder.stop()
        LiveHUDPanel.shared.hide()
        state = .idle
    }

    private func cancelPendingRecording() {
        AppLog.dictation.info("Pending recording cancelled")
        recordingStartGate.cancelPendingHoldStart()
        if case .preparing = state {
            state = .idle
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
        recordingLocalEscMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.type == .keyUp,
               RecordingEscapePolicy.isEscape(keyCode: event.keyCode),
               escapeSwallowState.finishIfNeeded() {
                Task { @MainActor in self?.removeRecordingEscMonitors() }
                return nil
            }

            guard RecordingEscapePolicy.shouldCancel(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags
            ) else { return event }
            if escapeSwallowState.begin() {
                Task { @MainActor in self?.cancelRecordingFromEscape() }
            }
            return nil
        }

        let context = RecordingEscapeEventTapContext(
            controller: self,
            swallowState: recordingEscapeSwallowState
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
                guard RecordingEscapePolicy.shouldCancel(keyCode: keyCode, modifierFlags: flags) else {
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
        recordingStartGate.reset()
        stopElapsedTicker()
        removeRecordingEscMonitors()
        LiveHUDPanel.shared.hide()
        state = .error("Audio input device changed. Try again.")
    }

    private func preparationErrorMessage(for descriptor: ModelDescriptor) -> String {
        if case .failed(let reason) = ModelRegistry.shared.readiness(for: descriptor.id) {
            return "Failed to load \(descriptor.displayName): \(reason)"
        }
        return "Failed to load \(descriptor.displayName)."
    }

    // MARK: - Stop

    private func stopAndTranscribe() async {
        recordingStartGate.reset()
        stopElapsedTicker()
        removeRecordingEscMonitors()
        let samples = recorder.stop()
        AppLog.dictation.info("Captured \(samples.count) samples (\(Double(samples.count) / AudioConfig.targetSampleRate, format: .fixed(precision: 2))s)")

        guard !samples.isEmpty,
              samples.count >= DictationConfig.minTranscribeSamples,
              let descriptor = ModelRegistry.shared.activeModel else {
            LiveHUDPanel.shared.hide()
            state = .idle
            return
        }

        state = .transcribing

        let voiced = await VoiceActivityGate.shared.isVoiced(samples)
        guard voiced else {
            AppLog.dictation.info("Full buffer VAD silent; dropping")
            LiveHUDPanel.shared.hide()
            state = .idle
            return
        }

        guard let engine = await ModelRegistry.shared.prepareModel(id: descriptor.id) else {
            LiveHUDPanel.shared.hide()
            state = .error("Failed to prepare model for transcription.")
            return
        }

        let rawText: String
        do {
            AppLog.dictation.info("Transcribing full buffer: \(samples.count) samples")
            rawText = try await engine.transcribe(samples: samples, contextPrompt: nil)
        } catch {
            LiveHUDPanel.shared.hide()
            AppLog.dictation.error("Transcription failed: \(error.localizedDescription)")
            state = .error("Transcription failed: \(error.localizedDescription)")
            return
        }

        let processed = TranscriptPostProcessor.process(rawText)
        if processed.isEmpty {
            LiveHUDPanel.shared.hide()
            state = .error("Transcription returned empty text. Try speaking closer to the mic.")
            return
        }

        if reviewBeforePaste {
            enterReview(text: processed)
        } else {
            LiveHUDPanel.shared.hide()
            deliver(text: processed)
        }
    }

    // MARK: - Review flow

    private func enterReview(text: String) {
        state = .reviewing(text: text)
        LiveHUDPanel.shared.showReview(
            text: text,
            onPaste: { [weak self] in self?.confirmPaste() },
            onCancel: { [weak self] in self?.cancelReview() }
        )
        installReviewEscMonitor()
    }

    private func confirmPaste() {
        guard case .reviewing = state else { return }
        let edited = LiveHUDPanel.shared.currentReviewText
        removeReviewEscMonitor()
        LiveHUDPanel.shared.hide()

        // Key status is released back to the previous app when our panel is
        // ordered out; give the system a moment before simulating Cmd+V.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.deliver(text: edited)
        }
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
