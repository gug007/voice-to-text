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
/// Two commit modes, keyed off the model (`usesManualCommit`):
/// - Server-VAD models (`gpt-4o-transcribe`, `gpt-live-transcribe`) get a
///   `server_vad` `turn_detection` block; the server auto-commits each utterance
///   as the user speaks, so at finish at most the trailing utterance is still
///   pending.
/// - `gpt-realtime-whisper` does NOT support VAD turn detection: the config must
///   omit `turn_detection`, and audio is only transcribed after an explicit
///   `input_audio_buffer.commit`. Nothing auto-commits, so at finish the engine
///   always commits and waits for the final `completed` event.
///
/// Turn detection is model-dependent, not session-dependent: the realtime-VAD
/// guide states that models supporting VAD default to `server_vad` "while
/// `gpt-realtime-whisper` requires turn detection to be omitted or set to
/// `null`" — it names no other model. `gpt-live-transcribe` is therefore a
/// server-VAD model. That is an inference from a rule stated in the negative, so
/// `sendSessionConfig` also carries a fallback ladder that flips this session to
/// manual commit if the server rejects the VAD config.
///
/// Also implements buffered `transcribe(samples:)` as a one-shot session for the
/// retry path and non-streaming callers (always a manual commit at finish).
actor OpenAIRealtimeEngine: StreamingTranscriptionEngine {
    let modelId: String
    private let session: URLSession

    /// Which fields this model accepts (and which it rejects outright).
    private let capabilities: OpenAIModelCapabilities

    /// Seeded per session from `capabilities`, but mutable: if the server
    /// rejects the VAD config the fallback ladder drops to `turn_detection: null`
    /// mid-session, and `finishStream` must then take the always-commit-and-wait
    /// branch or the only utterance never arrives.
    private var usesManualCommit: Bool

    /// Set when the fallback ladder gave up on VAD *mid-session*. Distinct from
    /// `usesManualCommit`: a model that is manual-commit by nature has its whole
    /// take flushed by a caller that knows to wait (`commitOnFinish`), whereas a
    /// downgraded session streamed live with nothing auto-committing, so the
    /// single commit at finish covers the entire recording. That needs the
    /// buffered drain, not the trailing-utterance grace window.
    private var downgradedToManualCommit = false

    /// Config attempts, in the order `downgradeSessionConfig` walks them. Each
    /// rung removes whatever the previous one might have been rejected for.
    private enum SessionConfigStage {
        /// `server_vad` + `prompt` / `keywords` / `languages`.
        case full
        /// `server_vad`, no context fields.
        case minimal
        /// Explicit `turn_detection: null`, no context fields.
        case manualCommit
    }

    private var configStage: SessionConfigStage = .full
    /// Set when the server acknowledges our `session.update`. Until then the
    /// session transcribes nothing, so audio waits (buffered) rather than being
    /// poured into a session that will never answer.
    private var sessionConfigured = false
    /// Clamped `prompt` for this session, combined in `startStream` from the
    /// caller's context and `decoder.initialPrompt`.
    private var sessionPrompt: String?

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

    /// Committed audio buffers (auto-VAD or manual) whose transcripts have
    /// not arrived yet. One-shot buffered sessions feed audio faster than
    /// realtime, so at finish the server may still owe every transcript even
    /// though `currentPartial` is empty — the buffered path drains this count
    /// instead of trusting the live path's "nothing pending" shortcut.
    private var pendingTranscripts = 0
    /// Set by the buffered `transcribe` so `finishStream` always commits the
    /// trailing buffer and waits for `pendingTranscripts`, rather than
    /// returning immediately (and empty) when no partial has shown up yet.
    private var commitOnFinish = false
    /// Set when the receive loop exits — no more events can arrive, so any
    /// finish wait should stop instead of running out its cap.
    private var streamClosed = false

    /// Bumped by every `startStream`. A torn-down session's receive loop can
    /// still be parked in `task.receive()`; it resumes on the actor only at the
    /// next suspension point, which — because `startStream` tears down, resets,
    /// and *then* awaits the socket handshake — falls inside the next session's
    /// window. Without this fence the dead session's `streamClosed = true` lands
    /// on a healthy socket and silently disables both the config gate and the
    /// finish waits.
    private var sessionGeneration = 0

    init(modelId: String, inputSampleRate: Double = AudioConfig.targetSampleRate) {
        self.modelId = modelId
        let capabilities = OpenAIModelCapabilities.forModel(modelId)
        self.capabilities = capabilities
        self.usesManualCommit = capabilities.realtimeUsesManualCommit
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

        // Tear down any prior session first so a reused actor never orphans its
        // old socket / receive + sender tasks.
        teardown()

        committed = []
        currentPartial = ""
        lastError = nil
        finishing = false
        finishSignaled = false
        pendingTranscripts = 0
        commitOnFinish = false
        streamClosed = false
        converter = nil
        self.onLiveText = onLiveText
        // Fence the previous session's receive loop out of everything reset here.
        sessionGeneration &+= 1
        let generation = sessionGeneration

        // Reset the config ladder — a previous session may have downgraded it,
        // and the next one deserves a fresh attempt at the best config.
        configStage = .full
        sessionConfigured = false
        usesManualCommit = capabilities.realtimeUsesManualCommit
        downgradedToManualCommit = false
        sessionPrompt = OpenAIModelCapabilities.combinedPrompt(
            initial: TranscriptionDecoderOptions.current.initialPrompt,
            context: contextPrompt
        )

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            throw TranscriptionEngineError.transcriptionFailed("Invalid OpenAI Realtime URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        startReceiveLoop(generation: generation)

        // Configure the transcription session before any audio is sent.
        await sendSessionConfig()

        let (audioStream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .unbounded
        )
        audioContinuation = continuation
        senderTask = Task { [weak self] in
            // Hold audio until the session is confirmed. The stream is unbounded,
            // so waiting buffers rather than drops — and audio sent before the
            // update lands (or after it was rejected) is transcribed by nothing.
            await self?.awaitSessionConfigured()
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

        if commitOnFinish || downgradedToManualCommit {
            // One-shot buffered session (or a live one the fallback ladder
            // dropped to no-VAD): the whole take is still uncommitted, so every
            // transcript may be in flight even with no partial in sight — and
            // there may be several, which the `finishSignaled` wait below would
            // truncate to the first. Commit the trailing buffer and wait for the
            // pending count to drain — after a settle window that lets the
            // commit's own `committed` event arrive — bailing if the socket dies.
            finishing = true
            finishSignaled = false
            await sendCommit()
            var waitedMs = 0
            while waitedMs < Self.bulkFinishCapMs, !streamClosed,
                  waitedMs < Self.bulkCommitSettleMs || pendingTranscripts > 0 {
                try? await Task.sleep(for: .milliseconds(Self.finishPollMs))
                waitedMs += Self.finishPollMs
            }
        } else if usesManualCommit || !currentPartial.isEmpty {
            // Live session. Two reasons to commit-and-wait here:
            //  - Server VAD (`!currentPartial.isEmpty`) has been auto-committing
            //    utterances as the user spoke, so at most the trailing one is
            //    pending; if nothing is pending everything is already committed.
            //  - Manual commit (`usesManualCommit`) never auto-commits, so the
            //    whole utterance's `completed` is still owed even when no partial
            //    has surfaced yet — always flush, regardless of `currentPartial`.
            // Either way, wait on `finishSignaled` up to the grace cap for the
            // final transcript. Silence that gets its commit rejected produces no
            // `completed`, but the cap (and a socket close, which signals finish)
            // still terminate the wait.
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
        commitOnFinish = true
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

        var transcription: [String: Any] = ["model": modelId]
        // Context fields only on the first rung: they are the most likely reason
        // for a rejection (an over-long prompt, a `<`/`>`/CR/LF in a keyword, or
        // a language code the server doesn't accept all reject the whole update),
        // so the first downgrade drops them wholesale.
        if configStage == .full {
            // Only the models wired up with `prompt` support opt in — see
            // `sendsRealtimePrompt`. The realtime models that shipped earlier
            // keep the exact `session.update` payload they always sent.
            if capabilities.sendsRealtimePrompt, let sessionPrompt {
                transcription["prompt"] = sessionPrompt
            }
            let opts = TranscriptionDecoderOptions.current
            if capabilities.supportsKeywords {
                let keywords = OpenAIModelCapabilities.sanitizedKeywords(from: opts.keywords)
                if !keywords.isEmpty { transcription["keywords"] = keywords }
            }
            if capabilities.usesPluralLanguages,
               let code = OpenAIModelCapabilities.validatedLanguageCode(opts.language) {
                transcription["languages"] = [code]
            }
        }
        // `delay` is deliberately never sent: the guide shows it on a
        // transcription session while the API reference scopes it to
        // `gpt-realtime-whisper` in GA sessions, and an unsupported field rejects
        // the entire update.

        var input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": 24_000],
            "transcription": transcription,
        ]
        switch configStage {
        case .full, .minimal:
            // Manual-commit models reject a `turn_detection` block — omit the key
            // entirely so the server transcribes only on explicit commits.
            if !usesManualCommit {
                input["turn_detection"] = [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500,
                ]
            }
        case .manualCommit:
            // Last rung: say `null` explicitly rather than omitting the key, so a
            // server that distinguishes "absent" from "null" still lands on no-VAD.
            input["turn_detection"] = NSNull()
        }

        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": ["input": input],
            ],
        ]
        guard let json = Self.encode(payload) else { return }
        try? await task.send(.string(json))
    }

    /// Blocks the sender task until the server confirms the session config, the
    /// socket dies, or the wait cap expires. Bounded on purpose: a server that
    /// never answers must cost one short stall, not the whole take.
    private func awaitSessionConfigured() async {
        var waitedMs = 0
        while !sessionConfigured, !streamClosed, !Task.isCancelled,
              waitedMs < Self.sessionConfigWaitMs {
            try? await Task.sleep(for: .milliseconds(Self.sessionConfigPollMs))
            waitedMs += Self.sessionConfigPollMs
        }
        if !sessionConfigured, !streamClosed, !Task.isCancelled {
            AppLog.dictation.warning(
                "OpenAI realtime session not confirmed within \(Self.sessionConfigWaitMs) ms; streaming audio anyway"
            )
        }
    }

    /// The server rejected a `session.update` that was never acknowledged, so the
    /// session as configured transcribes nothing. Step one rung down the ladder
    /// and resend; after the last rung, leave `lastError` holding the server's
    /// own message so `finishStream` surfaces it instead of an empty transcript.
    private func downgradeSessionConfig() {
        let next: SessionConfigStage?
        switch configStage {
        case .full: next = .minimal
        case .minimal: next = .manualCommit
        case .manualCommit: next = nil
        }
        guard let next else {
            AppLog.dictation.error("OpenAI realtime session config rejected at every fallback; giving up")
            return
        }
        configStage = next
        if next == .manualCommit {
            // Nothing will auto-commit from here on, so `finishStream` has to
            // flush and wait even when no partial ever surfaced — and because
            // this session has been streaming live all along, that one commit
            // covers the whole recording rather than a trailing utterance.
            usesManualCommit = true
            downgradedToManualCommit = true
        }
        AppLog.dictation.warning("Retrying OpenAI realtime session config on a reduced fallback")
        Task { [weak self] in
            await self?.sendSessionConfig()
        }
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

    private func startReceiveLoop(generation: Int) {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(generation: generation)
        }
    }

    /// `generation` is the session this loop belongs to. Every write below is
    /// fenced on it still being the live one: `task.receive()` resumes whenever
    /// the actor next yields, which for a torn-down socket is typically already
    /// inside the *next* session (see `sessionGeneration`).
    private func receiveLoop(generation: Int) async {
        guard let task, generation == sessionGeneration else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard generation == sessionGeneration else { return }
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
        guard generation == sessionGeneration else { return }
        streamClosed = true
        signalFinishIfNeeded()
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated",
             "transcription_session.created", "transcription_session.updated":
            // Only `.updated` confirms our config landed — `.created` is the
            // server's greeting and arrives before the update is even read. Any
            // error seen before this point was a config rejection we recovered
            // from, so it must not outlive the retry as a stale `lastError`.
            if type.hasSuffix(".updated") {
                sessionConfigured = true
                lastError = nil
            }
            AppLog.dictation.info("OpenAI realtime session ready (\(type))")
        case "conversation.item.input_audio_transcription.delta":
            if let delta = obj["delta"] as? String {
                currentPartial += delta
                emitLiveText()
            }
        case "input_audio_buffer.committed":
            pendingTranscripts += 1
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = obj["transcript"] as? String, !transcript.isEmpty {
                committed.append(transcript)
            }
            currentPartial = ""
            pendingTranscripts = max(0, pendingTranscripts - 1)
            emitLiveText()
            signalFinishIfNeeded()
        case "error", "conversation.item.input_audio_transcription.failed":
            let err = (obj["error"] as? [String: Any])?["message"] as? String ?? type
            lastError = err
            if type == "conversation.item.input_audio_transcription.failed" {
                pendingTranscripts = max(0, pendingTranscripts - 1)
            }
            // Verbatim: for a rejected `session.update` this is the only
            // diagnostic there is — the server never says which field it disliked
            // anywhere else.
            AppLog.dictation.error("OpenAI realtime error: \(err)")
            // An error before the session was ever confirmed is a rejected config,
            // not a failed utterance: retry on a reduced one instead of streaming
            // into a session that will never transcribe.
            if type == "error", !sessionConfigured {
                downgradeSessionConfig()
            }
        default:
            break // speech_started/stopped, item.created, etc.
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
        commitOnFinish = false
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
    /// Cap on holding audio while waiting for `session.updated`, sized to cover
    /// the whole fallback ladder (each rung is one round trip) without letting a
    /// silent server turn into a visible recording stall.
    private static let sessionConfigWaitMs = 2_000
    private static let sessionConfigPollMs = 25
    /// Buffered sessions: minimum wait so the manual commit's `committed`
    /// event can arrive before `pendingTranscripts == 0` is trusted.
    private static let bulkCommitSettleMs = 1_000
    /// Buffered sessions: hard cap on waiting for in-flight transcripts.
    private static let bulkFinishCapMs = 15_000
}
