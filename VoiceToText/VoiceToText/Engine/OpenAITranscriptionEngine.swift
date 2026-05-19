import Foundation

/// Engine that uploads the captured audio buffer to OpenAI's
/// `/v1/audio/transcriptions` endpoint. The API key lives in the Keychain
/// and is read on every request so changes propagate without rebuilding the
/// engine.
actor OpenAITranscriptionEngine: TranscriptionEngine {
    let modelId: String

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.makeMultipartBody(
            boundary: boundary,
            modelId: modelId,
            wav: wav,
            language: opts.language,
            prompt: combinedPrompt(userPrompt: opts.initialPrompt, context: contextPrompt)
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
            let summary = Self.errorMessage(from: data)
                ?? "HTTP \(http.statusCode)"
            throw TranscriptionEngineError.transcriptionFailed("OpenAI: \(summary)")
        }

        struct Body: Decodable { let text: String }
        do {
            let body = try JSONDecoder().decode(Body.self, from: data)
            return body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(
                "Could not parse OpenAI response"
            )
        }
    }

    private func combinedPrompt(userPrompt: String?, context: String?) -> String? {
        switch (userPrompt, context) {
        case let (user?, ctx?):
            return user + " " + ctx
        case let (user?, nil):
            return user
        case let (nil, ctx?):
            return ctx
        case (nil, nil):
            return nil
        }
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
            body.append("--\(boundary)\r\n".utf8Data)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
            body.append(value.utf8Data)
            body.append("\r\n".utf8Data)
        }

        appendField("model", modelId)
        appendField("response_format", "json")
        if let language, !language.isEmpty {
            appendField("language", language)
        }
        if let prompt, !prompt.isEmpty {
            appendField("prompt", prompt)
        }

        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8Data)
        body.append("Content-Type: audio/wav\r\n\r\n".utf8Data)
        body.append(wav)
        body.append("\r\n".utf8Data)

        body.append("--\(boundary)--\r\n".utf8Data)
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

nonisolated private extension String {
    var utf8Data: Data { Data(self.utf8) }
}
