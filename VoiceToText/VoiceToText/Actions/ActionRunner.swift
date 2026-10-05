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

/// A chat-completions request that never produced an answer: no response at
/// all, or a non-2xx one. Carries the same cause a failed cloud transcription
/// does, so `TranscriptionFailure.classify` can tell an exhausted balance from
/// a refused key from a dropped connection — the flat "OpenAI: …" sentence it
/// replaces made the review banner say the same thing about all three.
///
/// A type of its own rather than more `ActionRunnerError` cases because
/// insight generation switches over those exhaustively; this one reaches it as
/// any other error, whose description is the sentence it always showed.
nonisolated struct ActionRequestError: LocalizedError, Equatable, Sendable {
    let cause: CloudTranscriptionError.Cause
    /// "Network error: …" or "OpenAI: …", worded as before it was typed.
    let detail: String
    /// The time limit the request ran under, when it never got an answer.
    /// What a timeout means depends on it: past the base a review action gets,
    /// its text bought it extra time and still ran out.
    var timeout: TimeInterval? = nil

    var errorDescription: String? { detail }

    var failure: TranscriptionFailure { TranscriptionFailure.classify(cause) }

    /// The request ran out of time rather than failing to connect: the model
    /// still writing a long answer, or a connection that stalled.
    var isTimeout: Bool { cause == .transport(.timedOut) }
}

/// Applies a dictation action to a transcript by sending the action's
/// instruction plus the text to OpenAI chat completions. The API key is read
/// from `OpenAIAPIKey` on every request so changes propagate immediately.
nonisolated enum ActionRunner {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let modelId = "gpt-5.5"

    static func run(instruction: String, on text: String) async throws -> String {
        guard OpenAIAPIKey.read() != nil else {
            throw ActionRunnerError.noAPIKey
        }
        let body = try makeRequestBody(instruction: instruction, text: text, modelId: modelId)
        return try await perform(
            body: body,
            timeout: timeout(forCharacterCount: text.count),
            session: actionSession
        )
    }

    /// How long a review action may take on `characterCount` characters of
    /// transcript. The reply is the whole text rewritten and chat completions
    /// sends none of it until the model has finished, so a long dictated prompt
    /// needs longer than a sentence: 60s, plus a second for every 50
    /// characters, up to the 240s an insight request gets. A flat 60s cut long
    /// prompts off mid-answer, after they had been billed; a short rewrite still
    /// gives up at 60s, and Esc stops any of them sooner.
    static func timeout(forCharacterCount characterCount: Int) -> TimeInterval {
        min(maxActionTimeout, baseActionTimeout + Double(max(0, characterCount)) / 50)
    }

    static let baseActionTimeout: TimeInterval = 60

    /// How far past `baseActionTimeout` the text has to stretch the limit
    /// before a timeout is blamed on its length: 30s, about 1,500 characters.
    /// Every non-empty text stretches it a little — a one-sentence rewrite
    /// gets 61s — and that sentence timing out was waiting on a stalled
    /// connection, not on its length.
    static let lengthBlameMargin: TimeInterval = 30

    /// Whether a request that timed out after `timeout` seconds ran long
    /// because of the text it was given (`lengthBlameMargin`).
    static func timeoutReflectsLength(_ timeout: TimeInterval) -> Bool {
        timeout >= baseActionTimeout + lengthBlameMargin
    }

    static let maxActionTimeout: TimeInterval = 240

    /// `URLSession.shared` caps every request at its configuration's own 60s
    /// whatever the request asks for, so the scaled timeout above needs a
    /// session of its own — built like `TranscriptInsightGenerator.longCallSession`.
    private static let actionSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = maxActionTimeout
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    /// One chat-completions round trip: post `body`, and return the assistant's
    /// message sanitized, or throw. A request that got no answer, or a non-2xx
    /// one, throws `ActionRequestError`, which callers can classify; the rest
    /// throw an `ActionRunnerError` describing what went wrong in words a user
    /// can act on.
    ///
    /// Takes an already-encoded body so anything that speaks this endpoint can
    /// share the transport, the error mapping and the cancellation handling —
    /// `TranscriptInsightRequest`'s summary and action-item payloads are not
    /// dictation actions, but they are the same HTTP call with the same key.
    ///
    /// `timeout` and `session` are parameters rather than constants because
    /// callers ask very different things of the model, and chat completions is
    /// non-streaming, so *nothing* arrives until the entire answer is written.
    /// `timeoutInterval` is an idle timeout, which on this endpoint means a hard
    /// wall-clock cap on the model's thinking time — the 60s default suits a
    /// one-sentence rewrite and cuts anything longer off mid-answer, after the
    /// call has already been billed. `URLSession.shared`'s own configuration
    /// also caps requests at 60s, so a longer call has to bring its own session:
    /// a review action scales its timeout with its text (`run`), an insight
    /// request takes 240s (`TranscriptInsightGenerator.longCallSession`).
    static func perform(
        body: Data,
        timeout: TimeInterval = 60,
        session: URLSession = .shared
    ) async throws -> String {
        guard let apiKey = OpenAIAPIKey.read() else {
            throw ActionRunnerError.noAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw ActionRequestError(
                cause: .transport(error.code),
                detail: "Network error: \(error.localizedDescription)",
                timeout: timeout
            )
        } catch {
            throw ActionRunnerError.requestFailed("Network error: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ActionRunnerError.requestFailed("Invalid OpenAI response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw httpError(http, body: data)
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

    /// A non-2xx answer, read through the transcription error so the status,
    /// the body's `error.code` and any Retry-After mean exactly what they do
    /// for a failed upload.
    static func httpError(_ response: HTTPURLResponse, body: Data) -> ActionRequestError {
        let summary = errorMessage(from: body) ?? "HTTP \(response.statusCode)"
        let cause = CloudTranscriptionError.http(response, body: body, reason: summary).cause
        return ActionRequestError(cause: cause, detail: "OpenAI: \(summary)")
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
        // An empty body falls through to the caller's "HTTP <status>" rather
        // than leaving "OpenAI: " with nothing after it.
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return raw
    }
}

/// What the review banner says when an action fails. Leads with the action's
/// name, because the banner otherwise reads like the dictation itself went
/// wrong, and ends by saying the transcript is untouched — a user told only
/// "out of credit" over their only copy of a long dictation has every reason
/// to think it is gone.
///
/// Foundation-only and `nonisolated`, like `TranscriptionFailure`, so the
/// harness compiles it standalone.
nonisolated struct ReviewActionFailure: Equatable, Sendable {
    /// The banner's own way to fix the key, when that is what failed.
    enum KeyAction: Equatable, Sendable {
        case add
        case check
    }

    let message: String
    let keyAction: KeyAction?

    /// Action names are the user's own and can run long; past this the banner
    /// would spend its two lines on the name and cut off the reassurance.
    static let longestNameShown = 32
    /// The same for an unclassified error's own text, which can be a whole
    /// response body.
    static let longestDetailShown = 70

    init(actionName: String, error: Error) {
        let name = "“\(Self.clipped(actionName, to: Self.longestNameShown))”"
        let unchanged = "Your transcript is unchanged."
        let pasteStillWorks = "Your transcript is unchanged — Paste still works."
        func couldNotRun(_ reason: String) -> String {
            "Couldn't run \(name): \(reason). \(pasteStillWorks)"
        }

        switch error as? ActionRunnerError {
        case .noAPIKey:
            message = "Couldn't run \(name): actions need an OpenAI API key. \(unchanged)"
            keyAction = .add
            return
        case .emptyResult:
            message = "\(name) came back empty. \(pasteStillWorks)"
            keyAction = nil
            return
        case .requestFailed, nil:
            break
        }

        guard let request = error as? ActionRequestError else {
            message = Self.unclassified(name: name, detail: error.localizedDescription, suffix: pasteStillWorks)
            keyAction = nil
            return
        }
        if request.isTimeout {
            // Blame the text only when it is what stretched the time limit: a
            // short rewrite that ran out its minute or so was waiting on a
            // stalled connection, and shortening it would not help.
            message = if let timeout = request.timeout, ActionRunner.timeoutReflectsLength(timeout) {
                "\(name) took too long for this much text. \(unchanged)"
            } else {
                "Couldn't run \(name): OpenAI didn't answer in time — check your connection. \(unchanged)"
            }
            keyAction = nil
            return
        }
        switch request.failure {
        case .quotaExhausted:
            message = couldNotRun("OpenAI says your account is out of credit")
            keyAction = nil
        case .unauthorized:
            message = "Couldn't run \(name): OpenAI didn't accept your API key. \(unchanged)"
            keyAction = .check
        case .rateLimited(let retryAfter):
            let wait = retryAfter.map { ", try again in \(TranscriptionFailure.waitDescription($0))" } ?? ""
            message = couldNotRun("OpenAI is rate-limiting requests\(wait)")
            keyAction = nil
        case .server:
            message = couldNotRun("OpenAI is having trouble right now")
            keyAction = nil
        case .offline:
            message = couldNotRun("you're offline")
            keyAction = nil
        case .other:
            message = Self.unclassified(name: name, detail: request.detail, suffix: pasteStillWorks)
            keyAction = nil
        }
    }

    /// "Couldn't run “X” (OpenAI: …)." — the error's own words, in brackets
    /// so they can't run into the sentence around them.
    private static func unclassified(name: String, detail: String, suffix: String) -> String {
        var detail = clipped(detail, to: longestDetailShown)
        while let last = detail.last, last == "." || last == ":" {
            detail.removeLast()
        }
        guard !detail.isEmpty else { return "Couldn't run \(name). \(suffix)" }
        return "Couldn't run \(name) (\(detail)). \(suffix)"
    }

    /// One line, at most `limit` characters, ending in "…" when cut.
    static func clipped(_ text: String, to limit: Int) -> String {
        let line = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard line.count > limit else { return line }
        let cut = line.prefix(max(0, limit - 1)).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }
}
