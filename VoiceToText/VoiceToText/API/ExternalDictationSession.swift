import AVFoundation
import Foundation
import OSLog

/// Dictation driven by another app over the local API: the same recorder,
/// models, speech gate and History as the hotkey, with none of its UI — no
/// HUD, no review card, no paste. The client draws its own recorder from the
/// events sent here and gets the transcript back as text.
///
/// One session at a time, owned by the connection that started it; that
/// connection closing cancels it. It never runs beside the hotkey dictation or
/// a conversation — `start` refuses while either holds the microphone, and
/// the hotkey refuses while this one does (`isActive`).
final class ExternalDictationSession {
    static let shared = ExternalDictationSession()

    enum Phase: String {
        case idle, preparing, recording, transcribing
    }

    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }

    private let recorder = AudioRecorder()
    private var owner: ExternalAPIConnection?
    private var startRequestID: ExternalAPI.RequestID?
    /// Fences every await: a cancel, a disconnect or a newer start moves it,
    /// and whatever was in flight returns without touching the new state.
    private var generation: UInt64 = 0
    private var model: ModelDescriptor?
    private var engine: TranscriptionEngine?
    private var stream: (any StreamingTranscriptionEngine)?
    /// A live stream that showed the client words heard speech: the speech
    /// gate could only throw those words away.
    private var streamShowedText = false
    private var progressTask: Task<Void, Never>?
    private var recordStart: Date?

    private static let progressInterval: Duration = .milliseconds(200)

    private init() {}

    func owns(_ connection: ExternalAPIConnection) -> Bool {
        owner === connection
    }

    /// Whether the microphone is free for an API session.
    var microphoneIsBusy: Bool {
        if MeetingController.shared.isBusy { return true }
        switch DictationController.shared.state {
        case .preparing, .recording, .transcribing, .delivering: return true
        case .idle, .reviewing, .error: return false
        }
    }

    // MARK: - Start

    func start(id: ExternalAPI.RequestID?, from connection: ExternalAPIConnection, client: String?) async {
        guard phase == .idle else {
            connection.send(ExternalAPI.failure(id: id, code: .busy, message: "Another app is already recording with VoiceToText."))
            return
        }
        guard !microphoneIsBusy else {
            connection.send(ExternalAPI.failure(id: id, code: .busy, message: "VoiceToText is already recording."))
            return
        }
        AppLog.dictation.info("API start from \(client ?? "unnamed client", privacy: .public)")
        generation &+= 1
        let generation = self.generation
        owner = connection
        startRequestID = id
        phase = .preparing

        guard await MicPermission.request() else {
            failStart(generation, .microphoneDenied, "VoiceToText doesn't have microphone access. Allow it in System Settings → Privacy & Security → Microphone.")
            return
        }
        guard generation == self.generation else { return }
        guard let descriptor = ModelRegistry.shared.activeModel else {
            failStart(generation, .noModel, "No transcription model is selected in VoiceToText.")
            return
        }
        if let provider = descriptor.backend.cloudProvider, !provider.hasAPIKey {
            failStart(generation, .apiKeyMissing, "\(descriptor.displayName) needs \(provider.apiKeyPhrase). Add one in VoiceToText → Cloud.")
            return
        }
        model = descriptor
        let readiness = ModelRegistry.shared.readiness(for: descriptor.id)
        sendPreparing(descriptor, readiness: readiness)
        watchPreparation(of: descriptor, from: readiness, generation: generation)
        let prepared = await ModelRegistry.shared.prepareModel(id: descriptor.id)
        progressTask?.cancel()
        guard generation == self.generation else { return }
        guard let prepared else {
            failStart(generation, .modelUnavailable, "\(descriptor.displayName) couldn't be loaded. Check it in VoiceToText → Models.")
            return
        }
        engine = prepared

        recorder.onLevel = { [weak self] level in
            guard let self, self.phase == .recording else { return }
            self.owner?.send(ExternalAPI.event("level", ["level": (level * 1000).rounded() / 1000]))
        }
        recorder.onConfigurationChange = { [weak self] samples in
            self?.recorderStopped(generation: generation, samples: samples)
        }
        recorder.onAudioChunk = nil
        stream = nil
        streamShowedText = false
        if let streaming = prepared as? any StreamingTranscriptionEngine {
            do {
                try await streaming.startStream(contextPrompt: nil) { text in
                    Task { @MainActor in
                        ExternalDictationSession.shared.noteLiveText(text, generation: generation)
                    }
                }
                guard generation == self.generation else {
                    await streaming.cancelStream()
                    return
                }
                stream = streaming
                recorder.onAudioChunk = { samples in streaming.feedAudio(samples) }
            } catch {
                AppLog.dictation.error("API live stream failed to open: \(error.localizedDescription); using buffered transcription")
            }
        }

        do {
            try await recorder.start()
        } catch {
            guard generation == self.generation else { return }
            await tearDownStream()
            failStart(generation, .recorderFailed, "Could not start recording: \(error.localizedDescription)")
            return
        }
        guard generation == self.generation else {
            _ = await recorder.stop()
            return
        }
        phase = .recording
        recordStart = Date()
        let model = Self.modelJSON(descriptor, live: stream != nil)
        send(event: "state", ["state": Phase.recording.rawValue, "model": model])
        owner?.send(ExternalAPI.response(id: startRequestID, result: ["model": model]))
        startRequestID = nil
        AppLog.dictation.notice("API recording started on \(descriptor.id, privacy: .public)")
    }

    private func watchPreparation(of descriptor: ModelDescriptor, from initial: ModelReadiness, generation: UInt64) {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            var last = initial
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressInterval)
                guard let self, generation == self.generation, self.phase == .preparing else { return }
                let readiness = ModelRegistry.shared.readiness(for: descriptor.id)
                guard readiness != last else { continue }
                last = readiness
                self.sendPreparing(descriptor, readiness: readiness)
            }
        }
    }

    private func sendPreparing(_ descriptor: ModelDescriptor, readiness: ModelReadiness) {
        var fields: [String: Any] = [
            "state": Phase.preparing.rawValue,
            "model": Self.modelJSON(descriptor, live: descriptor.isRealtime),
        ]
        if case .preparing(let fraction, let message) = readiness {
            // 0 is what the registry publishes before anything has moved, and
            // the CoreML compile tail never moves it: unknown, not stuck.
            if fraction > 0 { fields["progress"] = fraction }
            fields["message"] = message
        }
        send(event: "state", fields)
    }

    private func noteLiveText(_ text: String, generation: UInt64) {
        guard generation == self.generation, phase == .recording || phase == .transcribing else { return }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { streamShowedText = true }
        send(event: "partial", ["text": text])
    }

    // MARK: - Stop

    func stop(id: ExternalAPI.RequestID?, from connection: ExternalAPIConnection) async {
        guard owns(connection) else {
            connection.send(ExternalAPI.failure(id: id, code: .notRecording, message: "This client isn't recording."))
            return
        }
        guard phase == .recording else {
            connection.send(ExternalAPI.failure(id: id, code: .notRecording, message: "Nothing is recording."))
            return
        }
        connection.send(ExternalAPI.response(id: id))
        let generation = self.generation
        enterTranscribing()
        let samples = await recorder.flushAndStop()
        guard generation == self.generation else { return }
        await transcribe(samples, generation: generation)
    }

    /// The recorder gave up mid-take — the microphone went away — and
    /// handed over what it captured. That's still the user's words: they're
    /// transcribed as if the client had pressed stop.
    private func recorderStopped(generation: UInt64, samples: [Float]) {
        guard generation == self.generation, phase == .recording else { return }
        AppLog.dictation.notice("API recording stopped by an audio device change")
        enterTranscribing(interrupted: true)
        Task { await transcribe(samples, generation: generation) }
    }

    private func enterTranscribing(interrupted: Bool = false) {
        phase = .transcribing
        var fields: [String: Any] = ["state": Phase.transcribing.rawValue]
        if interrupted { fields["interrupted"] = true }
        send(event: "state", fields)
    }

    private func transcribe(_ samples: [Float], generation: UInt64) async {
        guard let model else { return }
        let duration = Double(samples.count) / AudioConfig.targetSampleRate
        guard RecordingSalvage.outcome(
            sampleCount: samples.count,
            minTranscribeSamples: DictationConfig.minTranscribeSamples
        ) == .transcribe else {
            await tearDownStream()
            fail(generation, .tooShort, "Recording too short — try again.")
            return
        }
        if !(stream != nil && streamShowedText) {
            let voiced = await VoiceActivityGate.shared.isVoiced(samples)
            guard generation == self.generation else { return }
            guard voiced else {
                await tearDownStream()
                fail(generation, .noSpeech, "No speech detected.")
                return
            }
        }

        let raw: String
        do {
            if let streaming = stream {
                stream = nil
                recorder.onAudioChunk = nil
                raw = try await streaming.finishStream()
            } else if let engine {
                raw = try await engine.transcribe(samples: samples, contextPrompt: nil, progress: nil)
            } else {
                fail(generation, .modelUnavailable, "\(model.displayName) isn't loaded.")
                return
            }
            CloudCreditStatus.shared.noteSuccess(provider: model.backend.cloudProvider)
        } catch {
            guard generation == self.generation else { return }
            let failure = TranscriptionFailure.classify(error)
            _ = CloudCreditStatus.shared.noteFailure(failure, provider: model.backend.cloudProvider)
            let message = failure.message(
                provider: model.backend.cloudProvider?.displayName,
                fallback: error.localizedDescription
            )
            AppLog.dictation.error("API transcription failed: \(error.localizedDescription)")
            // Words the user spoke, kept where they can transcribe them again
            // — History's rule for any failed dictation.
            let saved = RecordingHistoryStore.shared.recordFailed(
                samples: samples,
                model: model,
                status: .init(kind: .failed, message: message)
            ) != nil
            fail(generation, .transcriptionFailed, message, extra: ["savedToHistory": saved])
            return
        }
        guard generation == self.generation else { return }

        let text = TranscriptPostProcessor.process(raw)
        guard !text.isEmpty else {
            fail(generation, .noSpeech, "Transcription returned empty text. Try speaking closer to the mic.")
            return
        }
        RecordingHistoryStore.shared.record(samples: samples, transcript: text, model: model)
        send(event: "transcript", [
            "text": text,
            "duration": (duration * 100).rounded() / 100,
            "model": Self.modelJSON(model, live: model.isRealtime),
        ])
        AppLog.dictation.notice("API transcript delivered (\(duration, format: .fixed(precision: 1))s)")
        finish()
    }

    // MARK: - Cancel

    func cancel(id: ExternalAPI.RequestID?, from connection: ExternalAPIConnection) async {
        guard phase == .idle || owns(connection) else {
            connection.send(ExternalAPI.failure(id: id, code: .busy, message: "Another app's recording can't be cancelled from here."))
            return
        }
        connection.send(ExternalAPI.response(id: id))
        await cancelSession(notify: true)
    }

    func connectionClosed(_ connection: ExternalAPIConnection) async {
        guard owns(connection) else { return }
        AppLog.dictation.info("API client disconnected; cancelling its session")
        await cancelSession(notify: false)
    }

    private func cancelSession(notify: Bool) async {
        guard phase != .idle else { return }
        let wasRecording = phase == .recording
        generation &+= 1
        progressTask?.cancel()
        if let startRequestID, notify {
            owner?.send(ExternalAPI.failure(id: startRequestID, code: .cancelled, message: "Cancelled."))
        }
        let owner = notify ? self.owner : nil
        finish(notifyIdle: false)
        owner?.send(ExternalAPI.event("state", ["state": Phase.idle.rawValue]))
        if wasRecording { _ = await recorder.stop() }
        await tearDownStream()
    }

    // MARK: - Endings

    private func failStart(_ generation: UInt64, _ code: ExternalAPI.ErrorCode, _ message: String) {
        guard generation == self.generation else { return }
        progressTask?.cancel()
        owner?.send(ExternalAPI.failure(id: startRequestID, code: code, message: message))
        finish()
    }

    private func fail(
        _ generation: UInt64,
        _ code: ExternalAPI.ErrorCode,
        _ message: String,
        extra: [String: Any] = [:]
    ) {
        guard generation == self.generation else { return }
        AppLog.dictation.notice("API take ended: \(code.rawValue, privacy: .public)")
        var fields = extra
        fields["code"] = code.rawValue
        fields["message"] = message
        send(event: "error", fields)
        finish()
    }

    private func finish(notifyIdle: Bool = true) {
        if notifyIdle { send(event: "state", ["state": Phase.idle.rawValue]) }
        phase = .idle
        owner = nil
        startRequestID = nil
        model = nil
        engine = nil
        recordStart = nil
        recorder.onLevel = nil
        recorder.onAudioChunk = nil
    }

    private func tearDownStream() async {
        guard let streaming = stream else { return }
        stream = nil
        recorder.onAudioChunk = nil
        await streaming.cancelStream()
    }

    private func send(event name: String, _ fields: [String: Any]) {
        owner?.send(ExternalAPI.event(name, fields))
    }

    // MARK: - Status

    func statusJSON() -> [String: Any] {
        var status: [String: Any] = [
            "state": phase.rawValue,
            "busy": phase == .idle && microphoneIsBusy,
            "microphone": Self.microphoneJSON,
        ]
        if let model = model ?? ModelRegistry.shared.activeModel {
            var json = Self.modelJSON(model, live: model.isRealtime)
            json["ready"] = ModelRegistry.shared.readiness(for: model.id).isInstalled
            status["model"] = json
        }
        if phase == .recording, let recordStart {
            status["elapsed"] = (Date().timeIntervalSince(recordStart) * 100).rounded() / 100
        }
        return status
    }

    private static var microphoneJSON: String {
        switch MicPermission.status {
        case .authorized: return "granted"
        case .notDetermined: return "undetermined"
        default: return "denied"
        }
    }

    static func modelJSON(_ model: ModelDescriptor, live: Bool) -> [String: Any] {
        ["id": model.id, "name": model.displayName, "live": live, "local": !model.isCloud]
    }
}
