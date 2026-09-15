import Foundation
import Observation

/// Generates the Summary, the Action Items and the results of the user's own
/// instructions for a saved recording, and writes them back into History.
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
    /// The newest custom-job failure per recording, read through
    /// `customFailure(entryID:)`. Backs the one message that has no tab to live
    /// on, because the job it belongs to never produced a result.
    private(set) var customFailureByEntry: [UUID: String] = [:]

    /// What identifies a resumable chunked run.
    ///
    /// Deliberately *not* the `Job`. A brand-new custom result's id is minted
    /// fresh on every attempt — there is no stored result to name it after, and
    /// a failed run stores nothing — so a `Job`-keyed checkpoint could never be
    /// looked up again and every retry of the expensive first run would re-send,
    /// and re-pay for, the parts the previous attempt already got back. What
    /// actually identifies a run is the recording, the *family* of work (the
    /// custom id left out on purpose) and the exact input.
    ///
    /// `inputDigest` is what makes the key safe to reuse: it folds in the text
    /// the parts were generated from, so a re-transcription — or a speaker
    /// rename, which changes what the model reads — starts over rather than
    /// stitching parts of two different conversations together, and on the
    /// custom path it folds in the instruction too, so parts written under
    /// "translate to Russian" are never resumed into "list only the decisions".
    nonisolated struct RunKey: Hashable, Sendable {
        let entryID: UUID
        let kindTag: String
        let inputDigest: String
    }

    /// What a chunked job has already got back, kept across a failure.
    ///
    /// A two-hour meeting is several sequential, individually billed requests;
    /// losing all of them because the last one timed out means the user pays
    /// twice for the same parts, and a part that reliably fails would make the
    /// job impossible rather than merely slow. Not observed — no view reads it,
    /// and re-rendering every row because a part landed would be noise.
    private struct PartialRun {
        /// Chunks already answered — the index the next attempt resumes from.
        /// Counted separately from the payloads below because a chunk can
        /// legitimately yield zero action items.
        var doneChunks: Int = 0
        /// The plain text each answered part came back with — a part summary on
        /// the summary path, a part result on the custom one. Shared because
        /// both are "N strings in, one reduce request out".
        var partTexts: [String] = []
        var items: [TranscriptInsightRequest.ParsedActionItem] = []
    }

    @ObservationIgnored private var partialRuns: [RunKey: PartialRun] = [:]

    /// The family a run belongs to. Every custom run shares one tag whatever
    /// result id it carries — which is the whole point of `RunKey`.
    private nonisolated static func kindTag(for kind: InsightKind) -> String {
        switch kind {
        case .summary: return "summary"
        case .actionItems: return "actionItems"
        case .custom: return "custom"
        }
    }

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
        // The per-recording copy is the same message seen from the instruction
        // field; dismissing it on the tab has to clear it there too, or the note
        // reappears the moment the field is opened.
        if kind.isCustom { customFailureByEntry[entryID] = nil }
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
        // "Regenerate" on a custom tab is the user's own instruction replayed in
        // place — the instruction is stored with the result, so nothing has to
        // be re-typed. Routed into `generateCustom` rather than duplicated here
        // so the cap check, the reduce step and the prompt store have exactly
        // one implementation.
        if let id = kind.customID {
            guard let existing = entry.customInsight(id: id) else {
                setFailure("That result is no longer here — type the instruction again.", for: Job(entryID: entry.id, kind: kind))
                return false
            }
            return await generateCustom(
                entry: entry,
                instruction: existing.instruction,
                replacing: id
            ) != nil
        }

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
            case .custom:
                // Handled above, before any state was touched. Unreachable.
                return false
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

    // MARK: - Custom insights

    /// The custom results currently being generated for one recording, by id.
    ///
    /// A brand-new custom result's id is minted inside `generateCustom` — the
    /// row cannot name a job it has never seen an id for — so the UI asks "what
    /// is running on this recording" and shows a pending tab for each answer.
    /// The job is in `running` before the first request goes out, so a tab
    /// appears the moment the user hits go.
    func runningCustomIDs(entryID: UUID) -> Set<UUID> {
        var found: Set<UUID> = []
        for job in running where job.entryID == entryID {
            if let id = job.kind.customID { found.insert(id) }
        }
        return found
    }

    /// Failure messages for this recording's custom jobs, keyed by the id the
    /// tab would carry.
    func customFailures(entryID: UUID) -> [UUID: String] {
        var found: [UUID: String] = [:]
        for (job, message) in failures where job.entryID == entryID {
            guard let id = job.kind.customID else { continue }
            found[id] = message
        }
        return found
    }

    /// The newest failure from *any* custom job on one recording.
    ///
    /// A new custom result is refused — the cap, a missing key, a request that
    /// failed — before anything is stored, and its job is keyed by an id the UI
    /// never saw. Without this the message would have no tab to be shown on and
    /// the instruction field would just go quiet. The field reads this.
    func customFailure(entryID: UUID) -> String? { customFailureByEntry[entryID] }

    /// Clears both the per-recording message above and the per-job entry behind
    /// it, so dismissing the note in the instruction field does not leave the
    /// same text waiting on a tab.
    func dismissCustomFailure(entryID: UUID) {
        customFailureByEntry[entryID] = nil
        failures = failures.filter { !($0.key.entryID == entryID && $0.key.kind.isCustom) }
        // The chunk checkpoint is deliberately *not* cleared here. Dismissing
        // the note and retyping the same instruction is the ordinary way back
        // from a timeout, and resuming it is exactly what the checkpoint is for;
        // throwing it away on a dismissal would re-bill every part the failed
        // attempt already paid for. Nothing accumulates either way — see
        // `resumableRun`, which supersedes, and `forgetRecording`.
    }

    /// Forgets everything this generator is holding for one recording. Called
    /// when a deletion commits: a recording that is gone for good cannot have a
    /// result written back to it, so its checkpoints, its failure notes and its
    /// progress are all dead weight that would otherwise live until quit.
    func forgetRecording(entryID: UUID) {
        partialRuns = partialRuns.filter { $0.key.entryID != entryID }
        failures = failures.filter { $0.key.entryID != entryID }
        progressByJob = progressByJob.filter { $0.key.entryID != entryID }
        customFailureByEntry[entryID] = nil
    }

    /// How many of a recording's `maxCustomInsights` slots are spoken for: the
    /// results it already holds, plus the jobs in flight that have not landed in
    /// one yet.
    ///
    /// Both gates read this — the pre-flight in `generateCustom` and the Format
    /// button in the form — so no request is sent that has nowhere to land.
    /// Counting only what is stored would let the user queue four instructions
    /// in the time the first one takes; all four would be billed and the fourth,
    /// finished and paid for, would be refused by the store and dropped.
    func usedCustomSlots(for entry: RecordingHistoryEntry) -> Int {
        let pending = runningCustomIDs(entryID: entry.id)
            .filter { entry.customInsight(id: $0) == nil }
            .count
        return entry.customInsightList.count + pending
    }

    /// Runs one instruction the user typed over a recording's transcript and
    /// stores the result as its own tab.
    ///
    /// `insightID` names an existing result to re-run in place (its tab keeps
    /// its position and its id); nil asks for a new one, which is refused when
    /// the recording is already at `maxCustomInsights`. Returns the id the
    /// result landed under — for a new result that id is minted here, so the
    /// caller has no other way to learn it — and nil on every other path,
    /// leaving a message behind: same discipline as `generate(entry:kind:)`, for
    /// the same reason: no call site could do anything with an error but show it.
    @discardableResult
    func generateCustom(
        entry: RecordingHistoryEntry,
        instruction: String,
        replacing insightID: UUID?
    ) async -> UUID? {
        // A new result is addressed by an id minted here. The UI finds the job
        // through `runningCustomIDs(entryID:)`, which is why this must be the
        // same id the result is eventually stored under.
        let id = insightID ?? UUID()
        let job = Job(entryID: entry.id, kind: .custom(id))
        guard !running.contains(job) else { return nil }
        failures[job] = nil
        customFailureByEntry[entry.id] = nil

        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            setFailure("Say what you want done with this transcript.", for: job)
            return nil
        }
        guard hasAPIKey else {
            setFailure(Self.missingKeyMessage(for: .custom(id)), for: job)
            return nil
        }
        // Checked before a single request is paid for: a fourth result has
        // nowhere to go, and finding that out after two minutes of generation
        // would be the app billing the user for something it then throws away.
        //
        // In-flight jobs count towards the cap (`usedCustomSlots`): a slot a
        // running job is on its way to filling is not free, and without that the
        // user can type three instructions in the time the first one takes, pay
        // for all of them, and have the last finished document refused by the
        // store and thrown away. Read back from History rather than trusted from
        // `entry`, which is the snapshot the row took before any of this began.
        let current = RecordingHistoryStore.shared.entries.first { $0.id == entry.id } ?? entry
        if insightID == nil, usedCustomSlots(for: current) >= RecordingHistoryEntry.maxCustomInsights {
            setFailure(Self.capReachedMessage, for: job)
            return nil
        }
        // Relabelled before it is sent, for the same reason as the built-ins:
        // the row shows "Kara:" where the stored transcript says "Speaker 1:",
        // and meeting minutes naming Speaker 1 would read as if the names the
        // user typed had been ignored.
        let text = SpeakerRelabeler
            .apply(names: entry.speakerNames ?? [:], to: entry.transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            setFailure("There is nothing to reformat yet.", for: job)
            return nil
        }

        running.insert(job)
        defer {
            running.remove(job)
            progressByJob[job] = nil
        }
        // Remembered the moment a request is actually about to be spent, not
        // once one lands. Everything that can refuse an instruction for free —
        // a blank one, a missing key, the cap, an empty transcript — has already
        // returned above, so what is left is a sentence the user paid to run.
        // The moment they most need it offered back is exactly the one where it
        // failed on a timeout or a network blip: the popover that collected it
        // closed before the job started, nothing else holds a copy, and without
        // this it would have to be typed out from memory to be retried.
        InsightPromptStore.shared.remember(instruction)

        // From the canonical stored transcript, not the relabelled text — a
        // speaker rename is a display-time relabel and must not make every
        // stored result look stale.
        let digest = TranscriptDigest.of(entry.transcript)

        do {
            let parsed = try await customResult(for: text, instruction: instruction, job: job)
            let stored = RecordingHistoryStore.shared.setCustomInsight(
                entryID: entry.id,
                insight: CustomInsight(
                    id: id,
                    title: parsed.title,
                    instruction: instruction,
                    text: parsed.text,
                    generatedAt: Date(),
                    modelId: ActionRunner.modelId,
                    sourceDigest: digest
                ),
                replacingExisting: insightID != nil
            )
            // Two ways to be refused, and only one of them is worth saying out
            // loud. A *new* result that lost the last free slot to another row
            // while it was in flight is the cap arriving late — the user asked
            // for something the app cannot keep, so they are told. A *re-run* is
            // refused only when its tab is no longer there: the user deleted it
            // while it ran, which is an answer rather than an error, and the
            // recording the store has forgotten entirely has no row left to read
            // a message on anyway.
            guard stored else {
                if insightID == nil { setFailure(Self.capReachedMessage, for: job) }
                return nil
            }
            return id
        } catch is CancellationError {
            return nil
        } catch {
            setFailure(Self.message(for: error, kind: .custom(id)), for: job)
            return nil
        }
    }

    /// One instruction applied to a whole transcript, chunked when it is too
    /// long for a single request. Same map-reduce as the summary path, with the
    /// same per-part checkpointing — a two-hour meeting is several individually
    /// billed requests, and a timeout on the last one must not make the user pay
    /// for the first five again.
    private func customResult(
        for text: String,
        instruction: String,
        job: Job
    ) async throws -> TranscriptInsightRequest.ParsedCustomResult {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: Self.chunkCharacterLimit)
        let tag = Self.kindTag(for: job.kind)
        guard chunks.count > 1 else {
            clearPartialRuns(entryID: job.entryID, kindTag: tag)
            let body = try TranscriptInsightRequest.makeCustomBody(
                instruction: instruction,
                text: text,
                modelId: ActionRunner.modelId
            )
            return try Self.parseCustom(await Self.send(body), instruction: instruction)
        }

        // The instruction is folded into the resume digest as well as the text:
        // parts written under "translate to Russian" are not parts of the answer
        // to "list only the decisions", even on the very same transcript, and
        // re-running a tab with an edited instruction must start over. The key
        // deliberately carries no result id, so retyping the same instruction
        // after a timeout resumes from the parts already paid for instead of
        // buying them a second time.
        let key = RunKey(
            entryID: job.entryID,
            kindTag: tag,
            inputDigest: TranscriptDigest.of("\(instruction)\n\(text)")
        )
        var run = resumableRun(key: key, chunkCount: chunks.count)
        progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        for index in run.doneChunks..<chunks.count {
            let body = try TranscriptInsightRequest.makeCustomBody(
                instruction: instruction,
                text: chunks[index],
                modelId: ActionRunner.modelId,
                part: (index: index + 1, total: chunks.count)
            )
            // Only the text is carried forward; each part's title is thrown
            // away, because the reduce step names the whole result.
            run.partTexts.append(try Self.parseCustom(await Self.send(body), instruction: instruction).text)
            run.doneChunks = index + 1
            partialRuns[key] = run
            progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        }

        // Reduce by request, not in code: unlike a list of action items, these
        // parts are prose in a shape only the model knows, and stitching them
        // with "\n\n" would leave the user a document that repeats itself and
        // restarts its own headings three times.
        let merged = try Self.parseCustom(
            await Self.send(
                TranscriptInsightRequest.makeCustomReduceBody(
                    instruction: instruction,
                    parts: run.partTexts,
                    modelId: ActionRunner.modelId
                )
            ),
            instruction: instruction
        )
        partialRuns[key] = nil
        return merged
    }

    /// Records a failure against the job *and*, for a custom job, against the
    /// recording — see `customFailure(entryID:)` for why both are needed.
    private func setFailure(_ message: String, for job: Job) {
        failures[job] = message
        if job.kind.isCustom { customFailureByEntry[job.entryID] = message }
    }

    // MARK: - Generation

    private func summaryText(for text: String, job: Job) async throws -> String {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: Self.chunkCharacterLimit)
        let tag = Self.kindTag(for: job.kind)
        guard chunks.count > 1 else {
            clearPartialRuns(entryID: job.entryID, kindTag: tag)
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
        let key = RunKey(entryID: job.entryID, kindTag: tag, inputDigest: TranscriptDigest.of(text))
        var run = resumableRun(key: key, chunkCount: chunks.count)
        progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        for index in run.doneChunks..<chunks.count {
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .summary,
                text: chunks[index],
                modelId: ActionRunner.modelId,
                part: (index: index + 1, total: chunks.count)
            )
            run.partTexts.append(try await Self.send(body))
            run.doneChunks = index + 1
            partialRuns[key] = run
            progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        }

        // Reduce: the parts read as a list of separate meetings until they are
        // merged, so this last request is what makes the result a summary of one
        // conversation. The parts stay checkpointed until it lands, so a failure
        // here retries the merge alone.
        let merged = try await Self.send(
            TranscriptInsightRequest.makeSummaryReduceBody(
                partialSummaries: run.partTexts,
                modelId: ActionRunner.modelId
            )
        )
        partialRuns[key] = nil
        return merged
    }

    private func actionItems(
        for text: String,
        job: Job
    ) async throws -> [TranscriptInsightRequest.ParsedActionItem] {
        let chunks = TranscriptChunker.chunks(of: text, maxCharacters: Self.chunkCharacterLimit)
        let tag = Self.kindTag(for: job.kind)
        guard chunks.count > 1 else {
            clearPartialRuns(entryID: job.entryID, kindTag: tag)
            let body = try TranscriptInsightRequest.makeRequestBody(
                kind: .actionItems,
                text: text,
                modelId: ActionRunner.modelId
            )
            return try Self.parse(await Self.send(body))
        }

        let key = RunKey(entryID: job.entryID, kindTag: tag, inputDigest: TranscriptDigest.of(text))
        var run = resumableRun(key: key, chunkCount: chunks.count)
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
            partialRuns[key] = run
            progressByJob[job] = Progress(done: run.doneChunks, total: chunks.count)
        }
        partialRuns[key] = nil
        // Reduced in code, not by another request: merging lists is exact, and a
        // model asked to merge them would paraphrase the tasks it was told to
        // keep verbatim.
        return TranscriptInsightRequest.merging(run.items)
    }

    /// The parts a previous attempt already got back, or an empty run — and, in
    /// the same move, the guarantee that only one checkpoint per recording and
    /// kind is ever held. Anything generated from different input — a
    /// re-transcription, a speaker rename, an edited instruction — is dropped
    /// rather than mixed in, and so is a run that somehow holds more parts than
    /// there are chunks. Dropping rather than merely ignoring is what keeps the
    /// map from growing a dead entry per failed attempt for the life of the
    /// process; a long meeting's part texts are not small.
    private func resumableRun(key: RunKey, chunkCount: Int) -> PartialRun {
        for superseded in partialRuns.keys
        where superseded != key && superseded.entryID == key.entryID && superseded.kindTag == key.kindTag {
            partialRuns[superseded] = nil
        }
        if let run = partialRuns[key], run.doneChunks <= chunkCount { return run }
        return PartialRun()
    }

    /// Forgets every checkpoint for one recording and kind — what a run that no
    /// longer needs chunking, or one the user has walked away from, leaves behind.
    private func clearPartialRuns(entryID: UUID, kindTag: String) {
        partialRuns = partialRuns.filter { !($0.key.entryID == entryID && $0.key.kindTag == kindTag) }
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

    private static func parseCustom(
        _ content: String,
        instruction: String
    ) throws -> TranscriptInsightRequest.ParsedCustomResult {
        guard let parsed = TranscriptInsightRequest.parseCustomResult(
            from: content,
            instruction: instruction
        ) else {
            throw InsightError.unreadableReply
        }
        return parsed
    }

    // MARK: - Failure text

    private enum InsightError: LocalizedError {
        case unreadableReply

        var errorDescription: String? {
            "the reply wasn't in a format the app could read"
        }
    }

    /// Said when the recording already holds the most custom results it can
    /// show. Names the number and the way out, because "remove one first" with
    /// no count leaves the user counting tabs.
    private static let capReachedMessage =
        "This recording already has \(RecordingHistoryEntry.maxCustomInsights) custom results. Remove one first."

    private static func missingKeyMessage(for kind: InsightKind) -> String {
        switch kind {
        case .summary: return "Summaries need an OpenAI API key. Add one in Cloud."
        case .actionItems: return "Action items need an OpenAI API key. Add one in Cloud."
        case .custom: return "Formatting a transcript needs an OpenAI API key. Add one in Cloud."
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
        switch kind {
        case .summary: return "Couldn't generate the summary"
        case .actionItems: return "Couldn't extract action items"
        case .custom: return "Couldn't apply your instruction"
        }
    }
}
