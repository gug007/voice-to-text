import Foundation
import Observation

nonisolated enum OpenAIChat {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let modelId = "gpt-5.5"
    static let chunkCharacterLimit = 60_000

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 240
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    static func send(_ body: Data, apiKey: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw Failure(message: "You're offline. Summaries and action items need the internet.")
        } catch let error as URLError where error.code == .timedOut {
            throw Failure(message: "OpenAI took too long to answer. Try again.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw Failure(message: "OpenAI sent an answer that couldn't be read.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(message: errorMessage(status: http.statusCode, body: data))
        }

        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let content = try? JSONDecoder().decode(Envelope.self, from: data).choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure(message: "OpenAI sent back an empty answer. Try again.")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func errorMessage(status: Int, body: Data) -> String {
        struct Envelope: Decodable {
            struct ErrorBody: Decodable {
                let message: String?
                let code: String?
            }
            let error: ErrorBody
        }
        let parsed = try? JSONDecoder().decode(Envelope.self, from: body)
        if status == 401 { return "OpenAI didn't accept your API key. Check it in Settings." }
        if parsed?.error.code == "insufficient_quota" {
            return "Your OpenAI account is out of credit. Add credit, then try again."
        }
        if status == 429 { return "OpenAI is rate-limiting this key. Wait a moment and try again." }
        if let message = parsed?.error.message, !message.isEmpty { return "OpenAI: \(message)" }
        return "OpenAI returned an error (HTTP \(status))."
    }
}

@Observable
final class Insights {
    static let shared = Insights()

    nonisolated struct Job: Hashable, Sendable {
        let entryID: UUID
        let kind: InsightKind
    }

    private(set) var running: Set<Job> = []
    private(set) var failures: [Job: String] = [:]
    private(set) var progress: [Job: Transcriber.Progress] = [:]

    private init() {}

    func isRunning(_ id: UUID, _ kind: InsightKind) -> Bool {
        running.contains(Job(entryID: id, kind: kind))
    }

    func failure(_ id: UUID, _ kind: InsightKind) -> String? {
        failures[Job(entryID: id, kind: kind)]
    }

    func progress(_ id: UUID, _ kind: InsightKind) -> Transcriber.Progress? {
        progress[Job(entryID: id, kind: kind)]
    }

    func generate(entryID: UUID, kind: InsightKind) async {
        let job = Job(entryID: entryID, kind: kind)
        guard !running.contains(job), let entry = Library.shared.entry(id: entryID) else { return }
        failures[job] = nil

        guard !entry.transcriptIsPlaceholder else {
            failures[job] = "This recording has no transcript yet."
            return
        }
        guard let apiKey = OpenAIKeychain.read() else {
            failures[job] = "Add your OpenAI API key in Settings first."
            return
        }
        let text = entry.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            failures[job] = "There is nothing to summarize yet."
            return
        }

        running.insert(job)
        defer {
            running.remove(job)
            progress[job] = nil
        }
        let digest = TranscriptDigest.of(entry.transcript)

        do {
            switch kind {
            case .summary:
                let summary = try await summarize(text, job: job, apiKey: apiKey)
                Library.shared.update(id: entryID) {
                    $0.updatingSummary(TranscriptSummary(
                        text: summary,
                        generatedAt: Date(),
                        modelId: OpenAIChat.modelId,
                        sourceDigest: digest
                    ))
                }
            case .actionItems:
                let parsed = try await extractItems(text, job: job, apiKey: apiKey)
                let fresh = TranscriptActionItems(
                    items: parsed.map { ActionItem(text: $0.text, owner: $0.owner, due: $0.due) },
                    generatedAt: Date(),
                    modelId: OpenAIChat.modelId,
                    sourceDigest: digest
                )
                Library.shared.update(id: entryID) {
                    $0.updatingActionItems(
                        TranscriptInsightRequest.carryingDoneFlags(from: $0.actionItems, onto: fresh)
                    )
                }
            case .custom:
                break
            }
        } catch {
            failures[job] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func summarize(_ text: String, job: Job, apiKey: String) async throws -> String {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: OpenAIChat.chunkCharacterLimit)
        guard chunks.count > 1 else {
            return try await OpenAIChat.send(
                TranscriptInsightRequest.makeRequestBody(kind: .summary, text: text, modelId: OpenAIChat.modelId),
                apiKey: apiKey
            )
        }
        var parts: [String] = []
        progress[job] = .init(done: 0, total: chunks.count)
        for (index, chunk) in chunks.enumerated() {
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .summary,
                text: chunk,
                modelId: OpenAIChat.modelId,
                part: (index: index + 1, total: chunks.count)
            )
            parts.append(try await OpenAIChat.send(body, apiKey: apiKey))
            progress[job] = .init(done: index + 1, total: chunks.count)
        }
        return try await OpenAIChat.send(
            TranscriptInsightRequest.makeSummaryReduceBody(partialSummaries: parts, modelId: OpenAIChat.modelId),
            apiKey: apiKey
        )
    }

    private func extractItems(
        _ text: String,
        job: Job,
        apiKey: String
    ) async throws -> [TranscriptInsightRequest.ParsedActionItem] {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: OpenAIChat.chunkCharacterLimit)
        var items: [TranscriptInsightRequest.ParsedActionItem] = []
        if chunks.count > 1 { progress[job] = .init(done: 0, total: chunks.count) }
        for (index, chunk) in chunks.enumerated() {
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .actionItems,
                text: chunk,
                modelId: OpenAIChat.modelId,
                part: chunks.count > 1 ? (index: index + 1, total: chunks.count) : nil
            )
            let content = try await OpenAIChat.send(body, apiKey: apiKey)
            guard let parsed = TranscriptInsightRequest.parseActionItems(from: content) else {
                throw OpenAIChat.Failure(message: "OpenAI's answer couldn't be read as a list. Try again.")
            }
            items += parsed
            if chunks.count > 1 { progress[job] = .init(done: index + 1, total: chunks.count) }
        }
        return TranscriptInsightRequest.merging(items)
    }
}
