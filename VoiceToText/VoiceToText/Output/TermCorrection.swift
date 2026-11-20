import Foundation

/// A fix made to every transcript: wherever the engine writes `heard`,
/// `replacement` goes in its place. Most are learned from what the user types
/// over on the review card (`TermCorrectionLearner`); the rest are typed into
/// Settings → Corrections.
nonisolated struct TermCorrection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// What the engine writes: one or more words, matched whole and whatever
    /// their case.
    var heard: String
    /// What it should have written, used exactly as spelled here.
    var replacement: String
    /// Picked up from an edit on the review card rather than typed into Settings.
    var isLearned: Bool

    init(id: UUID = UUID(), heard: String, replacement: String, isLearned: Bool = false) {
        self.id = id
        self.heard = TermCorrections.normalized(heard)
        self.replacement = TermCorrections.normalized(replacement)
        self.isLearned = isLearned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            heard: try container.decode(String.self, forKey: .heard),
            replacement: try container.decode(String.self, forKey: .replacement),
            isLearned: try container.decodeIfPresent(Bool.self, forKey: .isLearned) ?? false
        )
    }

    /// Neither side is empty and the two differ, so applying it does something.
    var isUsable: Bool {
        !heard.isEmpty && !replacement.isEmpty && heard != replacement
    }
}

/// Applies corrections to a transcript. Pure and Foundation-only so
/// `Tests/TermCorrectionHarness.swift` can compile it standalone.
nonisolated enum TermCorrections {

    /// `text` with every correction made. A phrase matches only as whole
    /// words — "cloud code" is left alone inside "icloud codes", "don" inside
    /// "don't" — in any case, and across whatever whitespace separates its
    /// words. Every phrase is looked for in `text` as it came in, so what one
    /// correction writes is never corrected again; where two matches
    /// overlap, the longer phrase wins, so "клод код" wins over "клод".
    static func apply(_ corrections: [TermCorrection], to text: String) -> String {
        var prepared = Prepared(corrections)
        return prepared.apply(to: text)
    }

    /// `list` with `correction` in it. A phrase has one correction: a second
    /// for the same words replaces the first.
    static func placing(_ correction: TermCorrection, in list: [TermCorrection]) -> [TermCorrection] {
        var updated = list
        let heardKey = key(correction.heard)
        updated.removeAll { $0.id != correction.id && key($0.heard) == heardKey }
        if let index = updated.firstIndex(where: { $0.id == correction.id }) {
            updated[index] = correction
        } else {
            updated.append(correction)
        }
        return updated
    }

    /// Corrections ready to make in one text after another: put in order
    /// once, each matcher built the first time its phrase turns up.
    struct Prepared {
        private struct Rule {
            let words: [Substring]
            /// The phrase's length, which decides between overlapping matches.
            let length: Int
            /// The phrase's first word, lowercased, as bytes.
            let needle: [UInt8]
            let replacement: String
            var matcher: NSRegularExpression?
            var isBuilt = false
        }

        private var rules: [Rule]

        init(_ corrections: [TermCorrection]) {
            rules = corrections
                .map { (correction: $0, length: $0.heard.count) }
                .sorted { $0.length > $1.length }
                .compactMap { entry in
                    guard entry.correction.isUsable else { return nil }
                    let words = entry.correction.heard.split(whereSeparator: \.isWhitespace)
                    guard let first = words.first else { return nil }
                    return Rule(
                        words: words,
                        length: entry.length,
                        needle: Array(first.lowercased().utf8),
                        replacement: entry.correction.replacement
                    )
                }
        }

        mutating func apply(to text: String) -> String {
            guard !rules.isEmpty, !text.isEmpty else { return text }
            let folded = text.lowercased()
            let whole = NSRange(text.startIndex..., in: text)
            var found: [(range: NSRange, rule: Int)] = []
            for index in rules.indices {
                // Most corrections match nothing in most transcripts; this
                // spares them the regex.
                guard Self.mentions(folded, rules[index].needle) else { continue }
                if !rules[index].isBuilt {
                    rules[index].matcher = TermCorrections.matcher(for: rules[index].words)
                    rules[index].isBuilt = true
                }
                guard let regex = rules[index].matcher else { continue }
                found += regex.matches(in: text, range: whole).map { ($0.range, index) }
            }
            guard !found.isEmpty else { return text }
            // Where matches overlap, the longer phrase wins, then the earlier.
            found.sort {
                rules[$0.rule].length != rules[$1.rule].length
                    ? rules[$0.rule].length > rules[$1.rule].length
                    : $0.range.location < $1.range.location
            }
            var kept: [(range: NSRange, rule: Int)] = []
            for match in found {
                let at = Self.insertionPoint(of: match.range, in: kept)
                let clearsBefore = at == 0 || NSMaxRange(kept[at - 1].range) <= match.range.location
                let clearsAfter = at == kept.count || NSMaxRange(match.range) <= kept[at].range.location
                guard clearsBefore, clearsAfter else { continue }
                kept.insert(match, at: at)
            }
            var result = ""
            var rest = text.startIndex
            for (range, rule) in kept {
                guard let match = Range(range, in: text) else { continue }
                result += text[rest..<match.lowerBound]
                result += rules[rule].replacement
                rest = match.upperBound
            }
            result += text[rest...]
            return result
        }

        /// Where a match starting at `range` goes in `kept`, which is in
        /// text order and has no overlaps.
        private static func insertionPoint(of range: NSRange, in kept: [(range: NSRange, rule: Int)]) -> Int {
            var low = 0
            var high = kept.count
            while low < high {
                let middle = (low + high) / 2
                if kept[middle].range.location < range.location {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low
        }

        /// Whether `needle`'s bytes are somewhere in `folded`. Says yes when
        /// it cannot look, which leaves the answer to the regex.
        private static func mentions(_ folded: String, _ needle: [UInt8]) -> Bool {
            folded.utf8.withContiguousStorageIfAvailable { text in
                needle.withUnsafeBufferPointer {
                    memmem(text.baseAddress, text.count, $0.baseAddress, $0.count) != nil
                }
            } ?? true
        }
    }

    /// A phrase as it is stored: NFC, trimmed, single-spaced.
    static func normalized(_ phrase: String) -> String {
        phrase.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// What two phrases are compared by: the same words in any case are the
    /// same phrase.
    static func key(_ phrase: String) -> String {
        normalized(phrase).lowercased()
    }

    /// Letters, combining marks, digits and underscores on either side mean
    /// the match is part of a longer word. So does an apostrophe and a letter
    /// after it — "don" in "don't" — except a possessive "'s" ending the
    /// word. Before it an apostrophe is an elision, "l'" or "d'", and the
    /// word that follows is whole.
    private static let wordEdgeBefore = "(?<![\\p{L}\\p{M}\\p{N}_])"
    private static let wordEdgeAfter = "(?![\\p{L}\\p{M}\\p{N}_])(?!['’](?!s(?![\\p{L}\\p{M}\\p{N}_]))\\p{L})"

    fileprivate static func matcher(for words: [Substring]) -> NSRegularExpression? {
        let phrase = words
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "\\s+")
        return try? NSRegularExpression(
            pattern: wordEdgeBefore + phrase + wordEdgeAfter,
            options: [.caseInsensitive]
        )
    }
}
