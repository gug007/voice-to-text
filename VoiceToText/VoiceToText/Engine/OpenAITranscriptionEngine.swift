import Foundation

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

    private let session: URLSession
    private let sampleRate: Int

    init(modelId: String, sampleRate: Int = 16_000) {
        self.modelId = modelId
        self.sampleRate = sampleRate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
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

    func transcribe(samples: [Float], contextPrompt: String?) async throws -> String {
        guard let apiKey = OpenAIAPIKey.read() else {
            throw TranscriptionEngineError.notReady
        }

        let opts = TranscriptionDecoderOptions.current
        let wav = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = Self.authorizedRequest(url: OpenAIEndpoint.transcriptions, apiKey: apiKey)
        request.httpMethod = "POST"
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
            (data, response) = try await session.data(for: request)
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
