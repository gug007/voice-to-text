import Foundation

/// Light cleanup applied to every engine's output before it is pasted or saved.
/// Engines already punctuate, space and case their text, so every rule here is
/// deliberately conservative: it only touches spacing and casing it can be sure
/// is wrong, and leaves anything that looks like a URL, file name, product name
/// or abbreviation exactly as the engine wrote it. Pure and Foundation-only so
/// `Tests/TranscriptPostProcessorHarness.swift` can compile it standalone.
nonisolated enum TranscriptPostProcessor {

    /// `capitalizeFirst: false` is for text that continues an earlier piece —
    /// a later chunk of a long recording usually starts mid-sentence, so its
    /// first word must keep the engine's casing.
    static func process(_ text: String, capitalizeFirst: Bool = true) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        let collapsed = collapseWhitespace(nfc)
        let spaced = fixPunctuationSpacing(collapsed)
        let cased = capitalizeSentences(spaced, capitalizeFirst: capitalizeFirst)
        return cased.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `process`, but preserves line structure: each `\n`-separated line is
    /// processed independently and empty results are dropped. Used for diarized
    /// transcripts where each `Speaker N: …` turn is its own line. Identity-
    /// equivalent to `process` for single-line input. `capitalizeFirst` applies
    /// to the first non-empty line only; every later line is a new turn.
    static func processPreservingLines(_ text: String, capitalizeFirst: Bool = true) -> String {
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let processed = process(String(line), capitalizeFirst: capitalizeFirst || !lines.isEmpty)
            if !processed.isEmpty { lines.append(processed) }
        }
        return lines.joined(separator: "\n")
    }

    private static let whitespaceRun = compileRegex("\\s+")
    /// Only `,` and `.` followed by a space, a closing quote or bracket, or the
    /// end: a dot glued to the next word is a token of its own (".zshrc",
    /// ".NET", ".5", "..."), and a space before `! ? ; :` is correct French
    /// typography ("Ça va ?").
    private static let spaceBeforePunct = compileRegex("\\s+([,.])(?=[\\s\"')\\]}”’»]|$)")
    /// Dotted initialisms ("e.g.", "a.m.", "U.S.", "Ph.D."). At least two
    /// dotted parts, so a sentence ending in a lone letter ("plan A.") still
    /// ends the sentence.
    private static let dottedInitialism = compileRegex("^(?:\\p{L}{1,2}\\.){2,}$")

    /// Abbreviations whose trailing period rarely ends a sentence. Kept short on
    /// purpose: each entry suppresses a real sentence break when it does.
    private static let abbreviations: Set<String> = [
        "etc", "vs", "mr", "mrs", "ms", "dr", "st", "jr", "sr", "approx", "incl",
        "inc", "ltd", "co", "corp",
    ]

    private static let sentenceTerminators: Set<Character> = [".", "!", "?"]
    /// Closing quotes and brackets after a terminator (`"done."`, `(really?)`)
    /// don't stop it ending the sentence.
    private static let trailingClosers: Set<Character> = ["\"", "'", ")", "]", "}", "”", "’", "»"]
    /// Everything that may trail a word without being part of it, so `word,`
    /// and `word."` are judged as `word`.
    private static let trailingMarks = trailingClosers.union([",", ".", "!", "?", ";", ":"])
    /// Characters that mark a token as a URL, email, path, query or identifier
    /// rather than a word — its casing is meaningful and must not change.
    private static let nonWordCharacters: Set<Character> = [".", "@", "/", "\\", "?", "=", "&", "#", "_"]

    private static func compileRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid regex pattern \"\(pattern)\": \(error)")
        }
    }

    private static func collapseWhitespace(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return whitespaceRun.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
    }

    /// There is intentionally no "missing space after punctuation" rule: every
    /// engine and chunk joiner already separates pieces with a space, so a mark
    /// glued to a letter is real text ("example.com", "Node.js", "e.g.").
    private static func fixPunctuationSpacing(_ s: String) -> String {
        spaceBeforePunct.stringByReplacingMatches(
            in: s,
            range: NSRange(s.startIndex..., in: s),
            withTemplate: "$1"
        )
    }

    /// Works token by token (whitespace is already collapsed to single spaces),
    /// so a terminator only ends a sentence when a space follows it.
    private static func capitalizeSentences(_ s: String, capitalizeFirst: Bool) -> String {
        var capitalizeNext = capitalizeFirst
        let tokens = s.split(separator: " ", omittingEmptySubsequences: false).map { token -> Substring in
            guard !token.isEmpty else { return token }
            let cased = capitalizeNext ? capitalizingIfWord(token) : token
            capitalizeNext = endsSentence(token)
            return cased
        }
        return tokens.joined(separator: " ")
    }

    /// A trailing `.` after an abbreviation or initialism ("e.g.", "p.m.",
    /// "Dr.") is part of the word, not the end of the sentence; neither is an
    /// ellipsis, which engines use for a pause mid-thought ("so... maybe").
    private static func endsSentence(_ token: Substring) -> Bool {
        let trimmed = trimmingSuffix(token, trailingClosers)
        guard let last = trimmed.last, sentenceTerminators.contains(last) else { return false }
        guard last == "." else { return true }
        if trimmed.hasSuffix("..") { return false }
        let word = String(trimmed.drop(while: { !$0.isLetter }))
        let range = NSRange(word.startIndex..., in: word)
        if dottedInitialism.firstMatch(in: word, range: range) != nil { return false }
        return !abbreviations.contains(word.dropLast().lowercased())
    }

    /// Uppercases the first letter of an ordinary lowercase word. Anything else —
    /// a leading symbol, internal capitals (iPhone, macOS, eBay), digits, or
    /// URL/path/dotted punctuation — is left exactly as transcribed.
    private static func capitalizingIfWord(_ token: Substring) -> Substring {
        guard let first = token.first, first.isLetter, first.isLowercase else { return token }
        let core = trimmingSuffix(token, trailingMarks)
        let rest = core.dropFirst()
        if rest.contains(where: { $0.isUppercase || $0.isNumber || nonWordCharacters.contains($0) }) {
            return token
        }
        return Substring(first.uppercased()) + token.dropFirst()
    }

    private static func trimmingSuffix(_ token: Substring, _ characters: Set<Character>) -> Substring {
        var end = token.endIndex
        while end > token.startIndex, characters.contains(token[token.index(before: end)]) {
            end = token.index(before: end)
        }
        return token[token.startIndex..<end]
    }
}
