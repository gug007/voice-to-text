import Foundation

struct RecordingHistoryHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RecordingHistoryHarnessFailure(description: message)
    }
}

private func makeEntry(
    id: UUID = UUID(),
    offset: TimeInterval,
    transcript: String = "hello",
    source: RecordingHistoryEntry.Source? = nil,
    isFavorite: Bool? = nil,
    speakerNames: [String: String]? = nil,
    summary: TranscriptSummary? = nil,
    actionItems: TranscriptActionItems? = nil,
    customInsights: [CustomInsight]? = nil,
    status: RecordingHistoryEntry.Status? = nil
) -> RecordingHistoryEntry {
    RecordingHistoryEntry(
        id: id,
        createdAt: Date(timeIntervalSinceReferenceDate: offset),
        transcript: transcript,
        audioFileName: "\(id.uuidString).wav",
        durationSeconds: 1.0,
        sampleRate: 16_000,
        modelId: "parakeet",
        modelName: "Parakeet",
        source: source,
        isFavorite: isFavorite,
        speakerNames: speakerNames,
        summary: summary,
        actionItems: actionItems,
        customInsights: customInsights,
        status: status
    )
}

/// Mirrors `RecordingHistoryStore.maxEntries`; the store itself is main-actor,
/// filesystem-bound code this harness doesn't compile.
private let cap = 200

private let sampleSummary = TranscriptSummary(
    text: "They agreed to ship on Friday.",
    generatedAt: Date(timeIntervalSinceReferenceDate: 0),
    modelId: "gpt-5.5",
    sourceDigest: "0123456789abcdef"
)

private let sampleActionItems = TranscriptActionItems(
    items: [ActionItem(text: "Ship it")],
    generatedAt: Date(timeIntervalSinceReferenceDate: 0),
    modelId: "gpt-5.5",
    sourceDigest: "0123456789abcdef"
)

private let sampleCustomInsight = CustomInsight(
    title: "Decisions",
    instruction: "list only the decisions",
    text: "- Ship on Friday.",
    generatedAt: Date(timeIntervalSinceReferenceDate: 0),
    modelId: "gpt-5.5",
    sourceDigest: "0123456789abcdef"
)

private let failedStatus = RecordingHistoryEntry.Status(
    kind: .failed,
    message: "OpenAI says your account is out of credit."
)

/// What `RecordingHistoryStore.insert` does to the visible list: prepend the
/// new entry, then prune, sparing the entries a job is working on.
private func inserting(
    _ entry: RecordingHistoryEntry,
    into library: [RecordingHistoryEntry],
    pinned: Set<UUID> = []
) -> RecordingHistoryPruner.Outcome {
    RecordingHistoryPruner.prune([entry] + library, maxUnprotected: cap, pinned: pinned)
}

/// Inserts `count` plain dictations, one at a time, each newer than the last,
/// starting after `offset`. Returns the library and everything pruned on the way.
private func insertingDictations(
    _ count: Int,
    after offset: TimeInterval,
    into library: [RecordingHistoryEntry],
    pinned: Set<UUID> = []
) -> (library: [RecordingHistoryEntry], removed: [RecordingHistoryEntry]) {
    var library = library
    var removed: [RecordingHistoryEntry] = []
    for i in 1...count {
        let outcome = inserting(makeEntry(offset: offset + TimeInterval(i)), into: library, pinned: pinned)
        library = outcome.kept
        removed += outcome.removed
    }
    return (library, removed)
}

private func isNewestFirst(_ entries: [RecordingHistoryEntry]) -> Bool {
    zip(entries, entries.dropFirst()).allSatisfy { $0.createdAt >= $1.createdAt }
}

private func unprotectedCount(_ entries: [RecordingHistoryEntry]) -> Int {
    entries.filter { !RecordingHistoryPruner.isProtected($0) }.count
}

@main
struct RecordingHistoryHarness {
    static func main() throws {
        try pruneKeepsNewestAndRemovesOverflow()
        try pruneSortsRegardlessOfInputOrder()
        try pruneWithNonPositiveMaxRemovesEveryUnprotected()
        try pruneUnderCapKeepsAll()
        try protectionCoversFavoritesConversationsInsightsAndSpeakers()
        try favoriteSurvives250Inserts()
        try conversationSurvives250Dictations()
        try insightAndSpeakerEntriesSurvive250Inserts()
        try failedTakeSurvives250DictationsUntilTranscribed()
        try protectedEntriesBeyondCapAreAllKept()
        try lostProtectionIsStampedOnlyWhenLost()
        try unprotectedAtRoundTripsAndSurvivesEdits()
        try unstarredOldFavoriteSurvivesTheNextInsert()
        try entryWithARunningJobSurvivesInserts()
        try undoAfterClearAllKeepsTheNewRecording()
        try undoBringsBackEvenTheOldestEntry()
        try clearAllSparesATakeStillTranscribing()
        try aTakeReclaimsItsRowFromTheUndoWindow()
        try codableRoundTrips()
        try favoriteFieldRoundTrips()
        try alternatesRoundTripAndDefaultEmpty()
        try regenerationKeepsPreviousTranscript()
        try removingActivePromotesNewestAlternate()
        try removingAlternateDropsItOnly()
        try removingOnlyTranscriptIsNoOp()
        try decodesIndexMissingOptionalModelFields()
        try joinsMeetingPiecesDroppingEmpties()
        try joinTrimsEachPiece()
        print("Recording history harness passed")
    }

    private static func joinsMeetingPiecesDroppingEmpties() throws {
        let result = MeetingTranscriptJoiner.join(["Hello world", "  ", "", "second part"])
        try expect(result == "Hello world second part", "joins non-empty pieces with single spaces")
    }

    private static func joinTrimsEachPiece() throws {
        let result = MeetingTranscriptJoiner.join(["  leading", "trailing  ", "\nnewline\n"])
        try expect(result == "leading trailing newline", "trims whitespace/newlines around each piece")
        try expect(MeetingTranscriptJoiner.join([]).isEmpty, "empty input → empty string")
        try expect(MeetingTranscriptJoiner.join(["", "  "]).isEmpty, "all-empty input → empty string")
    }

    private static func pruneKeepsNewestAndRemovesOverflow() throws {
        let entries = [
            makeEntry(offset: 100),
            makeEntry(offset: 300),
            makeEntry(offset: 200),
        ]
        let outcome = RecordingHistoryPruner.prune(entries, maxUnprotected: 2, pinned: [])
        try expect(outcome.kept.count == 2, "keeps maxUnprotected entries")
        try expect(outcome.kept[0].createdAt.timeIntervalSinceReferenceDate == 300, "newest first")
        try expect(outcome.kept[1].createdAt.timeIntervalSinceReferenceDate == 200, "second newest second")
        try expect(outcome.removed.count == 1, "removes the overflow")
        try expect(outcome.removed[0].createdAt.timeIntervalSinceReferenceDate == 100, "oldest is removed")
    }

    private static func pruneSortsRegardlessOfInputOrder() throws {
        let ascending = [makeEntry(offset: 1), makeEntry(offset: 2), makeEntry(offset: 3)]
        let outcome = RecordingHistoryPruner.prune(ascending, maxUnprotected: 10, pinned: [])
        let times = outcome.kept.map { $0.createdAt.timeIntervalSinceReferenceDate }
        try expect(times == [3, 2, 1], "unsorted input is normalized to newest-first")
    }

    private static func pruneWithNonPositiveMaxRemovesEveryUnprotected() throws {
        let favorite = makeEntry(offset: 0, isFavorite: true)
        let entries = [makeEntry(offset: 1), favorite, makeEntry(offset: 2)]
        let zero = RecordingHistoryPruner.prune(entries, maxUnprotected: 0, pinned: [])
        try expect(zero.kept == [favorite], "maxUnprotected 0 keeps only protected entries")
        try expect(zero.removed.count == 2, "maxUnprotected 0 removes every unprotected entry")
        let negative = RecordingHistoryPruner.prune(entries, maxUnprotected: -5, pinned: [])
        try expect(negative.kept == [favorite] && negative.removed.count == 2, "negative maxUnprotected acts like 0")
    }

    private static func pruneUnderCapKeepsAll() throws {
        let entries = [makeEntry(offset: 1), makeEntry(offset: 2)]
        let outcome = RecordingHistoryPruner.prune(entries, maxUnprotected: 5, pinned: [])
        try expect(outcome.kept.count == 2 && outcome.removed.isEmpty, "below cap keeps everything")
    }

    private static func protectionCoversFavoritesConversationsInsightsAndSpeakers() throws {
        let isProtected = RecordingHistoryPruner.isProtected
        try expect(!isProtected(makeEntry(offset: 1)), "a legacy entry with no source is an ordinary dictation")
        try expect(!isProtected(makeEntry(offset: 1, source: .dictation)), "a plain dictation is prunable")
        try expect(!isProtected(makeEntry(offset: 1, isFavorite: false)), "an unstarred entry is prunable")
        try expect(isProtected(makeEntry(offset: 1, isFavorite: true)), "favorites are protected")
        try expect(isProtected(makeEntry(offset: 1, source: .meeting)), "conversations are protected")
        try expect(isProtected(makeEntry(offset: 1, summary: sampleSummary)), "a summary protects its recording")
        try expect(isProtected(makeEntry(offset: 1, actionItems: sampleActionItems)), "action items protect their recording")
        try expect(isProtected(makeEntry(offset: 1, customInsights: [sampleCustomInsight])), "a custom result protects its recording")
        try expect(!isProtected(makeEntry(offset: 1, customInsights: [])), "an empty custom list is no insight")
        try expect(isProtected(makeEntry(offset: 1, speakerNames: ["Speaker 1": "Kara"])), "speaker names protect their recording")
        try expect(!isProtected(makeEntry(offset: 1, speakerNames: [:])), "an empty name map is no names")
        try expect(isProtected(makeEntry(offset: 1, source: .dictation, status: failedStatus)),
                   "a take still waiting for its transcript is protected")
    }

    private static func favoriteSurvives250Inserts() throws {
        let favorite = makeEntry(offset: 0, isFavorite: true)
        let (library, removed) = insertingDictations(250, after: 0, into: [favorite])
        try expect(library.contains(favorite), "the oldest entry survives 250 inserts when it's a favorite")
        try expect(!removed.contains(favorite), "the favorite is never handed back for deletion")
        try expect(library.count == cap + 1, "favorite plus a full cap of dictations (got \(library.count))")
        try expect(unprotectedCount(library) == cap, "the cap counts only unprotected entries")
        try expect(removed.count == 50, "exactly the overflow of dictations is pruned (got \(removed.count))")
        try expect(
            removed.map { $0.createdAt.timeIntervalSinceReferenceDate }.sorted() == (1...50).map(TimeInterval.init),
            "the pruned dictations are the 50 oldest"
        )
        try expect(isNewestFirst(library), "the library stays newest-first")
    }

    private static func conversationSurvives250Dictations() throws {
        let conversation = makeEntry(offset: 0, source: .meeting)
        let (library, removed) = insertingDictations(250, after: 0, into: [conversation])
        try expect(library.contains(conversation), "a conversation survives 250 dictations")
        try expect(!removed.contains(conversation), "the conversation is never pruned")
        try expect(library.last == conversation, "the oldest entry keeps its place at the end")
        try expect(isNewestFirst(library), "the library stays newest-first")
    }

    private static func insightAndSpeakerEntriesSurvive250Inserts() throws {
        let protected = [
            makeEntry(offset: 0.1, summary: sampleSummary),
            makeEntry(offset: 0.2, actionItems: sampleActionItems),
            makeEntry(offset: 0.3, customInsights: [sampleCustomInsight]),
            makeEntry(offset: 0.4, speakerNames: ["Speaker 1": "Kara"]),
        ]
        let (library, removed) = insertingDictations(250, after: 1, into: protected)
        for entry in protected {
            try expect(library.contains(entry), "an entry with insights or speaker names survives 250 inserts")
        }
        try expect(removed.allSatisfy { !RecordingHistoryPruner.isProtected($0) }, "only unprotected entries are pruned")
        try expect(unprotectedCount(library) == cap, "the dictations still fill exactly the cap")
        try expect(isNewestFirst(library), "the library stays newest-first")
    }

    /// A take whose transcription failed waits in History for a top-up or
    /// another model. Hundreds of dictations made meanwhile must not prune it,
    /// and once it is transcribed it is an ordinary dictation again, ranked
    /// from that moment.
    private static func failedTakeSurvives250DictationsUntilTranscribed() throws {
        let failed = makeEntry(offset: 0, transcript: "placeholder", source: .dictation, status: failedStatus)
        let (library, removed) = insertingDictations(250, after: 0, into: [failed])
        try expect(library.contains(failed), "a failed take survives 250 dictations")
        try expect(!removed.contains(failed), "the failed take is never handed back for deletion")
        try expect(unprotectedCount(library) == cap, "the dictations still fill exactly the cap")

        guard let resolved = failed.resolvingPlaceholder(transcript: "hello", modelId: "parakeet", modelName: "Parakeet") else {
            throw RecordingHistoryHarnessFailure(description: "a failed take resolves")
        }
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let stamped = RecordingHistoryPruner.stampingLostProtection(from: failed, to: resolved, at: now)
        try expect(!RecordingHistoryPruner.isProtected(stamped), "a transcribed take is an ordinary dictation")
        try expect(RecordingHistoryPruner.retainedSince(stamped) == now,
                   "and queues behind the cap from when it was transcribed, not from when it was recorded")
    }

    /// Protected entries are never evicted, even when they alone outnumber the
    /// cap; the unprotected ones interleaved with them are still capped.
    private static func protectedEntriesBeyondCapAreAllKept() throws {
        var entries: [RecordingHistoryEntry] = []
        for i in 0..<(cap + 50) {
            // Even offsets, alternating favorites and conversations.
            entries.append(i % 2 == 0
                ? makeEntry(offset: TimeInterval(i * 2), isFavorite: true)
                : makeEntry(offset: TimeInterval(i * 2), source: .meeting))
        }
        // Odd offsets, spread through the protected ones.
        let dictations = (0..<5).map { makeEntry(offset: TimeInterval($0 * 100 + 1)) }
        let outcome = RecordingHistoryPruner.prune((dictations + entries).shuffled(), maxUnprotected: 2, pinned: [])
        try expect(outcome.kept.count == cap + 50 + 2, "every protected entry kept, plus the newest 2 dictations")
        try expect(entries.allSatisfy(outcome.kept.contains), "no protected entry is removed past the cap")
        try expect(
            outcome.removed.map(\.id) == dictations.prefix(3).reversed().map(\.id),
            "the 3 oldest dictations go, newest-first"
        )
        try expect(isNewestFirst(outcome.kept), "protected and unprotected entries interleave newest-first")
    }

    /// What the store's `mutateEntry` does with each edit: stamp the moment
    /// protection is lost, and only then.
    private static func lostProtectionIsStampedOnlyWhenLost() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        func stamped(_ original: RecordingHistoryEntry, _ updated: RecordingHistoryEntry) -> Date? {
            RecordingHistoryPruner.stampingLostProtection(from: original, to: updated, at: now).unprotectedAt
        }
        let favorite = makeEntry(offset: 1, isFavorite: true)
        try expect(stamped(favorite, favorite.updatingFavorite(false)) == now, "unstarring stamps the moment")

        let summarized = makeEntry(offset: 1, summary: sampleSummary)
        try expect(stamped(summarized, summarized.updatingSummary(nil)) == now, "removing the last insight stamps it")

        let named = makeEntry(offset: 1, speakerNames: ["Speaker 1": "Kara"])
        try expect(stamped(named, named.updatingSpeakerNames(nil)) == now, "clearing speaker names stamps it")

        let starredAndSummarized = makeEntry(offset: 1, isFavorite: true, summary: sampleSummary)
        try expect(
            stamped(starredAndSummarized, starredAndSummarized.updatingFavorite(false)) == nil,
            "still protected by its summary, so nothing is lost"
        )
        let conversation = makeEntry(offset: 1, source: .meeting, isFavorite: true)
        try expect(stamped(conversation, conversation.updatingFavorite(false)) == nil, "a conversation stays protected")

        let plain = makeEntry(offset: 1)
        try expect(stamped(plain, plain.updatingFavorite(true)) == nil, "gaining protection stamps nothing")
        try expect(stamped(plain, plain.updatingFavorite(false)) == nil, "an unprotected edit stamps nothing")
    }

    private static func unprotectedAtRoundTripsAndSurvivesEdits() throws {
        let when = Date(timeIntervalSinceReferenceDate: 500)
        let entry = makeEntry(offset: 1).updatingUnprotectedAt(when)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode([RecordingHistoryEntry].self, from: encoder.encode([entry])).first
        try expect(round?.unprotectedAt == when, "unprotectedAt round-trips through Codable")

        let legacy = """
        [{"id":"\(UUID().uuidString)","createdAt":"2026-01-01T00:00:00Z","transcript":"t","audioFileName":"a.wav","durationSeconds":1,"sampleRate":16000}]
        """
        let decoded = try decoder.decode([RecordingHistoryEntry].self, from: Data(legacy.utf8)).first
        try expect(decoded?.unprotectedAt == nil, "an index written before unprotectedAt decodes as never unprotected")

        try expect(entry.updatingSummary(sampleSummary).unprotectedAt == when, "other edits carry the date through")
        try expect(entry.updatingFavorite(true).unprotectedAt == when, "starring again keeps it (unused while protected)")
    }

    /// Unstarring an old favorite must not turn the next dictation into its
    /// deletion: it queues behind the newest dictations as of the unstar and
    /// rolls off only after `cap` newer ones, like any other.
    private static func unstarredOldFavoriteSurvivesTheNextInsert() throws {
        let favorite = makeEntry(offset: 0, isFavorite: true)
        let (full, _) = insertingDictations(cap, after: 0, into: [favorite])
        let unstarredAt = Date(timeIntervalSinceReferenceDate: TimeInterval(cap) + 0.5)
        let library = full.map { entry in
            entry.id == favorite.id
                ? RecordingHistoryPruner.stampingLostProtection(from: entry, to: entry.updatingFavorite(false), at: unstarredAt)
                : entry
        }

        let (afterOne, removedByOne) = insertingDictations(1, after: TimeInterval(cap), into: library)
        try expect(afterOne.contains { $0.id == favorite.id }, "the unstarred recording survives the next insert")
        try expect(
            removedByOne.map { $0.createdAt.timeIntervalSinceReferenceDate } == [2, 1],
            "the oldest dictations go in its place"
        )
        try expect(afterOne.last?.id == favorite.id, "it keeps its place in the list, oldest at the bottom")
        try expect(isNewestFirst(afterOne), "the list stays newest-first by recording date")

        // 200 dictations newer than the unstar in all, then it goes like any other.
        let (afterMost, _) = insertingDictations(cap - 2, after: TimeInterval(cap + 1), into: afterOne)
        try expect(afterMost.contains { $0.id == favorite.id }, "still there with fewer than 200 newer dictations")
        let (afterAll, removedLast) = insertingDictations(1, after: TimeInterval(2 * cap - 1), into: afterMost)
        try expect(!afterAll.contains { $0.id == favorite.id }, "gone once 200 newer dictations have been made")
        try expect(removedLast.map(\.id) == [favorite.id], "and it is the one removed")
    }

    /// An insight or regeneration running on an old dictation pins it: the
    /// dictations landing meanwhile can't prune the row its result is for, and
    /// pinning never pushes another entry out early. Once the job ends the pin
    /// is released and the cap applies as if it had never been there.
    private static func entryWithARunningJobSurvivesInserts() throws {
        let (full, _) = insertingDictations(cap, after: 0, into: [])
        let busy = full.last!
        try expect(busy.createdAt.timeIntervalSinceReferenceDate == 1, "the oldest dictation is the one in use")

        let (during, removedDuring) = insertingDictations(5, after: TimeInterval(cap), into: full, pinned: [busy.id])
        try expect(during.contains(busy), "a pinned entry survives inserts past the cap")
        try expect(
            removedDuring.map { $0.createdAt.timeIntervalSinceReferenceDate }.sorted() == [2, 3, 4, 5],
            "the others go exactly when they would have anyway"
        )
        try expect(unprotectedCount(during) == cap + 1, "the pinned entry is the only overflow")

        // The job ends; the next insert prunes it as usual.
        let (after, removedAfter) = insertingDictations(1, after: TimeInterval(cap + 5), into: during)
        try expect(removedAfter.map(\.id).contains(busy.id), "once released, the pinned entry is pruned")
        let (neverPinned, _) = insertingDictations(6, after: TimeInterval(cap), into: full)
        try expect(
            after.map(\.createdAt) == neverPinned.map(\.createdAt),
            "and the library matches one where it was never pinned"
        )

        let zero = RecordingHistoryPruner.prune(full, maxUnprotected: 0, pinned: [busy.id])
        try expect(zero.kept == [busy], "a pinned entry is kept even with no room at all")
    }

    /// The verified defect: Clear All, a dictation landing inside the undo
    /// window, then Undo deleted the new dictation — Undo reserved room for the
    /// restored batch by pruning the visible list, which held only the new one.
    private static func undoAfterClearAllKeepsTheNewRecording() throws {
        let favorite = makeEntry(offset: 0, isFavorite: true)
        let conversation = makeEntry(offset: 0.5, source: .meeting)
        let (full, _) = insertingDictations(cap, after: 0, into: [favorite, conversation])
        try expect(unprotectedCount(full) == cap, "start at the cap")

        // Clear All: the whole library moves into the undo window.
        let pending = full
        var library: [RecordingHistoryEntry] = []

        // A dictation lands while the Undo toast is up.
        let fresh = makeEntry(offset: TimeInterval(cap + 1))
        let landed = inserting(fresh, into: library)
        try expect(landed.removed.isEmpty, "nothing to prune in an empty list")
        library = landed.kept

        // Undo.
        library = RecordingHistoryPruner.restoring(pending, into: library)
        try expect(library.contains(fresh), "Undo keeps the recording made during the window")
        try expect(library.first == fresh, "the new recording is the newest row")
        try expect(pending.allSatisfy(library.contains), "Undo brings back every cleared entry")
        try expect(library.count == pending.count + 1, "nothing is evicted by Undo")
        try expect(isNewestFirst(library), "restored entries interleave newest-first")

        // The next recording trims the overflow: oldest unprotected first,
        // never the recording made during the window, never a protected entry.
        let next = makeEntry(offset: TimeInterval(cap + 2))
        let outcome = inserting(next, into: library)
        try expect(
            outcome.removed.map { $0.createdAt.timeIntervalSinceReferenceDate } == [2, 1],
            "the next insert prunes the two oldest dictations"
        )
        for kept in [fresh, next, favorite, conversation] {
            try expect(outcome.kept.contains(kept), "new and protected recordings survive the trim")
        }
        try expect(unprotectedCount(outcome.kept) == cap, "back within the cap")
        try expect(isNewestFirst(outcome.kept), "the library stays newest-first")
    }

    /// Undo keeps its promise even for the oldest dictation at the cap, and the
    /// next insert then lands exactly where the cap would have without the
    /// deletion.
    private static func undoBringsBackEvenTheOldestEntry() throws {
        let (full, _) = insertingDictations(cap, after: 0, into: [])
        let oldest = full.last!

        // Delete the oldest; a dictation lands inside the window.
        var library = Array(full.dropLast())
        let fresh = makeEntry(offset: TimeInterval(cap + 1))
        let landed = inserting(fresh, into: library)
        try expect(landed.removed.isEmpty, "one below the cap, so nothing is pruned")
        library = RecordingHistoryPruner.restoring([oldest], into: landed.kept)
        try expect(library.contains(oldest), "Undo brings back the entry it promised")
        try expect(library.contains(fresh), "and keeps the one made during the window")

        let next = makeEntry(offset: TimeInterval(cap + 2))
        let afterUndo = inserting(next, into: library).kept
        let neverDeleted = inserting(next, into: inserting(fresh, into: full).kept).kept
        try expect(afterUndo == neverDeleted, "one insert later, the library matches a world without the deletion")
    }

    /// Review: Clear All parked a dictation's row mid-transcription; the take
    /// then filed a second row, and Undo brought the first back beside it.
    private static func clearAllSparesATakeStillTranscribing() throws {
        let transcribing = makeEntry(offset: 3, transcript: RecordingHistoryEntry.placeholderTranscript, status: failedStatus)
        let older = makeEntry(offset: 1)
        let old = makeEntry(offset: 2, isFavorite: true)
        let library = [transcribing, old, older]

        let cleared = RecordingHistoryPruner.clearingAll(library, sparing: [transcribing.id])
        try expect(cleared.kept == [transcribing], "the row being transcribed stays")
        try expect(cleared.removed == [old, older], "everything else goes to the undo window, in order")

        let everything = RecordingHistoryPruner.clearingAll(library, sparing: [])
        try expect(everything.kept.isEmpty && everything.removed == library, "with nothing in flight, all of it goes")
    }

    /// Review: a take whose row sat in the undo window filed a second row, and
    /// Undo then restored the first beside it.
    private static func aTakeReclaimsItsRowFromTheUndoWindow() throws {
        let take = makeEntry(offset: 2, transcript: RecordingHistoryEntry.placeholderTranscript, status: failedStatus)
        let other = makeEntry(offset: 1)
        let fresh = makeEntry(offset: 3)
        let parked = [take, other]

        guard let reclaimed = RecordingHistoryPruner.reclaiming(take.id, from: parked, into: [fresh]) else {
            throw RecordingHistoryHarnessFailure(description: "a parked row can be reclaimed")
        }
        try expect(reclaimed.entries == [fresh, take], "the row is visible again, newest-first")
        try expect(reclaimed.parked == [other], "the rest of the batch stays in its window")
        try expect(
            Set((reclaimed.entries + reclaimed.parked).map(\.id)) == Set((parked + [fresh]).map(\.id)),
            "visible and parked together still hold what the index lists"
        )
        let undone = RecordingHistoryPruner.restoring(reclaimed.parked, into: reclaimed.entries)
        try expect(undone.filter { $0.id == take.id }.count == 1, "Undo afterwards can't bring the take back twice")

        try expect(
            RecordingHistoryPruner.reclaiming(fresh.id, from: parked, into: [fresh]) == nil,
            "a row not in the window isn't reclaimed"
        )
        let alone = RecordingHistoryPruner.reclaiming(take.id, from: [take], into: [])
        try expect(alone?.parked.isEmpty == true, "reclaiming a lone deletion empties the window")
    }

    private static func codableRoundTrips() throws {
        let entry = makeEntry(offset: 42, transcript: "round trip \u{1F600}")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode([entry])
        let decoded = try decoder.decode([RecordingHistoryEntry].self, from: data)
        try expect(decoded == [entry], "Codable round-trips with iso8601 dates")
    }

    private static func favoriteFieldRoundTrips() throws {
        let favorited = RecordingHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 7),
            transcript: "starred",
            audioFileName: "x.wav",
            durationSeconds: 1.0,
            sampleRate: 16_000,
            modelId: nil,
            modelName: nil,
            source: .meeting,
            isFavorite: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode([RecordingHistoryEntry].self, from: encoder.encode([favorited]))
        try expect(round.first?.isFavorited == true, "isFavorite=true round-trips")

        // An index written before favorites existed must decode as not-favorited.
        let legacy = """
        [{"id":"\(UUID().uuidString)","createdAt":"2026-01-01T00:00:00Z","transcript":"t","audioFileName":"a.wav","durationSeconds":1,"sampleRate":16000}]
        """
        let decoded = try decoder.decode([RecordingHistoryEntry].self, from: Data(legacy.utf8))
        try expect(decoded.first?.isFavorited == false, "missing isFavorite decodes as not favorited")
    }

    private static func alternatesRoundTripAndDefaultEmpty() throws {
        let entry = RecordingHistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 11),
            transcript: "active",
            audioFileName: "a.wav",
            durationSeconds: 1.0,
            sampleRate: 16_000,
            modelId: "gpt4o",
            modelName: "GPT-4o",
            source: .meeting,
            alternates: [TranscriptVariant(id: UUID(), text: "older", modelId: "parakeet", modelName: "Parakeet")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let round = try decoder.decode([RecordingHistoryEntry].self, from: encoder.encode([entry])).first
        try expect(round == entry, "alternates round-trip through Codable")
        try expect(round?.transcriptVariants.count == 2, "active + one alternate = two variants")
        try expect(round?.transcriptVariants.first?.text == "active", "active variant is first")

        // A legacy index with no alternates key decodes as a single transcript.
        let legacy = """
        [{"id":"\(UUID().uuidString)","createdAt":"2026-01-01T00:00:00Z","transcript":"t","audioFileName":"a.wav","durationSeconds":1,"sampleRate":16000}]
        """
        let decoded = try decoder.decode([RecordingHistoryEntry].self, from: Data(legacy.utf8)).first
        try expect(decoded?.hasAlternateTranscripts == false, "missing alternates decodes as none")
        try expect(decoded?.transcriptVariants.count == 1, "legacy entry has exactly one transcript")
    }

    private static func regenerationKeepsPreviousTranscript() throws {
        let entry = makeEntry(offset: 5, transcript: "first")
        let altID = UUID()
        let after = TranscriptEditor.addingRegeneration(
            to: entry, transcript: "second", modelId: "gpt4o", modelName: "GPT-4o", newAlternateID: altID
        )
        try expect(after.transcript == "second", "new transcript becomes active")
        try expect(after.modelName == "GPT-4o", "active model updated")
        try expect(after.alternates?.count == 1, "previous transcript preserved as one alternate")
        try expect(after.alternates?.first?.text == "first", "alternate carries the old text")
        try expect(after.alternates?.first?.id == altID, "alternate uses the supplied id")
        try expect(after.transcriptVariants.map(\.text) == ["second", "first"], "newest (active) first")
    }

    private static func removingActivePromotesNewestAlternate() throws {
        let entry = makeEntry(offset: 5, transcript: "first")
        let mid = TranscriptEditor.addingRegeneration(
            to: entry, transcript: "second", modelId: "gpt4o", modelName: "GPT-4o", newAlternateID: UUID()
        )
        // Removing the active ("second") should promote "first" back to active.
        let after = TranscriptEditor.removing(variantID: mid.id, from: mid)
        try expect(after.transcript == "first", "newest alternate promoted to active")
        try expect(after.modelName == "Parakeet", "promoted model restored")
        try expect(after.hasAlternateTranscripts == false, "no alternates remain")
        try expect(after.id == entry.id, "entry identity (and audio) preserved")
    }

    private static func removingAlternateDropsItOnly() throws {
        let entry = makeEntry(offset: 5, transcript: "first")
        let mid = TranscriptEditor.addingRegeneration(
            to: entry, transcript: "second", modelId: "gpt4o", modelName: "GPT-4o", newAlternateID: UUID()
        )
        let altID = mid.alternates![0].id
        let after = TranscriptEditor.removing(variantID: altID, from: mid)
        try expect(after.transcript == "second", "active is untouched when an alternate is removed")
        try expect(after.hasAlternateTranscripts == false, "the one alternate is gone")
    }

    private static func removingOnlyTranscriptIsNoOp() throws {
        let entry = makeEntry(offset: 5, transcript: "only")
        let after = TranscriptEditor.removing(variantID: entry.id, from: entry)
        try expect(after == entry, "can't remove the sole transcript")

        // An unknown variant id leaves the entry unchanged too.
        let mid = TranscriptEditor.addingRegeneration(
            to: entry, transcript: "second", modelId: nil, modelName: nil, newAlternateID: UUID()
        )
        try expect(TranscriptEditor.removing(variantID: UUID(), from: mid) == mid, "unknown id is a no-op")
    }

    private static func decodesIndexMissingOptionalModelFields() throws {
        // An index written before model metadata existed must still decode.
        let json = """
        [{
          "id": "\(UUID().uuidString)",
          "createdAt": "2026-01-01T00:00:00Z",
          "transcript": "legacy",
          "audioFileName": "legacy.wav",
          "durationSeconds": 2.5,
          "sampleRate": 16000
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([RecordingHistoryEntry].self, from: Data(json.utf8))
        try expect(decoded.count == 1, "legacy entry decodes")
        try expect(decoded[0].modelId == nil && decoded[0].modelName == nil, "missing model fields decode to nil")
        try expect(decoded[0].transcript == "legacy", "other fields intact")
    }
}
