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
