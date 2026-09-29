import Foundation

struct HistoryIndexCodecHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw HistoryIndexCodecHarnessFailure(description: message)
    }
}

private func makeEntry(id: UUID = UUID(), offset: TimeInterval, source: RecordingHistoryEntry.Source? = nil) -> RecordingHistoryEntry {
    RecordingHistoryEntry(
        id: id,
        createdAt: Date(timeIntervalSinceReferenceDate: offset),
        transcript: "hello",
        audioFileName: "\(id.uuidString).wav",
        durationSeconds: 1.5,
        sampleRate: 16_000,
        modelId: "parakeet",
        modelName: "Parakeet",
        source: source,
        isFavorite: true
    )
}

/// A row as a newer build might write it: a `source` this build has no case
/// for, plus a field it has never heard of.
private let futureRow = """
{
  "id": "6B0F4C1E-7A4D-4F7E-9D55-2B1C8E3A9F10",
  "createdAt": "2026-09-01T10:00:00Z",
  "transcript": "from the future",
  "audioFileName": "future.wav",
  "durationSeconds": 12.25,
  "sampleRate": 16000,
  "source": "phoneCall",
  "isFavorite": false,
  "chapters": [{"title": "Intro", "start": 0}, {"title": "Wrap-up", "start": 9.5}],
  "note": null
}
"""

/// Parses JSON with Foundation's own parser, independent of the codec, so
/// equivalence checks don't just compare the codec against itself.
private func parsed(_ data: Data) throws -> NSObject {
    guard let object = try JSONSerialization.jsonObject(with: data) as? NSObject else {
        throw HistoryIndexCodecHarnessFailure(description: "JSONSerialization returned a non-object")
    }
    return object
}

private func encodedIndex(_ entries: [RecordingHistoryEntry]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(entries)
}

/// Splices raw JSON rows into an index array alongside encoded entries.
private func index(entries: [RecordingHistoryEntry], rawRows: [String]) throws -> Data {
    let encoded = String(decoding: try encodedIndex(entries), as: UTF8.self)
    let inner = encoded.dropFirst().dropLast()
    let parts = (inner.isEmpty ? [] : [String(inner)]) + rawRows
    return Data("[\(parts.joined(separator: ","))]".utf8)
}

@main
struct HistoryIndexCodecHarness {
    static func main() throws {
        try validIndexRoundTrips()
        try unknownSourceRowIsPassedThroughAndWrittenBack()
        try rowMissingRequiredKeyIsPassedThrough()
        try passthroughKeepsJSONTypes()
        try nonArrayOrGarbageIsUnclean()
        try referencedAudioIncludesPassthroughRows()
        try emptyArrayIsClean()
        try quarantineBlocksReaping()
        try onlyWAVsOlderThanTheIndexAreReaped()
        print("History index codec harness passed")
    }

    private static func validIndexRoundTrips() throws {
        let entries = [makeEntry(offset: 300, source: .meeting), makeEntry(offset: 200), makeEntry(offset: 100, source: .dictation)]
        let decoded = try HistoryIndexCodec.decode(encodedIndex(entries))
        try expect(decoded.entries == entries, "every valid row decodes, in order")
        try expect(decoded.passthrough.isEmpty, "a valid index has no passthrough rows")

        let written = try HistoryIndexCodec.encode(entries: decoded.entries, passthrough: decoded.passthrough)
        try expect(try HistoryIndexCodec.decode(written) == decoded, "encode → decode round-trips")
        let text = String(decoding: written, as: UTF8.self)
        try expect(text.contains("\n  "), "written index is pretty-printed")
        try expect(
            text.range(of: "\"audioFileName\"")!.lowerBound < text.range(of: "\"createdAt\"")!.lowerBound,
            "written index has sorted keys"
        )
    }

    private static func unknownSourceRowIsPassedThroughAndWrittenBack() throws {
        let entries = [makeEntry(offset: 2), makeEntry(offset: 1)]
        let decoded = try HistoryIndexCodec.decode(index(entries: entries, rawRows: [futureRow]))
        try expect(decoded.entries == entries, "the other rows still load")
        try expect(decoded.passthrough.count == 1, "the unknown-source row is kept, not dropped")
        try expect(decoded.passthrough[0].audioFileName == "future.wav", "passthrough row exposes its audio file")

        let written = try HistoryIndexCodec.encode(entries: decoded.entries, passthrough: decoded.passthrough)
        guard let rows = try parsed(written) as? [NSObject], rows.count == 3 else {
            throw HistoryIndexCodecHarnessFailure(description: "written index keeps all three rows")
        }
        try expect(rows[2] == (try parsed(Data(futureRow.utf8))), "passthrough row is written back equivalent")
        try expect(try HistoryIndexCodec.decode(written) == decoded, "a second load sees the same split")
    }

    private static func rowMissingRequiredKeyIsPassedThrough() throws {
        // No `transcript`: a required key, so the row can't be an entry.
        let partial = """
        {"id": "\(UUID().uuidString)", "createdAt": "2026-01-01T00:00:00Z", "audioFileName": "partial.wav", "durationSeconds": 1, "sampleRate": 16000}
        """
        let entry = makeEntry(offset: 5)
        let decoded = try HistoryIndexCodec.decode(index(entries: [entry], rawRows: [partial, "42"]))
        try expect(decoded.entries == [entry], "the valid row still loads")
        try expect(decoded.passthrough.count == 2, "the partial row and a stray scalar are both kept")
        try expect(decoded.passthrough[0].audioFileName == "partial.wav", "partial row's audio file is read")
        try expect(decoded.passthrough[1].audioFileName == nil, "a non-object row names no audio file")
    }

    private static func passthroughKeepsJSONTypes() throws {
        let decoded = try HistoryIndexCodec.decode(Data(#"[{"flag": true, "count": 1, "ratio": 1.5, "big": 9007199254740993}]"#.utf8))
        guard case .object(let fields)? = decoded.passthrough.first?.json else {
            throw HistoryIndexCodecHarnessFailure(description: "an unrecognized object is passed through as an object")
        }
        try expect(fields["flag"] == .bool(true), "a bool stays a bool, not the number 1")
        try expect(fields["count"] == .int(1), "an integer stays an integer")
        try expect(fields["ratio"] == .double(1.5), "a fraction stays a double")
        try expect(fields["big"] == .int(9_007_199_254_740_993), "a large integer keeps full precision")
    }

    private static func nonArrayOrGarbageIsUnclean() throws {
        let unreadable = [
            #"{"id": "not-an-array"}"#,
            "not json at all",
            "[{\"id\": ",
            "",
        ]
        for text in unreadable {
            var threw = false
            do { _ = try HistoryIndexCodec.decode(Data(text.utf8)) } catch { threw = true }
            try expect(threw, "unreadable index reports unclean: \(text.debugDescription)")
        }
    }

    private static func referencedAudioIncludesPassthroughRows() throws {
        let entry = makeEntry(offset: 1)
        let decoded = try HistoryIndexCodec.decode(index(entries: [entry], rawRows: [futureRow, "null"]))
        let referenced = HistoryIndexCodec.referencedAudio(entries: decoded.entries, passthrough: decoded.passthrough)
        try expect(referenced == [entry.audioFileName, "future.wav"], "entries' and passthrough rows' WAVs are referenced")
    }

    private static func emptyArrayIsClean() throws {
        let decoded = try HistoryIndexCodec.decode(Data("[]".utf8))
        try expect(decoded.entries.isEmpty && decoded.passthrough.isEmpty, "an empty array decodes to nothing")
        let written = try HistoryIndexCodec.encode(entries: [], passthrough: [])
        try expect(try HistoryIndexCodec.decode(written) == decoded, "an empty index round-trips")
    }

    private static func quarantineBlocksReaping() throws {
        let name = HistoryIndexCodec.quarantineFileName(at: Date(timeIntervalSince1970: 0))
        try expect(name == "index.corrupt-19700101T000000Z.json", "quarantine name is a UTC timestamp: \(name)")

        let clean = ["index.json", "a.wav"]
        try expect(HistoryIndexCodec.mayReapOrphans(loadWasClean: true, directoryFileNames: clean), "clean load reaps")
        try expect(HistoryIndexCodec.mayReapOrphans(loadWasClean: true, directoryFileNames: []), "fresh install reaps")
        try expect(!HistoryIndexCodec.mayReapOrphans(loadWasClean: false, directoryFileNames: clean), "unclean load never reaps")
        try expect(
            !HistoryIndexCodec.mayReapOrphans(loadWasClean: true, directoryFileNames: clean + [name]),
            "a quarantined index blocks reaping on later launches"
        )
    }

    private static func onlyWAVsOlderThanTheIndexAreReaped() throws {
        let index = Date(timeIntervalSinceReferenceDate: 1_000)
        let reap = HistoryIndexCodec.mayReapOrphanWAV
        try expect(reap(index.addingTimeInterval(-1), index), "a WAV older than the index is a true orphan")
        try expect(!reap(index, index), "a WAV dated the same as the index is kept")
        try expect(!reap(index.addingTimeInterval(1), index), "a WAV newer than the index (its row's write failed) is kept")
        try expect(!reap(index.addingTimeInterval(-1), nil), "with no index date nothing is reaped")
        try expect(!reap(nil, index), "a WAV with no date is kept")
    }
}
