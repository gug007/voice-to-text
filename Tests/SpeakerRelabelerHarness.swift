import Foundation

struct SpeakerRelabelerHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SpeakerRelabelerHarnessFailure(description: message)
    }
}

@main
struct SpeakerRelabelerHarness {
    static func main() throws {
        try labelsExtractedInOrderAndDeduped()
        try midSentenceMentionIsNotALabel()
        try unlabeledTranscriptHasNoLabels()
        try renameSingleLabel()
        try sameNameMergesAdjacentTurns()
        try unmappedLabelsUntouched()
        try emptyAndWhitespaceNamesIgnored()
        try unlabeledTranscriptReturnedIdentical()
        print("Speaker relabeler harness passed")
    }

    private static func labelsExtractedInOrderAndDeduped() throws {
        let transcript = "Speaker 2: hi\nSpeaker 1: hello\nSpeaker 2: again"
        let labels = SpeakerRelabeler.speakerLabels(in: transcript)
        try expect(labels == ["Speaker 2", "Speaker 1"], "labels are first-appearance order, deduped")
    }

    private static func midSentenceMentionIsNotALabel() throws {
        // "Speaker 2" only appears inside the text, never as a line prefix.
        let transcript = "Speaker 1: I think Speaker 2 already left the room"
        let labels = SpeakerRelabeler.speakerLabels(in: transcript)
        try expect(labels == ["Speaker 1"], "a mid-sentence 'Speaker 2' is not counted as a label")
    }

    private static func unlabeledTranscriptHasNoLabels() throws {
        let labels = SpeakerRelabeler.speakerLabels(in: "just some plain dictation text")
        try expect(labels == [], "an unlabeled transcript yields no labels")
    }

    private static func renameSingleLabel() throws {
        let transcript = "Speaker 1: hello\nSpeaker 2: hi there"
        let out = SpeakerRelabeler.apply(names: ["Speaker 1": "Kara"], to: transcript)
        try expect(out == "Kara: hello\nSpeaker 2: hi there", "mapped label renamed; unmapped label kept")
    }

    private static func sameNameMergesAdjacentTurns() throws {
        // Two labels mapped to one name make adjacent turns merge with a space.
        let transcript = "Speaker 1: hello\nSpeaker 2: there\nSpeaker 1: bye"
        let out = SpeakerRelabeler.apply(
            names: ["Speaker 1": "Kara", "Speaker 2": "Kara"], to: transcript
        )
        try expect(out == "Kara: hello there bye", "same name merges every adjacent turn into one line")
    }

    private static func unmappedLabelsUntouched() throws {
        let transcript = "Speaker 1: a\nSpeaker 2: b\nSpeaker 3: c"
        let out = SpeakerRelabeler.apply(names: ["Speaker 2": "Bo"], to: transcript)
        try expect(
            out == "Speaker 1: a\nBo: b\nSpeaker 3: c",
            "only the mapped label changes; neighbors keep canonical labels and stay separate"
        )
    }

    private static func emptyAndWhitespaceNamesIgnored() throws {
        let transcript = "Speaker 1: a\nSpeaker 2: b"
        // Empty map returns input unchanged.
        try expect(
            SpeakerRelabeler.apply(names: [:], to: transcript) == transcript,
            "empty map returns the input unchanged"
        )
        // Whitespace-only names are treated as absent → nothing renamed.
        try expect(
            SpeakerRelabeler.apply(names: ["Speaker 1": "   "], to: transcript) == transcript,
            "whitespace-only name is treated as absent"
        )
        // A real name is trimmed.
        try expect(
            SpeakerRelabeler.apply(names: ["Speaker 1": "  Kara  "], to: transcript)
                == "Kara: a\nSpeaker 2: b",
            "mapped names are trimmed"
        )
    }

    private static func unlabeledTranscriptReturnedIdentical() throws {
        let transcript = "just some plain dictation text"
        let out = SpeakerRelabeler.apply(names: ["Speaker 1": "Kara"], to: transcript)
        try expect(out == transcript, "an unlabeled transcript is returned identical")
    }
}
