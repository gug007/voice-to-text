import AppKit
import AVFoundation
import Foundation
import Observation
import OSLog

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
    private var escMonitor: Any?

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
        HotkeyStore.shared.onChange = { [weak self] _ in
            Task { @MainActor in self?.registerCurrentBinding() }
        }
    }

    private func registerCurrentBinding() {
        let binding = HotkeyStore.shared.binding
        HotkeyManager.shared.register(keyCode: binding.keyCode, modifiers: binding.modifiers) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
    }

    func toggle() {
        AppLog.dictation.info("toggle called, current state=\(String(describing: self.state))")
        switch state {
        case .idle, .error:
            Task { await startRecording() }
        case .recording:
            Task { await stopAndTranscribe() }
        case .reviewing:
            confirmPaste()
        case .preparing, .transcribing:
            break
        }
    }

    // MARK: - Start

    private func startRecording() async {
        AppLog.dictation.info("startRecording: requesting mic permission (current=\(String(describing: MicPermission.status.rawValue)))")
        let granted = await MicPermission.request()
        AppLog.dictation.info("startRecording: mic permission granted=\(granted)")
        guard granted else {
            state = .error("Microphone access denied. Grant it in System Settings → Privacy → Microphone.")
            return
        }

        guard let descriptor = ModelRegistry.shared.activeModel else {
            AppLog.dictation.error("startRecording: no active model")
            state = .error("No active model selected.")
            return
        }

        AppLog.dictation.info("startRecording: active model=\(descriptor.id)")
        state = .preparing(modelDisplayName: descriptor.displayName)
        guard await ModelRegistry.shared.prepareModel(id: descriptor.id) != nil else {
            AppLog.dictation.error("startRecording: prepareModel returned nil")
            state = .error(preparationErrorMessage(for: descriptor))
            return
        }

        do {
            recorder.onConfigurationChange = { [weak self] in
                self?.handleAudioConfigurationChange()
            }
            recorder.onLevel = { level in
                LiveHUDPanel.shared.setLevel(level)
            }
            try recorder.start()
            state = .recording
            let start = Date()
            recordStart = start
            LiveHUDPanel.shared.show()
            startElapsedTicker(from: start)
            AppLog.dictation.info("startRecording: recording started")
        } catch {
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
        stopElapsedTicker()
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
        stopElapsedTicker()
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
        installEscMonitor()
    }

    private func confirmPaste() {
        guard case .reviewing = state else { return }
        let edited = LiveHUDPanel.shared.currentReviewText
        removeEscMonitor()
        LiveHUDPanel.shared.hide()

        // Key status is released back to the previous app when our panel is
        // ordered out; give the system a moment before simulating Cmd+V.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.deliver(text: edited)
        }
    }

    private func cancelReview() {
        guard case .reviewing = state else { return }
        AppLog.dictation.info("Review cancelled")
        removeEscMonitor()
        LiveHUDPanel.shared.hide()
        state = .idle
    }

    private func installEscMonitor() {
        removeEscMonitor()
        // Local monitor: our review panel is key, so Esc is dispatched into our app.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.cancelReview() }
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }

    // MARK: - Output

    private func deliver(text: String) {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.promptForPermission()
            AppLog.dictation.warning("Missing Accessibility permission, could not type: \(text)")
            state = .error("Accessibility permission needed. Grant it in System Settings → Privacy → Accessibility.")
            return
        }

        KeystrokeOutput.type(text)
        state = .idle
    }
}
