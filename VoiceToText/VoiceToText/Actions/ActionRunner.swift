import Foundation

nonisolated enum ActionRunnerError: LocalizedError, Equatable {
    case noAPIKey
    case requestFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Actions need an OpenAI API key. Add one in Settings → Cloud."
        case .requestFailed(let message):
            return message
        case .emptyResult:
            return "The action returned empty text."
        }
    }
}

/// Applies a dictation action to a transcript by sending the action's
/// instruction plus the text to OpenAI chat completions. The API key is read
/// from `OpenAIAPIKey` on every request so changes propagate immediately.
nonisolated enum ActionRunner {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let modelId = "gpt-5.5"

    static func run(instruction: String, on text: String) async throws -> String {
        guard let apiKey = OpenAIAPIKey.read() else {
            throw ActionRunnerError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try makeRequestBody(instruction: instruction, text: text, modelId: modelId)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ActionRunnerError.requestFailed("Network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ActionRunnerError.requestFailed("Invalid OpenAI response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let summary = errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw ActionRunnerError.requestFailed("OpenAI: \(summary)")
        }

        guard let content = parseResponse(data) else {
            throw ActionRunnerError.requestFailed("Could not parse OpenAI response")
        }
        let cleaned = sanitize(content)
        guard !cleaned.isEmpty else {
            throw ActionRunnerError.emptyResult
        }
        return cleaned
    }

    // MARK: - Pure helpers (exercised by Tests/ActionRunnerHarness.swift)

    static func systemPrompt(for instruction: String) -> String {
        """
        You transform text that the user dictated by voice. Apply this instruction to the text:

        \(instruction)

        Reply with only the transformed text — no explanations, no preamble, and no surrounding quotes or code fences.
        """
    }

    static func makeRequestBody(instruction: String, text: String, modelId: String) throws -> Data {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        // No temperature override: GPT-5-family models reject non-default
        // values on chat completions, and the default suits rewrites fine.
        struct Payload: Encodable {
            let model: String
            let messages: [Message]
        }
        let payload = Payload(
            model: modelId,
            messages: [
                Message(role: "system", content: systemPrompt(for: instruction)),
                Message(role: "user", content: text),
            ]
        )
        return try JSONEncoder().encode(payload)
    }

    static func parseResponse(_ data: Data) -> String? {
        struct Body: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return body.choices.first?.message.content
    }

    /// Trims the model output and unwraps a whole-message markdown code fence
    /// (some models fence their answer despite instructions). Only a true
    /// single wrapper is unwrapped — output with interior fences (multiple
    /// code blocks) and quotes inside the text are left alone, since
    /// stripping those could mangle legit content.
    static func sanitize(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2,
              lines.first?.hasPrefix("```") == true,
              lines.last == "```",
              !lines.dropFirst().dropLast().contains(where: { $0.hasPrefix("```") })
        else { return trimmed }
        return lines.dropFirst().dropLast()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func errorMessage(from data: Data) -> String? {
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
