import Foundation
import OSLog

nonisolated enum OpenAIEndpoint {
    static let transcriptions = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    static let models = URL(string: "https://api.openai.com/v1/models")!
    static let apiKeysDocs = URL(string: "https://platform.openai.com/api-keys")!
}

enum OpenAIConnectionTest {
    /// Reachability probe used by the settings UI. Returns nil on success;
    /// a short user-facing failure message otherwise.
    case ok
    case rejected
    case failed(String)
}

/// Engine that uploads the captured audio buffer to OpenAI's
/// `/v1/audio/transcriptions` endpoint. The API key is read from
/// `OpenAIAPIKey` on every request so changes propagate without rebuilding
/// the engine.
actor OpenAITranscriptionEngine: TranscriptionEngine {
    let modelId: String

    /// Replaced wholesale when a request dies on a stale pooled connection
    /// (see `send`); otherwise lives for the engine's lifetime.
    private var session: URLSession
    private let sampleRate: Int

    /// Tail of the prior chunk's transcript passed as `prompt` to the next
    /// — gives the model rolling context for consistent punctuation and
    /// proper-noun spelling across boundaries.
    private static let contextPromptTailLength = 200

    init(modelId: String, sampleRate: Int = 16_000) {
        self.modelId = modelId
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

    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress: TranscribeProgress?
    ) async throws -> String {
        guard let apiKey = OpenAIAPIKey.read() else {
            throw TranscriptionEngineError.notReady
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
        var request = Self.authorizedRequest(url: OpenAIEndpoint.transcriptions, apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout(
            forAudioSeconds: Double(samples.count) / Double(sampleRate)
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let prompt = [opts.initialPrompt, contextPrompt]
            .compactMap { $0 }
            .joined(separator: " ")
        request.httpBody = Self.makeMultipartBody(
            boundary: boundary,
            modelId: modelId,
            wav: wav,
            language: opts.language,
            prompt: prompt.isEmpty ? nil : prompt
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(
                "Network error: \(error.localizedDescription)"
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionEngineError.transcriptionFailed("Invalid OpenAI response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let summary = Self.errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw TranscriptionEngineError.transcriptionFailed("OpenAI: \(summary)")
        }

        struct Body: Decodable { let text: String }
        do {
            let body = try JSONDecoder().decode(Body.self, from: data)
            return body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed("Could not parse OpenAI response")
        }
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
        do {
            return try await session.data(for: request)
        } catch let error as URLError
            where error.code == .networkConnectionLost || error.code == .timedOut {
            AppLog.engine.warning(
                "OpenAI transcription request failed (URLError \(error.code.rawValue)); retrying on a fresh connection"
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
    /// `/v1/models` with the saved API key and reports whether the key works.
    static func testConnection() async -> OpenAIConnectionTest {
        guard let apiKey = OpenAIAPIKey.read() else {
            return .failed("No key configured.")
        }
        var request = authorizedRequest(url: OpenAIEndpoint.models, apiKey: apiKey)
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

    private nonisolated static func makeMultipartBody(
        boundary: String,
        modelId: String,
        wav: Data,
        language: String?,
        prompt: String?
    ) -> Data {
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }

        appendField("model", modelId)
        appendField("response_format", "json")
        if let language, !language.isEmpty {
            appendField("language", language)
        }
        if let prompt, !prompt.isEmpty {
            appendField("prompt", prompt)
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n".utf8))

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private nonisolated static func errorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct ErrorBody: Decodable { let message: String? }
            let error: ErrorBody
        }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data),
           let message = env.error.message,
           !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8)
    }
}
