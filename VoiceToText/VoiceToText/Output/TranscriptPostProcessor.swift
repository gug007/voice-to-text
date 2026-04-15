import Foundation

enum TranscriptPostProcessor {

    static func process(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        let collapsed = collapseWhitespace(nfc)
        let spaced = fixPunctuationSpacing(collapsed)
        let cased = capitalizeSentences(spaced)
        return cased.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let whitespaceRun = compileRegex("\\s+")
    private static let spaceBeforePunct = compileRegex("\\s+([,.!?;:])")
    private static let missingSpaceAfterPunct = compileRegex("([,.!?;:])([A-Za-z])")

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

    private static func fixPunctuationSpacing(_ s: String) -> String {
        var out = spaceBeforePunct.stringByReplacingMatches(
            in: s,
            range: NSRange(s.startIndex..., in: s),
            withTemplate: "$1"
        )
        out = missingSpaceAfterPunct.stringByReplacingMatches(
            in: out,
            range: NSRange(out.startIndex..., in: out),
            withTemplate: "$1 $2"
        )
        return out
    }

    private static func capitalizeSentences(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var chars = Array(s)

        if let first = chars.firstIndex(where: { !$0.isWhitespace }) {
            chars[first] = Character(String(chars[first]).uppercased())
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "." || c == "!" || c == "?" {
                var j = i + 1
                while j < chars.count && chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j].isLetter {
                    chars[j] = Character(String(chars[j]).uppercased())
                }
                i = j
            } else {
                i += 1
            }
        }
        return String(chars)
    }
}
