import Foundation

struct RecordingHistoryHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RecordingHistoryHarnessFailure(description: message)
    }
}

private func makeEntry(id: UUID = UUID(), offset: TimeInterval, transcript: String = "hello") -> RecordingHistoryEntry {
    RecordingHistoryEntry(
        id: id,
        createdAt: Date(timeIntervalSinceReferenceDate: offset),
        transcript: transcript,
        audioFileName: "\(id.uuidString).wav",
        durationSeconds: 1.0,
        sampleRate: 16_000,
        modelId: "parakeet",
        modelName: "Parakeet"
    )
}

@main
struct RecordingHistoryHarness {
    static func main() throws {
        try pruneKeepsNewestAndRemovesOverflow()
        try pruneSortsRegardlessOfInputOrder()
        try pruneWithNonPositiveMaxRemovesEverything()
        try pruneUnderCapKeepsAll()
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
        let outcome = RecordingHistoryPruner.prune(entries, maxCount: 2)
        try expect(outcome.kept.count == 2, "keeps maxCount entries")
        try expect(outcome.kept[0].createdAt.timeIntervalSinceReferenceDate == 300, "newest first")
        try expect(outcome.kept[1].createdAt.timeIntervalSinceReferenceDate == 200, "second newest second")
        try expect(outcome.removed.count == 1, "removes the overflow")
        try expect(outcome.removed[0].createdAt.timeIntervalSinceReferenceDate == 100, "oldest is removed")
    }

    private static func pruneSortsRegardlessOfInputOrder() throws {
        let ascending = [makeEntry(offset: 1), makeEntry(offset: 2), makeEntry(offset: 3)]
        let outcome = RecordingHistoryPruner.prune(ascending, maxCount: 10)
        let times = outcome.kept.map { $0.createdAt.timeIntervalSinceReferenceDate }
        try expect(times == [3, 2, 1], "unsorted input is normalized to newest-first")
    }

    private static func pruneWithNonPositiveMaxRemovesEverything() throws {
        let entries = [makeEntry(offset: 1), makeEntry(offset: 2)]
        let zero = RecordingHistoryPruner.prune(entries, maxCount: 0)
        try expect(zero.kept.isEmpty, "maxCount 0 keeps nothing")
        try expect(zero.removed.count == 2, "maxCount 0 removes all")
        let negative = RecordingHistoryPruner.prune(entries, maxCount: -5)
        try expect(negative.kept.isEmpty && negative.removed.count == 2, "negative maxCount removes all")
    }

    private static func pruneUnderCapKeepsAll() throws {
        let entries = [makeEntry(offset: 1), makeEntry(offset: 2)]
        let outcome = RecordingHistoryPruner.prune(entries, maxCount: 5)
        try expect(outcome.kept.count == 2 && outcome.removed.isEmpty, "below cap keeps everything")
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
