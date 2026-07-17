import Foundation

struct DiarizedTranscriptHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw DiarizedTranscriptHarnessFailure(description: message)
    }
}

private func seg(
    _ speaker: String,
    _ text: String,
    _ start: Double? = nil,
    _ end: Double? = nil
) -> DiarizedTranscript.Segment {
    DiarizedTranscript.Segment(speaker: speaker, text: text, start: start, end: end)
}

@main
struct DiarizedTranscriptHarness {
    static func main() throws {
        try labelsNormalizeInFirstAppearanceOrder()
        try consecutiveSameSpeakerSegmentsMerge()
        try singleSpeakerReturnsPlainText()
        try multiSpeakerEmitsLabeledLines()
        try knownNamePassesThrough()
        try emptyAndBlankSegmentsAreDropped()
        try canonicalizeScopesRawLabelsPerChunk()
        try canonicalizeSameLabelWithinChunkStaysOneSpeaker()
        try textFallbackChunksMergeAcrossChunkIndices()
        try referenceClipPicksLongestClampedToTenSeconds()
        try referenceClipSkipsShortAndKeepsPrevious()
        try referenceClipLimitsToFourSpeakers()
        try parseDecodesSegments()
        try parseFallsBackToTopLevelText()
        try parseThrowsOnGarbageAndEmpty()
        print("Diarized transcript harness passed")
    }

    private static func labelsNormalizeInFirstAppearanceOrder() throws {
        // "B" appears first, so it becomes Speaker 1.
        let out = DiarizedTranscript.format(segments: [seg("B", "first"), seg("A", "second")])
        try expect(out == "Speaker 1: first\nSpeaker 2: second", "first-seen raw label becomes Speaker 1")
    }

    private static func consecutiveSameSpeakerSegmentsMerge() throws {
        let out = DiarizedTranscript.format(segments: [
            seg("A", "one"), seg("A", "two"), seg("B", "three"), seg("A", "four"),
        ])
        try expect(
            out == "Speaker 1: one two\nSpeaker 2: three\nSpeaker 1: four",
            "consecutive same-speaker segments merge; a later turn opens a new block"
        )
    }

    private static func singleSpeakerReturnsPlainText() throws {
        let out = DiarizedTranscript.format(segments: [seg("A", "hello"), seg("A", "world")])
        try expect(out == "hello world", "one distinct speaker → plain text with no labels")
    }

    private static func multiSpeakerEmitsLabeledLines() throws {
        let out = DiarizedTranscript.format(segments: [
            seg("speaker_0", "hi there"), seg("speaker_1", "hello"),
        ])
        try expect(out == "Speaker 1: hi there\nSpeaker 2: hello", "multi-speaker → labeled lines joined by newline")
    }

    private static func knownNamePassesThrough() throws {
        // A raw label that is itself a canonical name we pinned maps to itself,
        // not a fresh number — so a pinned speaker merges with its earlier turn.
        let out = DiarizedTranscript.format(segments: [
            seg("A", "hello"), seg("B", "hi"), seg("Speaker 1", "bye"),
        ])
        try expect(
            out == "Speaker 1: hello\nSpeaker 2: hi\nSpeaker 1: bye",
            "pinned canonical label maps to itself"
        )
    }

    private static func emptyAndBlankSegmentsAreDropped() throws {
        let out = DiarizedTranscript.format(segments: [
            seg("A", "kept"), seg("B", "   "), seg("B", ""), seg("A", "again"),
        ])
        // B contributes nothing, so only one distinct speaker remains → plain text.
        try expect(out == "kept again", "blank/empty segments are dropped before counting speakers")
    }

    private static func canonicalizeScopesRawLabelsPerChunk() throws {
        var map = DiarizedTranscript.SpeakerLabelMap()
        let c0 = DiarizedTranscript.canonicalize(
            segments: [seg("A", "hi"), seg("B", "yo")], chunk: 0, labelMap: &map
        )
        try expect(c0.map(\.speaker) == ["Speaker 1", "Speaker 2"], "chunk 0 raw A/B → Speaker 1/2")

        // Chunk 1 comes back with the pinned canonical names plus a genuinely
        // new speaker whose raw label recycles "A" (the API restarts letters
        // per response). That "A" must NOT collapse into chunk 0's Speaker 1.
        let c1 = DiarizedTranscript.canonicalize(
            segments: [seg("Speaker 1", "again"), seg("Speaker 2", "me too"), seg("A", "new person")],
            chunk: 1, labelMap: &map
        )
        try expect(
            c1.map(\.speaker) == ["Speaker 1", "Speaker 2", "Speaker 3"],
            "pinned names self-map; a recycled raw label in a new chunk is a new speaker"
        )

        // format on already-canonical segments must reproduce the same numbering.
        let out = DiarizedTranscript.format(segments: c0 + c1)
        try expect(
            out == "Speaker 1: hi\nSpeaker 2: yo\nSpeaker 1: again\nSpeaker 2: me too\nSpeaker 3: new person",
            "format is numbering-stable across chunks; three distinct speakers"
        )
    }

    private static func canonicalizeSameLabelWithinChunkStaysOneSpeaker() throws {
        var map = DiarizedTranscript.SpeakerLabelMap()
        let c = DiarizedTranscript.canonicalize(
            segments: [seg("A", "one"), seg("B", "two"), seg("A", "three")],
            chunk: 0, labelMap: &map
        )
        try expect(
            c.map(\.speaker) == ["Speaker 1", "Speaker 2", "Speaker 1"],
            "the same raw label repeated within one chunk maps to one speaker"
        )
    }

    private static func textFallbackChunksMergeAcrossChunkIndices() throws {
        var map = DiarizedTranscript.SpeakerLabelMap()
        let c0 = DiarizedTranscript.canonicalize(
            segments: [seg(DiarizedTranscript.textFallbackSpeaker, "first half")],
            chunk: 0, labelMap: &map
        )
        let c1 = DiarizedTranscript.canonicalize(
            segments: [seg(DiarizedTranscript.textFallbackSpeaker, "second half")],
            chunk: 1, labelMap: &map
        )
        let out = DiarizedTranscript.format(segments: c0 + c1)
        try expect(out == "first half second half", "text-only fallback chunks merge into one unlabeled block")
    }

    private static func referenceClipPicksLongestClampedToTenSeconds() throws {
        let sr = 10
        let samples = [Float](repeating: 0.5, count: 200) // 20 s at 10 Hz
        var map = DiarizedTranscript.SpeakerLabelMap()
        let segments = [
            seg("A", "short", 0, 5),   // 5 s
            seg("B", "mid", 5, 8),     // 3 s
            seg("A", "long", 8, 20),   // 12 s → longest for A, clamps to 10 s
        ]
        let refs = DiarizedTranscript.referenceClips(
            fromChunk: samples, segments: segments, sampleRate: sr, labelMap: &map, previous: [:]
        )
        try expect(refs["Speaker 1"]?.count == 100, "A's clip is the longest segment clamped to 10 s (100 samples)")
        try expect(refs["Speaker 2"]?.count == 30, "B's 3 s clip is 30 samples")
        try expect(map.order == ["Speaker 1", "Speaker 2"], "label map advanced in appearance order")
    }

    private static func referenceClipSkipsShortAndKeepsPrevious() throws {
        let sr = 10
        let samples = [Float](repeating: 0.1, count: 100)
        var map = DiarizedTranscript.SpeakerLabelMap()
        let previous: [String: [Float]] = ["Speaker 1": [1, 2, 3]]
        // A's only segment is 1 s (< 2 s) → skipped, previous clip kept.
        let refs = DiarizedTranscript.referenceClips(
            fromChunk: samples, segments: [seg("A", "brief", 0, 1)],
            sampleRate: sr, labelMap: &map, previous: previous
        )
        try expect(refs["Speaker 1"] == [1, 2, 3], "sub-2 s segment keeps the previously captured reference")
    }

    private static func referenceClipLimitsToFourSpeakers() throws {
        let sr = 10
        let samples = [Float](repeating: 0.2, count: 300)
        var map = DiarizedTranscript.SpeakerLabelMap()
        let segments = [
            seg("A", "a", 0, 3), seg("B", "b", 3, 6), seg("C", "c", 6, 9),
            seg("D", "d", 9, 12), seg("E", "e", 12, 15),
        ]
        let refs = DiarizedTranscript.referenceClips(
            fromChunk: samples, segments: segments, sampleRate: sr, labelMap: &map, previous: [:]
        )
        try expect(refs.count == 4, "at most four speakers get reference clips")
        try expect(refs["Speaker 5"] == nil, "the fifth speaker is excluded")
        try expect(refs["Speaker 4"] != nil, "the fourth speaker is included")
    }

    private static func parseDecodesSegments() throws {
        let json = """
        {"segments":[{"speaker":"A","text":"hi","start":0,"end":1.5},{"speaker":"B","text":"yo"}]}
        """
        let segments = try DiarizedTranscript.parse(Data(json.utf8))
        try expect(segments.count == 2, "both segments decode")
        try expect(segments[0] == seg("A", "hi", 0, 1.5), "first segment fields decode")
        try expect(segments[1].speaker == "B" && segments[1].start == nil, "missing times decode as nil")
    }

    private static func parseFallsBackToTopLevelText() throws {
        // segments absent → fall back to top-level text as one unlabeled block.
        let missing = try DiarizedTranscript.parse(Data(#"{"text":"hello world"}"#.utf8))
        try expect(DiarizedTranscript.format(segments: missing) == "hello world", "text-only fallback formats to plain text")

        // segments present but empty → same fallback.
        let empty = try DiarizedTranscript.parse(Data(#"{"segments":[],"text":"just this"}"#.utf8))
        try expect(DiarizedTranscript.format(segments: empty) == "just this", "empty segments fall back to text")
    }

    private static func parseThrowsOnGarbageAndEmpty() throws {
        try expectThrows(Data("not json at all".utf8), "non-JSON payload throws")
        try expectThrows(Data(#"{"foo":1}"#.utf8), "payload with neither segments nor text throws")
    }

    private static func expectThrows(_ data: Data, _ message: String) throws {
        do {
            _ = try DiarizedTranscript.parse(data)
            throw DiarizedTranscriptHarnessFailure(description: "expected throw: \(message)")
        } catch is DiarizedTranscriptHarnessFailure {
            throw DiarizedTranscriptHarnessFailure(description: "expected throw: \(message)")
        } catch {
            // Any other error is the expected parse failure.
        }
    }
}
