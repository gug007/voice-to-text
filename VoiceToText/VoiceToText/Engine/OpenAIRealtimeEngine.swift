import AVFoundation
import Foundation
import OSLog

/// Streaming Speech-to-Text engine backed by OpenAI's Realtime API transcription
/// session (`wss://api.openai.com/v1/realtime?intent=transcription`). Audio is
/// streamed in live and the server returns `…input_audio_transcription.delta`
/// (partial preview) and `.completed` (finalized utterance) events.
///
/// OpenAI's realtime input path requires 24 kHz mono PCM16 and does NOT resample,
/// but the app records at 16 kHz — so this engine resamples each chunk to 24 kHz
/// via `AVAudioConverter` before sending. Reuses the OpenAI API key from
/// `OpenAIAPIKey` (no separate credential).
///
/// Also implements buffered `transcribe(samples:)` as a one-shot session for the
/// retry path and non-streaming callers.
actor OpenAIRealtimeEngine: StreamingTranscriptionEngine {
    let modelId: String
    private let session: URLSession

    // 16 kHz mono Float32 (recorder) → 24 kHz mono Int16 (OpenAI requirement).
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    /// Single consumer that resamples + sends buffered audio chunks in order.
    private var senderTask: Task<Void, Never>?
    /// Set in `startStream` before audio begins; read by the `nonisolated`
    /// `feedAudio` on the audio thread (order-preserving `yield`).
    private nonisolated(unsafe) var audioContinuation: AsyncStream<[Float]>.Continuation?

    /// Finalized utterance transcripts, in completion order.
    private var committed: [String] = []
    /// Text of the in-progress (not yet committed) utterance, accumulated from
    /// `.delta` events. Server VAD emits utterances sequentially, so a single
    /// partial string suffices (reset on each `.completed`).
    private var currentPartial: String = ""
    private var onLiveText: (@Sendable (String) -> Void)?
    private var lastError: String?

    private var finishing = false
    private var finishSignaled = false

    init(modelId: String, inputSampleRate: Double = AudioConfig.targetSampleRate) {
        self.modelId = modelId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config)
        // These fixed, valid formats never fail to construct.
        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: inputSampleRate, channels: 1, interleaved: false
        )!
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true
        )!
    }

    nonisolated var isReady: Bool {
        get async { OpenAIAPIKey.read() != nil }
    }

    func prepare(progress: PrepareProgress?) async throws {
        progress?(0.5, "Checking API key…")
        guard OpenAIAPIKey.read() != nil else {
            throw TranscriptionEngineError.modelLoadFailed(
                "OpenAI API key not configured. Add one in Settings → Cloud."
            )
        }
        progress?(1.0, "Ready")
    }

    // MARK: - Streaming

    func startStream(
        contextPrompt: String?,
        onLiveText: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let apiKey = OpenAIAPIKey.read() else {
            throw TranscriptionEngineError.notReady
        }

        committed = []
        currentPartial = ""
        lastError = nil
        finishing = false
        finishSignaled = false
        converter = nil
        self.onLiveText = onLiveText

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            throw TranscriptionEngineError.transcriptionFailed("Invalid OpenAI Realtime URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        startReceiveLoop()

        // Configure the transcription session before any audio is sent.
        await sendSessionConfig()

        let (audioStream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .unbounded
        )
        audioContinuation = continuation
        senderTask = Task { [weak self] in
            for await chunk in audioStream {
                await self?.sendChunkOverSocket(chunk)
            }
        }
        AppLog.dictation.info("OpenAI realtime session opened (model \(self.modelId))")
    }

    nonisolated func feedAudio(_ samples: [Float]) {
        audioContinuation?.yield(samples)
    }

    func finishStream() async throws -> String {
        defer { teardown() }

        // Stop accepting audio and drain everything captured before flushing.
        audioContinuation?.finish()
        await senderTask?.value

        // Server VAD auto-commits each utterance. If an utterance is still
        // in-progress at stop, nudge a commit and wait briefly for its final
        // transcript; if nothing is pending, everything is already committed.
        if !currentPartial.isEmpty {
            finishing = true
            finishSignaled = false
            await sendCommit()
            var waitedMs = 0
            while !finishSignaled, waitedMs < Self.finishGraceMs {
                try? await Task.sleep(for: .milliseconds(Self.finishPollMs))
                waitedMs += Self.finishPollMs
            }
        }

        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, let lastError {
            throw TranscriptionEngineError.transcriptionFailed("OpenAI: \(lastError)")
        }
        return text
    }

    func cancelStream() async {
        teardown()
        committed = []
        currentPartial = ""
    }

    // MARK: - Buffered fallback (retry / non-streaming callers)

    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress: TranscribeProgress?
    ) async throws -> String {
        try await startStream(contextPrompt: contextPrompt) { _ in }
        // ~200 ms per chunk at the input rate.
        let chunkSize = max(1, Int(inputFormat.sampleRate) / 5)
        var index = 0
        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            feedAudio(Array(samples[index..<end]))
            index = end
        }
        return try await finishStream()
    }

    // MARK: - Send

    private func sendSessionConfig() async {
        guard let task else { return }
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": ["model": modelId],
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 500,
                        ],
                    ],
                ],
            ],
        ]
        guard let json = Self.encode(payload) else { return }
        try? await task.send(.string(json))
    }

    private func sendChunkOverSocket(_ samples: [Float]) async {
        guard let task, let base64 = resampleToPCM16Base64(samples) else { return }
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64,
        ]
        guard let json = Self.encode(payload) else { return }
        do {
            try await task.send(.string(json))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sendCommit() async {
        guard let task else { return }
        guard let json = Self.encode(["type": "input_audio_buffer.commit"]) else { return }
        try? await task.send(.string(json))
    }

    // MARK: - Receive

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text): handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { handleMessage(text) }
                @unknown default: break
                }
            } catch {
                AppLog.dictation.error("OpenAI realtime receive loop ended: \(error.localizedDescription)")
                break
            }
        }
        signalFinishIfNeeded()
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated",
             "transcription_session.created", "transcription_session.updated":
            AppLog.dictation.info("OpenAI realtime session ready (\(type))")
        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                currentPartial += delta
                emitLiveText()
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = obj["transcript"] as? String, !transcript.isEmpty {
                committed.append(transcript)
            }
            currentPartial = ""
            emitLiveText()
            signalFinishIfNeeded()
        case "error", "conversation.item.input_audio_transcription.failed":
            let err = (obj["error"] as? [String: Any])?["message"] as? String ?? type
            lastError = err
            AppLog.dictation.error("OpenAI realtime error: \(err)")
        default:
            break // speech_started/stopped, committed, item.created, etc.
        }
    }

    private func emitLiveText() {
        onLiveText?(liveText)
    }

    private var liveText: String {
        var parts = committed
        if !currentPartial.isEmpty { parts.append(currentPartial) }
        return parts.joined(separator: " ")
    }

    private func signalFinishIfNeeded() {
        guard finishing else { return }
        finishSignaled = true
    }

    private func teardown() {
        audioContinuation?.finish()
        audioContinuation = nil
        senderTask?.cancel()
        senderTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        onLiveText = nil
        finishing = false
    }

    // MARK: - Resampling + encoding

    /// 16 kHz mono Float32 → 24 kHz mono Int16 (little-endian) → base64.
    /// One stateful `AVAudioConverter` per session preserves SRC filter state
    /// across chunks (mirrors `AudioRecorder`'s capture-side conversion).
    private func resampleToPCM16Base64(_ samples: [Float]) -> String? {
        guard !samples.isEmpty else { return nil }
        if converter == nil {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }
        guard let converter,
              let inBuffer = AVAudioPCMBuffer(
                  pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = inBuffer.floatChannelData else { return nil }
        inBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            channel[0].update(from: src.baseAddress!, count: samples.count)
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(samples.count) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        guard status != .error, let int16 = outBuffer.int16ChannelData else { return nil }
        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: int16[0], count: byteCount).base64EncodedString()
    }

    private static func encode(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let finishGraceMs = 2_000
    private static let finishPollMs = 50
}
