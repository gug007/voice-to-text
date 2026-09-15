import Foundation
import Observation

/// Generates the Summary and Action Items for a saved recording and writes them
/// back into History.
///
/// State is keyed by `(entry, kind)` rather than held as a single "active job",
/// because unlike `TranscriptRegenerator` there is no shared transcription
/// engine to serialize against — these are stateless HTTP calls, so summarizing
/// one recording while extracting action items from another is fine and the
/// rows should not disable each other. The only thing refused is starting the
/// *same* job twice.
@Observable
@MainActor
final class TranscriptInsightGenerator {
    static let shared = TranscriptInsightGenerator()

    /// One generation: which recording, which insight. `nonisolated` because a
    /// `Set`/dictionary key's `Hashable` witnesses must be callable without the
    /// actor, which a MainActor-isolated nested type could not do.
    nonisolated struct Job: Hashable, Sendable {
        let entryID: UUID
        let kind: InsightKind
    }

    /// Chunk progress for a transcript too long to send in one request.
    nonisolated struct Progress: Hashable, Sendable {
        let done: Int
        let total: Int
    }

    private(set) var running: Set<Job> = []
    /// The last failure per job, in words for the row's inline note. Cleared
    /// when that job is started again or the user dismisses it.
    private(set) var failures: [Job: String] = [:]
    /// Only populated for chunked jobs — a single-request generation has no
    /// meaningful progress to report, and a "1 of 1" would be noise.
    private(set) var progressByJob: [Job: Progress] = [:]

    /// What a chunked job has already got back, kept across a failure.
    ///
    /// A two-hour meeting is several sequential, individually billed requests;
    /// losing all of them because the last one timed out means the user pays
    /// twice for the same parts, and a part that reliably fails would make the
    /// job impossible rather than merely slow. Not observed — no view reads it,
    /// and re-rendering every row because a part landed would be noise.
    private struct PartialRun {
        /// Digest of the exact text these parts were generated from. A
        /// re-transcription (or a speaker rename, which changes what the model
        /// reads) makes them parts of a different conversation, so the run is
        /// dropped rather than stitched onto fresh ones.
        let inputDigest: String
        /// Chunks already answered — the index the next attempt resumes from.
        /// Counted separately from the payloads below because a chunk can
        /// legitimately yield zero action items.
        var doneChunks: Int = 0
        var summaries: [String] = []
        var items: [TranscriptInsightRequest.ParsedActionItem] = []
    }

    @ObservationIgnored private var partialRuns: [Job: PartialRun] = [:]

    /// Above this many characters a transcript is split before it is sent. Sized
    /// well under the model's context so the prompt, the reply and a long
    /// conversation's worth of speaker labels all still fit — a two-hour meeting
    /// transcript lands around 70–90k characters, which is exactly the case this
    /// exists for.
    nonisolated static let chunkCharacterLimit = 60_000

    /// How long one insight request may take. Chat completions is not streamed,
    /// so nothing arrives until the model has finished writing the whole answer
    /// and `URLRequest.timeoutInterval` — an *idle* timeout — becomes a hard cap
    /// on how long the model may spend on up to `chunkCharacterLimit` characters
    /// of transcript. `ActionRunner`'s 60s default is sized for a one-sentence
    /// dictation rewrite and cuts a summary off mid-answer, after it has been
    /// billed. 240s is what `OpenAITranscriptionEngine` allows a long upload.
    private static let requestTimeout: TimeInterval = 240

    /// `URLSession.shared` caps every request at its configuration's own 60s
    /// regardless of what the request asks for, so a long call needs its own
    /// session. Built exactly like the transcription engine's.
    private static let longCallSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }()

    private init() {}

    func isRunning(entryID: UUID, kind: InsightKind) -> Bool {
        running.contains(Job(entryID: entryID, kind: kind))
    }

    func progress(entryID: UUID, kind: InsightKind) -> Progress? {
        progressByJob[Job(entryID: entryID, kind: kind)]
    }

    func failure(entryID: UUID, kind: InsightKind) -> String? {
        failures[Job(entryID: entryID, kind: kind)]
    }

    func dismissFailure(entryID: UUID, kind: InsightKind) {
        failures[Job(entryID: entryID, kind: kind)] = nil
    }

    /// Whether a key is configured at all. Read from the store rather than
    /// `OpenAIAPIKey` directly so the button enables itself the moment the user
    /// pastes a key in Cloud, without a refresh.
    var hasAPIKey: Bool { OpenAIAPIKeyStore.shared.hasKey }

    /// Generates one insight and stores it, replacing whatever was there before.
    /// Returns true only on success; every failure path leaves a message in
    /// `failures` for the row to show instead of throwing, because there is no
    /// call site that could do anything better with the error than display it.
    @discardableResult
    func generate(entry: RecordingHistoryEntry, kind: InsightKind) async -> Bool {
        let job = Job(entryID: entry.id, kind: kind)
        guard !running.contains(job) else { return false }
        failures[job] = nil

        guard hasAPIKey else {
            failures[job] = Self.missingKeyMessage(for: kind)
            return false
        }
        // Relabelled before it is sent: the row shows "Kara:" where the stored
        // transcript says "Speaker 1:", and a summary that talks about Speaker 1
        // — or a checklist assigning work to "Speaker 2" — would read as if the
        // names the user just typed had been ignored. `apply` merges adjacent
        // turns that end up with the same name, which is harmless for chunking.
        let text = SpeakerRelabeler
            .apply(names: entry.speakerNames ?? [:], to: entry.transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            failures[job] = "There is nothing to summarize yet."
            return false
        }

        running.insert(job)
        defer {
            running.remove(job)
            progressByJob[job] = nil
        }

        // The digest is taken from the canonical stored transcript, not from the
        // relabelled text above: speaker names are a display-time relabel, so
        // renaming "Speaker 2" to "Dan" must not make every insight look stale.
        // Untrimmed, because `isStale` recomputes the digest from this same
        // stored string.
        let digest = TranscriptDigest.of(entry.transcript)

        do {
            switch kind {
            case .summary:
                let summary = try await summaryText(for: text, job: job)
                RecordingHistoryStore.shared.setSummary(
                    entryID: entry.id,
                    summary: TranscriptSummary(
                        text: summary,
                        generatedAt: Date(),
                        modelId: ActionRunner.modelId,
                        sourceDigest: digest
                    )
                )
            case .actionItems:
                let parsed = try await actionItems(for: text, job: job)
                RecordingHistoryStore.shared.setActionItems(
                    entryID: entry.id,
                    actionItems: TranscriptActionItems(
                        items: parsed.map { ActionItem(text: $0.text, owner: $0.owner, due: $0.due) },
                        generatedAt: Date(),
                        modelId: ActionRunner.modelId,
                        sourceDigest: digest
                    )
                )
            }
            return true
        } catch is CancellationError {
            // The user navigated away or quit; nothing failed, so nothing to say.
            return false
        } catch {
            failures[job] = Self.message(for: error, kind: kind)
            return false
        }
    }

    // MARK: - Generation

    private func summaryText(for text: String, job: Job) async throws -> String {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: Self.chunkCharacterLimit)
        guard chunks.count > 1 else {
            partialRuns[job] = nil
            return try await Self.send(
                TranscriptInsightRequest.makeRequestBody(
                    kind: .summary,
                    text: text,
                    modelId: ActionRunner.modelId
                )
            )
        }

        // Map: one summary per part, sequentially, resuming after whatever a
        // previous attempt already paid for. Not concurrently — a dozen
        // simultaneous requests is how a long meeting hits a rate limit, and the
        // parts are only useful all together anyway.
        var run = resumableRun(job: job, inputDigest: TranscriptDigest.of(text), chunkCount: chunks.count)
        progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        for index in run.doneChunks..<chunks.count {
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .summary,
                text: chunks[index],
                modelId: ActionRunner.modelId,
                part: (index: index + 1, total: chunks.count)
            )
            run.summaries.append(try await Self.send(body))
            run.doneChunks = index + 1
            partialRuns[job] = run
            progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        }

        // Reduce: the parts read as a list of separate meetings until they are
        // merged, so this last request is what makes the result a summary of one
        // conversation. The parts stay checkpointed until it lands, so a failure
        // here retries the merge alone.
        let merged = try await Self.send(
            TranscriptInsightRequest.makeSummaryReduceBody(
                partialSummaries: run.summaries,
                modelId: ActionRunner.modelId
            )
        )
        partialRuns[job] = nil
        return merged
    }

    private func actionItems(
        for text: String,
        job: Job
    ) async throws -> [TranscriptInsightRequest.ParsedActionItem] {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: Self.chunkCharacterLimit)
        guard chunks.count > 1 else {
            partialRuns[job] = nil
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .actionItems,
                text: text,
                modelId: ActionRunner.modelId
            )
            return try Self.parse(await Self.send(body))
        }

        var run = resumableRun(job: job, inputDigest: TranscriptDigest.of(text), chunkCount: chunks.count)
        progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        for index in run.doneChunks..<chunks.count {
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .actionItems,
                text: chunks[index],
                modelId: ActionRunner.modelId,
                part: (index: index + 1, total: chunks.count)
            )
            run.items += try Self.parse(await Self.send(body))
            run.doneChunks = index + 1
            partialRuns[job] = run
            progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        }
        partialRuns[job] = nil
        // Reduced in code, not by another request: merging lists is exact, and a
        // model asked to merge them would paraphrase the tasks it was told to
        // keep verbatim.
        return TranscriptInsightRequest.merging(run.items)
    }

    /// The parts a previous attempt already got back, or an empty run. Anything
    /// generated from different text — a re-transcription, a speaker rename — is
    /// discarded rather than mixed in, and so is a run that somehow holds more
    /// parts than there are chunks.
    private func resumableRun(job: Job, inputDigest: String, chunkCount: Int) -> PartialRun {
        if let run = partialRuns[job], run.inputDigest == inputDigest, run.doneChunks <= chunkCount {
            return run
        }
        return PartialRun(inputDigest: inputDigest)
    }

    /// Every insight request goes over the long-call session with the long
    /// timeout; `ActionRunner`'s defaults belong to dictation actions.
    private static func send(_ body: Data) async throws -> String {
        try await ActionRunner.perform(body: body, timeout: requestTimeout, session: longCallSession)
    }

    private static func parse(_ content: String) throws -> [TranscriptInsightRequest.ParsedActionItem] {
        guard let items = TranscriptInsightRequest.parseActionItems(from: content) else {
            throw InsightError.unreadableReply
        }
        return items
    }

    // MARK: - Failure text

    private enum InsightError: LocalizedError {
        case unreadableReply

        var errorDescription: String? {
            "the reply wasn't in a format the app could read"
        }
    }

    private static func missingKeyMessage(for kind: InsightKind) -> String {
        switch kind {
        case .summary: return "Summaries need an OpenAI API key. Add one in Cloud."
        case .actionItems: return "Action items need an OpenAI API key. Add one in Cloud."
        }
    }

    /// One sentence naming what was being generated and what went wrong. The
    /// no-key case is re-mapped because `ActionRunner`'s own wording talks about
    /// dictation actions, which is not what the user just pressed.
    private static func message(for error: Error, kind: InsightKind) -> String {
        if let runnerError = error as? ActionRunnerError {
            switch runnerError {
            case .noAPIKey: return missingKeyMessage(for: kind)
            case .emptyResult: return "\(subject(for: kind)) — the model replied with nothing."
            case .requestFailed(let detail): return "\(subject(for: kind)) — \(detail)"
            }
        }
        return "\(subject(for: kind)) — \(error.localizedDescription)"
    }

    private static func subject(for kind: InsightKind) -> String {
        kind == .summary ? "Couldn't generate the summary" : "Couldn't extract action items"
    }
}
