import Foundation
import OSLog

nonisolated enum OpenAIEndpoint {
    static let transcriptions = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let models = URL(string: "https://api.openai.com/v1/models")!
    static let apiKeysDocs = URL(string: "https://platform.openai.com/api-keys")!
}

/// Groq's OpenAI-compatible API: the same paths under `/openai/v1`.
nonisolated enum GroqEndpoint {
    static let transcriptions = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let models = URL(string: "https://api.groq.com/openai/v1/models")!
    static let apiKeysDocs = URL(string: "https://console.groq.com/keys")!
}

/// A service that speaks OpenAI's `/audio/transcriptions` contract — the
/// multipart request, the `{"text"}` answer and the `{"error"}` envelope — and
/// so runs on `OpenAITranscriptionEngine`. Only those: ElevenLabs has an API of
/// its own and can't be named here.
nonisolated enum OpenAICompatibleService: Sendable {
    case openAI
    case groq

    var provider: CloudProvider {
        switch self {
        case .openAI: return .openAI
        case .groq: return .groq
        }
    }

    var displayName: String { provider.displayName }

    var transcriptionsURL: URL {
        switch self {
        case .openAI: return OpenAIEndpoint.transcriptions
        case .groq: return GroqEndpoint.transcriptions
        }
    }

    var modelsURL: URL {
        switch self {
        case .openAI: return OpenAIEndpoint.models
        case .groq: return GroqEndpoint.models
        }
    }

    /// Read on every request, so a key changed in Settings applies without
    /// rebuilding the engine.
    func readAPIKey() -> String? {
        switch self {
        case .openAI: return OpenAIAPIKey.read()
        case .groq: return GroqAPIKey.read()
        }
    }

    /// What a 404 or `model_not_found` means on this service, worded as the fix.
    var modelUnavailableMessage: String {
        switch self {
        case .openAI:
            // Both new July 2026 models ship as unversioned aliases with no
            // published tier requirement, so "your key can't see this model
            // yet" is a plausible first-run failure.
            return "This model isn't available on your OpenAI account yet. Pick another model in Settings → Models."
        case .groq:
            // Groq retires models on its own schedule; a retired id is the
            // likely way to land here.
            return "Groq no longer offers this model, or your account can't use it. Pick another model in Settings → Models."
        }
    }
}

enum OpenAIConnectionTest {
    /// Reachability probe used by the settings UI. Returns nil on success;
    /// a short user-facing failure message otherwise.
    case ok
    case rejected
    case failed(String)
}

/// Engine that uploads the captured audio buffer to an
/// `/audio/transcriptions` endpoint on OpenAI's API shape — OpenAI's own, or
/// Groq's (`service`). The API key is read from the service's key store on
/// every request so changes propagate without rebuilding the engine.
actor OpenAITranscriptionEngine: TranscriptionEngine {
    let modelId: String
    private let service: OpenAICompatibleService

    /// Which fields this model accepts (and which it rejects outright).
    private let capabilities: OpenAIModelCapabilities

    /// Replaced wholesale when a request dies on a stale pooled connection, or
    /// proactively after a long idle gap (see `send`); otherwise lives for the
    /// engine's lifetime.
    private var session: URLSession
    private var lastRequestFinishedAt: Date?
    private let sampleRate: Int

    /// Below this idle gap since the last request, the pooled connection is
    /// assumed alive and reused as-is. Above it, refreshing proactively costs
    /// one extra handshake but avoids paying a full request timeout to
    /// discover a NAT/VPN-expired connection reactively — the exact scenario
    /// `send`'s reactive retry exists for, and the difference between a quick
    /// take and a stall that silently doubles the request timeout.
    private nonisolated static let staleSessionIdleThreshold: TimeInterval = 30

    /// Tail of the prior chunk's transcript passed as `prompt` to the next
    /// — gives the model rolling context for consistent punctuation and
    /// proper-noun spelling across boundaries.
    private nonisolated static let contextPromptTailLength = 200

    init(modelId: String, service: OpenAICompatibleService = .openAI, sampleRate: Int = 16_000) {
        self.modelId = modelId
        self.service = service
        self.capabilities = .forModel(modelId)
        self.sampleRate = sampleRate
        self.session = Self.makeSession()
    }

    private nonisolated static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // Idle-timeout ceiling: each chunk request overrides this with a
        // value scaled to its audio length (see `requestTimeout`); the
        // resource budget covers a full chunked job.
        config.timeoutIntervalForRequest = 240
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }

    nonisolated var isReady: Bool {
        get async { service.readAPIKey() != nil }
    }

    /// All models here split over-long input via `AudioChunker` and
    /// carry their own cross-request context, so callers must not pre-chunk.
    nonisolated var chunksInternally: Bool { true }

    func prepare(progress: PrepareProgress?) async throws {
        progress?(0.5, "Checking API key…")
        guard service.readAPIKey() != nil else {
            throw TranscriptionEngineError.modelLoadFailed(
                "\(service.displayName) API key not configured. Add one in Settings → Cloud."
            )
        }
        progress?(1.0, "Ready")
    }

    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress: TranscribeProgress?
    ) async throws -> String {
        guard let apiKey = service.readAPIKey() else {
            throw TranscriptionEngineError.notReady
        }
        #if DEBUG
        try CloudQuotaSimulation.throwIfEnabled(for: service.provider)
        #endif

        // The diarizing model has its own request shape and its own cross-request
        // continuity mechanism (speaker pinning); see `transcribeDiarize`.
        if capabilities.isDiarize {
            return try await transcribeDiarize(samples: samples, apiKey: apiKey, progress: progress)
        }

        let chunks = AudioChunker.split(samples: samples, sampleRate: sampleRate)
        guard !chunks.isEmpty else { return "" }

        var pieces: [String] = []
        pieces.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            let rollingContext = pieces.last.map { Self.tail(of: $0) }
            let combinedContext = [contextPrompt, rollingContext]
                .compactMap { $0 }
                .joined(separator: " ")
            let text = try await transcribeChunk(
                samples: chunk,
                apiKey: apiKey,
                contextPrompt: combinedContext.isEmpty ? nil : combinedContext
            )
            pieces.append(text)
            progress?(index + 1, chunks.count)
        }

        return pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeChunk(
        samples: [Float],
        apiKey: String,
        contextPrompt: String?
    ) async throws -> String {
        let opts = TranscriptionDecoderOptions.current
        let wav = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = Self.authorizedRequest(url: service.transcriptionsURL, apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout(
            forAudioSeconds: Double(samples.count) / Double(sampleRate)
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        // Models on the plural-`languages` form reject the singular `language`
        // alongside it, and reject a malformed code outright — so their language
        // goes through validation and the singular field is suppressed entirely.
        // Every older OpenAI model keeps its previous behavior: raw `language`,
        // no `keywords`; Groq's get the singular field, validated. Neither
        // `chunking_strategy` nor `known_speaker_*[]` is reachable from this
        // path — both are scoped to the diarizing model. The prompt clamp is
        // scoped per model too; see `batchPrompt`.
        request.httpBody = OpenAIRequestBuilder.makeMultipartBody(
            boundary: boundary,
            modelId: modelId,
            wav: wav,
            language: capabilities.batchLanguage(opts.language),
            prompt: capabilities.batchPrompt(initial: opts.initialPrompt, context: contextPrompt),
            // The docs' own `gpt-transcribe` examples omit `response_format`, and
            // the reference states per-model restrictions for every model *except*
            // this one — so sending the endpoint-wide `json` default explicitly is
            // an assumption. Revisit if a 400 ever names `response_format`.
            responseFormat: capabilities.batchResponseFormat,
            languages: capabilities.batchLanguages(opts.language),
            keywords: capabilities.supportsKeywords
                ? OpenAIModelCapabilities.sanitizedKeywords(from: opts.keywords)
                : []
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw Self.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionEngineError.transcriptionFailed("Invalid \(service.displayName) response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.httpError(http, body: data, service: service)
        }

        struct Body: Decodable { let text: String }
        do {
            let body = try JSONDecoder().decode(Body.self, from: data)
            return body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed("Could not parse \(service.displayName) response")
        }
    }

    /// Diarizing path for `gpt-4o-transcribe-diarize`. This model has no
    /// `prompt`, so cross-request continuity for a long recording is instead
    /// carried by pinning speakers: after each chunk we pick a short reference
    /// clip per canonical speaker and pass them into the next chunk as
    /// `known_speaker_names[]` / `known_speaker_references[]`, so "Speaker N"
    /// stays the same person across the whole call. All state is local to this
    /// call. `contextPrompt` is ignored (unsupported).
    private func transcribeDiarize(
        samples: [Float],
        apiKey: String,
        progress: TranscribeProgress?
    ) async throws -> String {
        let chunks = AudioChunker.split(samples: samples, sampleRate: sampleRate)
        guard !chunks.isEmpty else { return "" }

        let language = TranscriptionDecoderOptions.current.language
        var allSegments: [DiarizedTranscript.Segment] = []
        var labelMap = DiarizedTranscript.SpeakerLabelMap()
        var references: [String: [Float]] = [:]

        for (index, chunk) in chunks.enumerated() {
            let (names, refs) = knownSpeakerFields(references: references, order: labelMap.order)
            let rawSegments = try await transcribeDiarizeChunk(
                samples: chunk,
                apiKey: apiKey,
                language: language,
                knownSpeakerNames: names,
                knownSpeakerReferences: refs
            )
            // Rewrite this response's raw labels to canonical names *before*
            // they touch shared state — raw letters recur across responses, so
            // scoping the assignment per chunk keeps distinct speakers distinct.
            let segments = DiarizedTranscript.canonicalize(
                segments: rawSegments,
                chunk: index,
                labelMap: &labelMap
            )
            references = DiarizedTranscript.referenceClips(
                fromChunk: chunk,
                segments: segments,
                sampleRate: sampleRate,
                labelMap: &labelMap,
                previous: references
            )
            allSegments.append(contentsOf: segments)
            progress?(index + 1, chunks.count)
        }

        return DiarizedTranscript.format(segments: allSegments)
    }

    private func transcribeDiarizeChunk(
        samples: [Float],
        apiKey: String,
        language: String?,
        knownSpeakerNames: [String],
        knownSpeakerReferences: [String]
    ) async throws -> [DiarizedTranscript.Segment] {
        let wav = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = Self.authorizedRequest(url: service.transcriptionsURL, apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout(
            forAudioSeconds: Double(samples.count) / Double(sampleRate)
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = OpenAIRequestBuilder.makeMultipartBody(
            boundary: boundary,
            modelId: modelId,
            wav: wav,
            language: language,
            prompt: nil,
            responseFormat: capabilities.batchResponseFormat,
            chunkingStrategy: "auto",
            knownSpeakerNames: knownSpeakerNames,
            knownSpeakerReferences: knownSpeakerReferences
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw Self.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionEngineError.transcriptionFailed("Invalid \(service.displayName) response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.httpError(http, body: data, service: service)
        }

        return try DiarizedTranscript.parse(data)
    }

    /// Builds the parallel `known_speaker_names[]` / `known_speaker_references[]`
    /// fields (max 4, in canonical order) from the reference clips captured so
    /// far. References are WAV-encoded and base64'd into `data:` URLs.
    private func knownSpeakerFields(
        references: [String: [Float]],
        order: [String]
    ) -> (names: [String], references: [String]) {
        var names: [String] = []
        var refs: [String] = []
        for name in order.prefix(4) {
            guard let clip = references[name] else { continue }
            let wav = WAVEncoder.encode(samples: clip, sampleRate: sampleRate)
            names.append(name)
            refs.append("data:audio/wav;base64,\(wav.base64EncodedString())")
        }
        return (names, refs)
    }

    /// A request that got no answer. Typed so the failure card can tell
    /// "you're offline" from the rest; the message is the one it always was.
    private nonisolated static func networkError(_ error: Error) -> Error {
        let reason = "Network error: \(error.localizedDescription)"
        guard let urlError = error as? URLError else {
            return TranscriptionEngineError.transcriptionFailed(reason)
        }
        return CloudTranscriptionError(cause: .transport(urlError.code), reason: reason)
    }

    /// A non-2xx answer, typed so the failure card can tell a refused key or
    /// a rate limit from the rest; the message is the one it always was.
    private nonisolated static func httpError(
        _ http: HTTPURLResponse,
        body: Data,
        service: OpenAICompatibleService
    ) -> Error {
        let summary = errorMessage(from: body, status: http.statusCode, service: service)
            ?? "HTTP \(http.statusCode)"
        return CloudTranscriptionError.http(http, body: body, reason: "\(service.displayName): \(summary)")
    }

    /// One transparent retry for transport errors that typically mean the
    /// pooled keep-alive connection died while the app sat idle between takes
    /// (NAT/VPN mappings expire silently, and URLSession won't re-send a POST
    /// on its own). The dead socket can still sit in the session's connection
    /// pool — there's no API to flush it, and HTTP/2 would happily multiplex
    /// the retry onto the same corpse — so the session itself is replaced to
    /// guarantee the retry rides a fresh connection. All other failures
    /// propagate immediately.
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let last = lastRequestFinishedAt,
           Date().timeIntervalSince(last) > Self.staleSessionIdleThreshold {
            AppLog.engine.debug(
                "\(self.service.displayName, privacy: .public) session idle for \(Date().timeIntervalSince(last), format: .fixed(precision: 1))s; refreshing connection before request"
            )
            session.invalidateAndCancel()
            session = Self.makeSession()
        }
        defer { lastRequestFinishedAt = Date() }
        do {
            return try await session.data(for: request)
        } catch let error as URLError
            where error.code == .networkConnectionLost || error.code == .timedOut {
            AppLog.engine.warning(
                "\(self.service.displayName, privacy: .public) transcription request failed (URLError \(error.code.rawValue)); retrying on a fresh connection"
            )
            session.invalidateAndCancel()
            session = Self.makeSession()
            return try await session.data(for: request)
        }
    }

    /// Idle timeout for a single chunk request. Whisper-1 can take 90–180 s
    /// to process a full 10-minute chunk, but a short dictation take should
    /// fail (and offer Retry) quickly instead of hanging for that worst case
    /// — so the allowance scales with the chunk's audio length.
    private nonisolated static func requestTimeout(forAudioSeconds seconds: Double) -> TimeInterval {
        min(240, max(60, 45 + seconds))
    }

    private nonisolated static func tail(of text: String) -> String {
        guard text.count > contextPromptTailLength else { return text }
        return String(text.suffix(contextPromptTailLength))
    }

    /// Lightweight reachability check used by the Cloud settings pane. Hits
    /// the service's `/v1/models` with the saved API key and reports whether
    /// the key works.
    static func testConnection(service: OpenAICompatibleService = .openAI) async -> OpenAIConnectionTest {
        guard let apiKey = service.readAPIKey() else {
            return .failed("No key configured.")
        }
        return await testConnection(apiKey: apiKey, service: service)
    }

    /// The same probe against a key that has not been saved yet — what the
    /// paste-to-connect field verifies before committing anything to storage.
    static func testConnection(
        apiKey: String,
        service: OpenAICompatibleService = .openAI
    ) async -> OpenAIConnectionTest {
        var request = authorizedRequest(url: service.modelsURL, apiKey: apiKey)
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

    private nonisolated static func authorizedRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private nonisolated static func errorMessage(
        from data: Data,
        status: Int,
        service: OpenAICompatibleService
    ) -> String? {
        struct Envelope: Decodable {
            struct ErrorBody: Decodable {
                let message: String?
                let code: String?
            }
            let error: ErrorBody
        }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        let message = envelope?.error.message
        if isModelUnavailable(status: status, code: envelope?.error.code, message: message) {
            return service.modelUnavailableMessage
        }
        if let message, !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8)
    }

    /// "Your key can't see this model" — the raw API string for it ("The model
    /// `…` does not exist…") reads like an app bug, so the message names the
    /// fix instead (`OpenAICompatibleService.modelUnavailableMessage`).
    private nonisolated static func isModelUnavailable(
        status: Int,
        code: String?,
        message: String?
    ) -> Bool {
        // A 404 from this endpoint can only be an unknown model — the URL is a
        // compile-time constant.
        if status == 404 { return true }
        let haystack = [code, message].compactMap { $0 }.joined(separator: " ").lowercased()
        return haystack.contains("model_not_found")
    }
}
