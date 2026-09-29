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
///
/// A live session that loses text on the way — a dropped socket, a failed
/// send, a server error, a flush nobody answers — never hands back what it
/// managed to collect: `finishStream` re-sends the whole take through the
/// buffered path, and throws if that fails too, so the caller keeps the audio
/// for Retry instead of pasting half a sentence.
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

    /// What this session still owes and whether any of it was lost.
    private var finish: ElevenLabsRealtimeFinishTracker
    /// Set by the buffered `transcribe` right after it opens its session.
    private var isBufferedSession = false
    /// Every sample of a live take, in the order it was sent, so a degraded
    /// session can re-send the whole take. The controller holds the same audio
    /// but `finishStream` has no way to ask for it. Buffered sessions already
    /// have their samples in hand and don't keep a second copy.
    private var takeAudio: [Float] = []
    private var retainsTakeAudio = false
    private var sessionContextPrompt: String?
    /// Set on the buffered session that re-sends a degraded live take: the
    /// whole re-send must end by then.
    private var sessionDeadline: ContinuousClock.Instant?

    /// Bumped by every `startStream` and `cancelStream`. A torn-down session's
    /// receive loop can resume after the next session has started; without
    /// this fence its close would mark the healthy session as dropped. It also
    /// tells a finish wait, or the re-send behind it, that its session was
    /// replaced or cancelled underneath it.
    private var sessionGeneration = 0

    init(modelId: String, sampleRate: Int = Int(AudioConfig.targetSampleRate)) {
        self.modelId = modelId
        self.sampleRate = sampleRate
        self.finish = Self.freshTracker(sampleRate: sampleRate)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config)
    }

    nonisolated var isReady: Bool {
        get async { ElevenLabsAPIKey.read() != nil }
    }

    /// The session is opened without `previous_text`; `contextPrompt` is
    /// ignored.
    nonisolated var usesContextPrompt: Bool { false }

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
        try await openSession(contextPrompt: contextPrompt, onLiveText: onLiveText, deadline: nil)
    }

    /// `deadline` bounds the automatic re-send of a degraded take: once it
    /// passes, the socket is cut (see `enforceDeadline`), which ends a stalled
    /// handshake, a stalled send and the finish wait alike.
    private func openSession(
        contextPrompt: String?,
        onLiveText: @escaping @Sendable (String) -> Void,
        deadline: ContinuousClock.Instant?
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
        finish = Self.freshTracker(sampleRate: sampleRate)
        isBufferedSession = false
        takeAudio = []
        retainsTakeAudio = true
        sessionContextPrompt = contextPrompt
        sessionDeadline = deadline
        self.onLiveText = onLiveText
        sessionGeneration &+= 1
        let generation = sessionGeneration
        if let deadline { enforceDeadline(deadline, generation: generation) }

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

        startReceiveLoop(generation: generation)
        AppLog.dictation.info("ElevenLabs realtime session opened (\(self.audioFormatParam))")
    }

    nonisolated func feedAudio(_ samples: [Float]) {
        audioContinuation?.yield(samples)
    }

    private func sendChunkOverSocket(_ samples: [Float]) async {
        // Kept before the send, so a take whose socket died is still whole.
        if retainsTakeAudio { takeAudio.append(contentsOf: samples) }
        finish.audioSent(
            sampleCount: samples.count,
            hasSpeechEnergy: RealtimeFinishPolicy.hasSpeechEnergy(
                samples,
                sampleRate: sampleRate,
                thresholdDBFS: DictationConfig.vadThresholdDBFS
            )
        )
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
            finish.sendFailed(error.localizedDescription, transport: (error as? URLError)?.code)
        }
    }

    func finishStream() async throws -> String {
        let session: RealtimeFinishPolicy.Session = isBufferedSession ? .buffered : .live
        let generation = sessionGeneration
        // Throws only when a newer session or a cancel replaced this one
        // mid-wait — the socket is no longer this call's to tear down.
        let settled = try await settleSession()
        guard generation == sessionGeneration else { throw Self.supersededError }
        let take = takeAudio
        let contextPrompt = sessionContextPrompt
        let transport = finish.transport
        teardown()

        switch RealtimeFinishPolicy.action(
            for: settled.degradation,
            session: session,
            hasRetainedTake: !take.isEmpty
        ) {
        case .deliver:
            return settled.text
        case .rerunBuffered:
            let seconds = Double(take.count) / Double(sampleRate)
            AppLog.dictation.warning("ElevenLabs live session incomplete (\(settled.degradation?.summary ?? "", privacy: .public)); re-sending the \(seconds, format: .fixed(precision: 1))s take")
            let deadline = ContinuousClock.now + .milliseconds(RealtimeFinishPolicy.resendBudgetMs)
            return try await transcribeBuffered(samples: take, contextPrompt: contextPrompt, deadline: deadline)
        case .fail(let degradation):
            AppLog.dictation.error("ElevenLabs session incomplete: \(degradation.summary, privacy: .public)")
            throw RealtimeFinishPolicy.failureError(provider: "ElevenLabs", degradation, transport: transport)
        }
    }

    /// Drains the audio, flushes the tail, and waits for the server to answer.
    /// Returns what arrived and why it can't be trusted, if it can't.
    private func settleSession() async throws -> (text: String, degradation: RealtimeDegradation?) {
        let generation = sessionGeneration

        // Stop accepting audio and wait for the sender to drain everything
        // already captured before we flush, so no trailing words are lost.
        audioContinuation?.finish()
        await senderTask?.value
        finish.beginFinish()

        // Flush only when speech may still be uncommitted; with nothing
        // outstanding there is nothing to wait for (see
        // `ElevenLabsRealtimeFinishTracker`).
        if finish.needsFlush {
            finish.flushCommitSent()
            await sendFlushCommit()
        }

        // Poll so we return as soon as the answer lands rather than always
        // paying the full window. The window scales with what may be owed: the
        // whole take for a buffered session, the audio since the last commit
        // for a live one.
        let buffered = isBufferedSession
        var capMs = buffered
            ? RealtimeFinishPolicy.bufferedFinishCapMs(sampleCount: finish.sentSamples, sampleRate: Double(sampleRate))
            : RealtimeFinishPolicy.liveFinishCapMs(owedSampleCount: finish.owedSampleCount, sampleRate: Double(sampleRate))
        if let sessionDeadline {
            capMs = min(capMs, RealtimeFinishPolicy.milliseconds(until: sessionDeadline))
        }
        var waitedMs = 0
        var quietMs = 0
        var seenEvents = finish.transcriptEvents
        func isDone() -> Bool {
            finish.isDone(quietMs: quietMs, buffered: buffered)
        }
        while true {
            guard generation == sessionGeneration else { throw Self.supersededError }
            if isDone() || waitedMs >= capMs { break }
            try? await Task.sleep(for: .milliseconds(Self.finishPollMs))
            waitedMs += Self.finishPollMs
            if finish.transcriptEvents != seenEvents {
                seenEvents = finish.transcriptEvents
                quietMs = 0
            } else {
                quietMs += Self.finishPollMs
            }
        }
        if !isDone() { finish.finishWindowExpired() }

        let text = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, finish.degradation)
    }

    /// Also stops a finish wait, or the re-send behind it, that is still
    /// running for this engine: the generation bump makes it throw.
    func cancelStream() async {
        sessionGeneration &+= 1
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
        try await transcribeBuffered(samples: samples, contextPrompt: contextPrompt, deadline: nil)
    }

    private func transcribeBuffered(
        samples: [Float],
        contextPrompt: String?,
        deadline: ContinuousClock.Instant?
    ) async throws -> String {
        try await openSession(contextPrompt: contextPrompt, onLiveText: { _ in }, deadline: deadline)
        // Before any audio is fed: the sender only runs once chunks arrive.
        isBufferedSession = true
        retainsTakeAudio = false
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

    private func startReceiveLoop(generation: Int) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(generation: generation)
        }
    }

    /// `generation` is the session this loop belongs to; everything it writes
    /// is fenced on that still being the live one (see `sessionGeneration`).
    private func receiveLoop(generation: Int) async {
        guard let task, generation == sessionGeneration else { return }
        var failure: Error?
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard generation == sessionGeneration else { return }
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
                failure = error
                break
            }
        }
        // Unblocks a pending finish, and marks the take incomplete if the
        // socket closed while text was still owed. A handshake the server
        // refused (a bad key, a rate limit) says which by its HTTP status.
        guard generation == sessionGeneration else { return }
        if let status = (task.response as? HTTPURLResponse)?.statusCode,
           let refusal = RealtimeRefusal.handshake(status: status) {
            finish.refused(refusal, "HTTP \(status)")
        }
        finish.connectionClosed(transport: (failure as? URLError)?.code)
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
            finish.partialTranscript(partial)
            emitLiveText()
        case "committed_transcript", "committed_transcript_with_timestamps":
            if let committed = obj["text"] as? String, !committed.isEmpty {
                committedSegments.append(committed)
            }
            partial = ""
            finish.committedTranscript()
            emitLiveText()
        case "insufficient_audio_activity", "commit_throttled":
            // The flush found nothing to commit (or was refused because a VAD
            // commit just went out). Benign, and at finish an answer — see
            // `ElevenLabsRealtimeFinishTracker.nothingToCommit`.
            finish.nothingToCommit()
        default:
            // Error events carry an "error" field; every other one costs text.
            // The ones that refuse the session outright rule out a re-send.
            if let err = obj["error"] as? String, type != "warning" {
                if let refusal = RealtimeRefusal.elevenLabs(messageType: type) {
                    finish.refused(refusal, err)
                } else {
                    finish.serverError("\(type): \(err)")
                }
                AppLog.dictation.error("ElevenLabs stream error (\(type)): \(err)")
            }
        }
    }

    private func enforceDeadline(_ deadline: ContinuousClock.Instant, generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            await self?.deadlinePassed(generation: generation)
        }
    }

    /// Marks the session timed out and cuts the socket, so every wait on it —
    /// the sender's drain, the finish — ends now.
    private func deadlinePassed(generation: Int) {
        guard generation == sessionGeneration, task != nil else { return }
        AppLog.dictation.warning("ElevenLabs re-send ran out of time; giving up on it")
        finish.finishWindowExpired()
        task?.cancel(with: .goingAway, reason: nil)
    }

    private func emitLiveText() {
        onLiveText?(liveText)
    }

    private var liveText: String {
        var parts = committedSegments
        if !partial.isEmpty { parts.append(partial) }
        return parts.joined(separator: " ")
    }

    private func sendFlushCommit() async {
        guard let task else {
            finish.sendFailed("no open connection")
            return
        }
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": sampleRate,
        ]
        guard let json = Self.encode(payload) else { return }
        do {
            try await task.send(.string(json))
        } catch {
            finish.sendFailed(error.localizedDescription, transport: (error as? URLError)?.code)
        }
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
        takeAudio = []
        retainsTakeAudio = false
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
    private nonisolated static func pcm16Base64(_ samples: [Float]) -> String {
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices {
            let clamped = max(-1.0, min(1.0, samples[i]))
            pcm[i] = Int16(clamped * 32_767.0).littleEndian
        }
        let data = pcm.withUnsafeBytes { Data($0) }
        return data.base64EncodedString()
    }

    private nonisolated static func encode(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static let finishPollMs = 50

    /// A commit lands a silence window plus a transcription after its cut, so
    /// it is trusted to cover audio sent up to a second before it arrived. Any
    /// speech sent after that still gets a flush; if the guess falls short of
    /// the segment's own end, the flush just finds nothing to add.
    private nonisolated static func freshTracker(sampleRate: Int) -> ElevenLabsRealtimeFinishTracker {
        ElevenLabsRealtimeFinishTracker(commitLagSamples: sampleRate)
    }

    private nonisolated static var supersededError: TranscriptionEngineError {
        .transcriptionFailed("The ElevenLabs session was cancelled or replaced before it finished.")
    }

    // MARK: - Connection test

    /// Lightweight reachability/auth probe for the Cloud settings pane. Hits the
    /// REST `/v1/user` endpoint with the saved key.
    static func testConnection() async -> ElevenLabsConnectionTest {
        guard let apiKey = ElevenLabsAPIKey.read() else {
            return .failed("No key configured.")
        }
        return await testConnection(apiKey: apiKey)
    }

    /// The same probe against a key that has not been saved yet — what the
    /// paste-to-connect field verifies before committing anything to storage.
    static func testConnection(apiKey: String) async -> ElevenLabsConnectionTest {
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
