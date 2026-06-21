import Foundation
import OSLog

/// Reachability/auth probe result for the Cloud settings UI.
enum ElevenLabsConnectionTest {
    case ok
    case rejected
    case failed(String)
}

/// Streaming Speech-to-Text engine backed by ElevenLabs Scribe v2 Realtime over
/// a WebSocket (`wss://api.elevenlabs.io/v1/speech-to-text/realtime`). Audio is
/// pushed in live as 16 kHz mono Float32, encoded to PCM16-LE base64, and the
/// server streams back `partial_transcript` (replaceable preview) and
/// `committed_transcript` (finalized segments) events.
///
/// Also implements the buffered `transcribe(samples:)` as a one-shot session so
/// it works on the retry path (which re-runs the cached buffer) and for any
/// caller that doesn't use the streaming API.
actor ElevenLabsRealtimeEngine: StreamingTranscriptionEngine {
    let modelId: String
    private let sampleRate: Int
    private let session: URLSession

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    /// Single consumer that sends buffered audio chunks over the socket in
    /// order. Fed by `feedAudio` via `audioContinuation`.
    private var senderTask: Task<Void, Never>?
    /// Set in `startStream` before audio begins; read by the `nonisolated`
    /// `feedAudio` on the audio thread. `AsyncStream.Continuation.yield` is
    /// thread-safe and order-preserving for sequential calls, so feeding it
    /// directly from the in-order audio callback keeps frames ordered.
    private nonisolated(unsafe) var audioContinuation: AsyncStream<[Float]>.Continuation?
    private var committedSegments: [String] = []
    private var partial: String = ""
    private var onLiveText: (@Sendable (String) -> Void)?
    private var lastError: String?

    /// Set true once `finishStream` has sent its flush commit; lets the receive
    /// loop signal that the final committed segment has arrived.
    private var finishing = false
    private var finishSignaled = false

    init(modelId: String, sampleRate: Int = Int(AudioConfig.targetSampleRate)) {
        self.modelId = modelId
        self.sampleRate = sampleRate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config)
    }

    nonisolated var isReady: Bool {
        get async { ElevenLabsAPIKey.read() != nil }
    }

    func prepare(progress: PrepareProgress?) async throws {
        progress?(0.5, "Checking API key…")
        guard ElevenLabsAPIKey.read() != nil else {
            throw TranscriptionEngineError.modelLoadFailed(
                "ElevenLabs API key not configured. Add one in Settings → Cloud."
            )
        }
        progress?(1.0, "Ready")
    }

    // MARK: - Streaming

    func startStream(
        contextPrompt: String?,
        onLiveText: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let apiKey = ElevenLabsAPIKey.read() else {
            throw TranscriptionEngineError.notReady
        }

        // Tear down any prior session first so a reused actor never orphans its
        // old socket / receive + sender tasks.
        teardown()

        // Reset session state in case the actor is reused.
        committedSegments = []
        partial = ""
        lastError = nil
        finishing = false
        finishSignaled = false
        self.onLiveText = onLiveText

        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        components.queryItems = [
            URLQueryItem(name: "model_id", value: modelId),
            URLQueryItem(name: "audio_format", value: audioFormatParam),
            // VAD auto-commits on natural pauses, which keeps long dictation
            // within the server buffer and yields incremental committed text.
            URLQueryItem(name: "commit_strategy", value: "vad"),
        ]
        guard let url = components.url else {
            throw TranscriptionEngineError.transcriptionFailed("Invalid ElevenLabs URL")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        let (audioStream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .unbounded
        )
        audioContinuation = continuation
        senderTask = Task { [weak self] in
            for await chunk in audioStream {
                await self?.sendChunkOverSocket(chunk)
            }
        }

        startReceiveLoop()
        AppLog.dictation.info("ElevenLabs realtime session opened (\(self.audioFormatParam))")
    }

    nonisolated func feedAudio(_ samples: [Float]) {
        audioContinuation?.yield(samples)
    }

    private func sendChunkOverSocket(_ samples: [Float]) async {
        guard let task else { return }
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": Self.pcm16Base64(samples),
            "commit": false,
            "sample_rate": sampleRate,
        ]
        guard let json = Self.encode(payload) else { return }
        do {
            try await task.send(.string(json))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func finishStream() async throws -> String {
        defer { teardown() }

        // Stop accepting audio and wait for the sender to drain everything
        // already captured before we flush, so no trailing words are lost.
        audioContinuation?.finish()
        await senderTask?.value

        finishing = true
        finishSignaled = false
        await sendFlushCommit()

        // Wait briefly for the server to flush the tail into a final committed
        // segment. Poll so we return as soon as it lands rather than always
        // paying the full grace period.
        var waitedMs = 0
        while !finishSignaled, waitedMs < Self.finishGraceMs {
            try? await Task.sleep(for: .milliseconds(Self.finishPollMs))
            waitedMs += Self.finishPollMs
        }

        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, let lastError {
            throw TranscriptionEngineError.transcriptionFailed("ElevenLabs: \(lastError)")
        }
        return text
    }

    func cancelStream() async {
        teardown()
        committedSegments = []
        partial = ""
    }

    // MARK: - Buffered fallback (retry / non-streaming callers)

    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress: TranscribeProgress?
    ) async throws -> String {
        try await startStream(contextPrompt: contextPrompt) { _ in }
        // ~200 ms per chunk.
        let chunkSize = max(1, sampleRate / 5)
        var index = 0
        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            feedAudio(Array(samples[index..<end]))
            index = end
        }
        return try await finishStream()
    }

    // MARK: - Receive loop

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
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                // Surfaces auth/handshake failures, which `task.resume()`
                // reports lazily on the first receive rather than at connect.
                AppLog.dictation.error("ElevenLabs receive loop ended: \(error.localizedDescription)")
                break
            }
        }
        // Unblock a pending finishStream if the socket closed before its commit
        // response arrived.
        signalFinishIfNeeded()
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["message_type"] as? String else { return }

        switch type {
        case "session_started":
            AppLog.dictation.info("ElevenLabs session_started")
        case "partial_transcript":
            partial = (obj["text"] as? String) ?? ""
            emitLiveText()
        case "committed_transcript", "committed_transcript_with_timestamps":
            if let committed = obj["text"] as? String, !committed.isEmpty {
                committedSegments.append(committed)
            }
            partial = ""
            emitLiveText()
            signalFinishIfNeeded()
        default:
            // Error events carry an "error" field. `insufficient_audio_activity`
            // is benign when flushing an already-empty buffer at finish.
            if let err = obj["error"] as? String, type != "insufficient_audio_activity" {
                lastError = err
                AppLog.dictation.error("ElevenLabs stream error (\(type)): \(err)")
            }
        }
    }

    private func emitLiveText() {
        onLiveText?(liveText)
    }

    private var liveText: String {
        var parts = committedSegments
        if !partial.isEmpty { parts.append(partial) }
        return parts.joined(separator: " ")
    }

    private func signalFinishIfNeeded() {
        guard finishing else { return }
        finishSignaled = true
    }

    private func sendFlushCommit() async {
        guard let task else { return }
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": sampleRate,
        ]
        guard let json = Self.encode(payload) else { return }
        try? await task.send(.string(json))
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

    private var audioFormatParam: String {
        switch sampleRate {
        case 8_000: return "pcm_8000"
        case 16_000: return "pcm_16000"
        case 22_050: return "pcm_22050"
        case 24_000: return "pcm_24000"
        case 44_100: return "pcm_44100"
        case 48_000: return "pcm_48000"
        default: return "pcm_16000"
        }
    }

    // MARK: - Encoding helpers

    /// Float32 [-1, 1] → 16-bit signed little-endian PCM → base64. Builds a
    /// contiguous Int16 buffer and copies it in one shot rather than appending
    /// per sample (this runs ~16×/sec during dictation).
    private static func pcm16Base64(_ samples: [Float]) -> String {
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices {
            let clamped = max(-1.0, min(1.0, samples[i]))
            pcm[i] = Int16(clamped * 32_767.0).littleEndian
        }
        let data = pcm.withUnsafeBytes { Data($0) }
        return data.base64EncodedString()
    }

    private static func encode(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let finishGraceMs = 2_000
    private static let finishPollMs = 50

    // MARK: - Connection test

    /// Lightweight reachability/auth probe for the Cloud settings pane. Hits the
    /// REST `/v1/user` endpoint with the saved key.
    static func testConnection() async -> ElevenLabsConnectionTest {
        guard let apiKey = ElevenLabsAPIKey.read() else {
            return .failed("No key configured.")
        }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/user") else {
            return .failed("Test failed: bad URL.")
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Test failed: invalid response.")
            }
            switch http.statusCode {
            case 200..<300: return .ok
            case 401: return .rejected
            default: return .failed("Test failed: HTTP \(http.statusCode).")
            }
        } catch {
            return .failed("Test failed: \(error.localizedDescription)")
        }
    }
}
