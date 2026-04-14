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
        case error(String)
    }

    static let shared = DictationController()

    private(set) var state: State = .idle

    private let recorder = AudioRecorder()
    private let liveLoop = LiveTranscriptionLoop()
    private var recordStart: Date?

    private init() {}

    func installHotkey() {
        let (keyCode, modifiers) = HotkeyDefaults.optionSpace
        HotkeyManager.shared.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
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
            try recorder.start()
            state = .recording
            recordStart = Date()
            LiveHUDPanel.shared.show()
            liveLoop.start(modelId: descriptor.id, recordStart: Date()) { [weak self] in
                self?.recorder.currentSamples() ?? []
            } isActive: { [weak self] in
                self?.state == .recording
            }
            AppLog.dictation.info("startRecording: recording started")
        } catch {
            AppLog.dictation.error("Recorder start failed: \(error.localizedDescription)")
            state = .error("Could not start recording: \(error.localizedDescription)")
        }
    }

    private func preparationErrorMessage(for descriptor: ModelDescriptor) -> String {
        if case .failed(let reason) = ModelRegistry.shared.readiness(for: descriptor.id) {
            return "Failed to load \(descriptor.displayName): \(reason)"
        }
        return "Failed to load \(descriptor.displayName)."
    }

    // MARK: - Stop

    private func stopAndTranscribe() async {
        liveLoop.stop()
        let samples = recorder.stop()
        AppLog.dictation.info("Captured \(samples.count) samples (\(Double(samples.count) / AudioConfig.targetSampleRate, format: .fixed(precision: 2))s)")

        guard !samples.isEmpty,
              let descriptor = ModelRegistry.shared.activeModel,
              let engine = await ModelRegistry.shared.prepareModel(id: descriptor.id) else {
            LiveHUDPanel.shared.hide()
            state = .idle
            return
        }

        state = .transcribing
        do {
            let text = try await engine.transcribe(samples: samples)
            LiveHUDPanel.shared.hide()
            try handleFinalTranscription(text)
        } catch {
            LiveHUDPanel.shared.hide()
            AppLog.dictation.error("Transcription failed: \(error.localizedDescription)")
            state = .error("Transcription failed: \(error.localizedDescription)")
        }
    }

    private func handleFinalTranscription(_ text: String) throws {
        if text.isEmpty {
            state = .error("Transcription returned empty text. Try speaking closer to the mic.")
            return
        }

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
