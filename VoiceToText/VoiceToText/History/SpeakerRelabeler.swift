import Foundation

/// Pure display-relabeling for a diarized transcript. Foundation-only and
/// `nonisolated` so it can be unit-tested standalone (see
/// `Tests/SpeakerRelabelerHarness`) and used from any actor.
///
/// A diarized transcript is a sequence of newline-separated turns, each a
/// `Speaker N: text…` line (single-speaker transcripts carry no labels at all —
/// see `DiarizedTranscript.format`). Names are never baked into that stored
/// string; instead a `["Speaker 1": "Kara"]` mapping is applied on the way to
/// the screen. Because two labels can map to the same name, applying the map
/// also merges adjacent turns that end up sharing a display name — that merge is
/// the entire "give two speakers one name" UX.
nonisolated enum SpeakerRelabeler {
    /// The distinct canonical labels ("Speaker 1", "Speaker 2", …) that appear as
    /// line prefixes, in first-appearance order. A "Speaker 2" mentioned inside a
    /// sentence is not a prefix and is ignored; an unlabeled transcript yields [].
    static func speakerLabels(in transcript: String) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for line in transcript.components(separatedBy: "\n") {
            if let parsed = parsePrefixedLine(line), !seen.contains(parsed.label) {
                seen.insert(parsed.label)
                ordered.append(parsed.label)
            }
        }
        return ordered
    }

    /// Renders `transcript` for display with the given canonical-label → name
    /// map applied. Each line that starts with a canonical `Speaker N: ` prefix
    /// whose label has a non-empty mapped name gets that prefix swapped for
    /// `<Name>: `; unmapped labels and non-prefixed lines are left as-is.
    /// Adjacent lines that end up carrying the same display label are then merged
    /// into one line joined by a single space (mirroring `DiarizedTranscript`).
    /// Returns the input unchanged when the map is empty or nothing it names is
    /// present. Names are trimmed; whitespace-only names are treated as absent.
    static func apply(names: [String: String], to transcript: String) -> String {
        var effective: [String: String] = [:]
        for (label, name) in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { effective[label] = trimmed }
        }
        guard !effective.isEmpty else { return transcript }

        enum Block {
            case labeled(display: String, text: String)
            case raw(String)
        }

        var blocks: [Block] = []
        var didRename = false
        for line in transcript.components(separatedBy: "\n") {
            guard let parsed = parsePrefixedLine(line) else {
                blocks.append(.raw(line))
                continue
            }
            let display = effective[parsed.label] ?? parsed.label
            if display != parsed.label { didRename = true }
            if case .labeled(let prevDisplay, let prevText)? = blocks.last, prevDisplay == display {
                blocks[blocks.count - 1] = .labeled(display: display, text: prevText + " " + parsed.text)
            } else {
                blocks.append(.labeled(display: display, text: parsed.text))
            }
        }

        // Nothing named a present label: reconstruction would equal the input, so
        // return it verbatim rather than risk perturbing whitespace.
        guard didRename else { return transcript }

        return blocks.map { block in
            switch block {
            case .labeled(let display, let text): return "\(display): \(text)"
            case .raw(let line): return line
            }
        }.joined(separator: "\n")
    }

    /// Splits a line into its canonical label and the text after the `Speaker N: `
    /// prefix, or nil when the line doesn't start with that exact shape. The label
    /// must be at the very start (`Speaker`, a space, one or more ASCII digits,
    /// then `": "`) so a mid-sentence mention never counts.
    private static func parsePrefixedLine(_ line: String) -> (label: String, text: String)? {
        let speakerPrefix = "Speaker "
        guard line.hasPrefix(speakerPrefix) else { return nil }
        var index = line.index(line.startIndex, offsetBy: speakerPrefix.count)
        let digitsStart = index
        while index < line.endIndex, ("0"..."9").contains(line[index]) {
            index = line.index(after: index)
        }
        guard index > digitsStart else { return nil }
        let rest = line[index...]
        guard rest.hasPrefix(": ") else { return nil }
        let label = speakerPrefix + line[digitsStart..<index]
        return (label, String(rest.dropFirst(2)))
    }
}
