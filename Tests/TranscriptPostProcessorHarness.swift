import Foundation

struct TranscriptPostProcessorHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TranscriptPostProcessorHarnessFailure(description: message)
    }
}

private func expectProcessed(_ input: String, _ expected: String, _ label: String) throws {
    let actual = TranscriptPostProcessor.process(input)
    try expect(actual == expected, "\(label): \"\(input)\" → \"\(actual)\", expected \"\(expected)\"")
}

@main
struct TranscriptPostProcessorHarness {
    static func main() throws {
        try ordinaryProseStillFixed()
        try gluedPunctuationPreserved()
        try leadingDotTokensPreserved()
        try frenchSpacingPreserved()
        try abbreviationsDoNotEndSentences()
        try firstWordCasingRespectsTokenShape()
        try linesProcessedIndependently()
        try capitalizeFirstFalseKeepsOpeningCase()
        print("Transcript post-processor harness passed")
    }

    private static func ordinaryProseStillFixed() throws {
        try expectProcessed("hello world. how are you", "Hello world. How are you", "sentence case")
        try expectProcessed("hello , world", "Hello, world", "space before comma")
        try expectProcessed("  lots   of   space ", "Lots of space", "whitespace collapse + trim")
        try expectProcessed("that's it .", "That's it.", "space before final period")
        try expectProcessed("really? yes! ok", "Really? Yes! Ok", "? and ! end sentences")
        try expectProcessed("he said \"stop.\" then left", "He said \"stop.\" Then left", "terminator inside quotes")
        try expectProcessed("he said \"stop .\" then", "He said \"stop.\" Then", "space before period inside quotes")
        try expectProcessed("(see above , below .) ok", "(see above, below.) Ok", "space before mark inside brackets")
        try expectProcessed("plan A. then B", "Plan A. Then B", "lone letter still ends a sentence")
        try expectProcessed("tabs\tand\nnewlines", "Tabs and newlines", "any whitespace collapses")
        try expectProcessed("", "", "empty input")
        try expectProcessed("   ", "", "whitespace-only input")
        // NFC: "e" + combining acute becomes the single precomposed "é".
        try expect(TranscriptPostProcessor.process("cafe\u{301}") == "Caf\u{E9}", "NFC normalization")
    }

    private static func gluedPunctuationPreserved() throws {
        try expectProcessed("example.com", "example.com", "domain")
        try expectProcessed("visit example.com. then", "Visit example.com. Then", "domain ending a sentence")
        try expectProcessed("me@site.io", "me@site.io", "email")
        try expectProcessed("README.md", "README.md", "file name")
        try expectProcessed("I use Node.js daily", "I use Node.js daily", "dotted product name")
        try expectProcessed("open search?q=x now", "Open search?q=x now", "query string")
        try expectProcessed("see https://a.io/x. next", "See https://a.io/x. Next", "URL ending a sentence")
        try expectProcessed("done. example.com works", "Done. example.com works", "sentence starting with a domain")
        try expectProcessed("ok. iPhone sales", "Ok. iPhone sales", "sentence starting with internal capital")
        try expectProcessed("ok. mp3 files", "Ok. mp3 files", "sentence starting with digits")
        try expectProcessed("ok. my_var is set", "Ok. my_var is set", "sentence starting with an identifier")
    }

    private static func leadingDotTokensPreserved() throws {
        try expectProcessed("edit the .zshrc file", "Edit the .zshrc file", "dotfile")
        try expectProcessed("I use .NET", "I use .NET", "leading-dot product")
        try expectProcessed("about .5 percent", "About .5 percent", "leading-dot number")
        try expectProcessed("well ... maybe", "Well ... maybe", "spaced ellipsis")
        // Accepted limitation: a standalone "." can't be told apart from a stray
        // space before a period, so it is glued and ends the sentence. Pinned
        // here so any change to it is deliberate.
        try expectProcessed("run git add . and commit", "Run git add. And commit", "standalone dot")
        try expectProcessed("so... maybe not", "So... maybe not", "ellipsis is a pause, not a sentence end")
    }

    private static func frenchSpacingPreserved() throws {
        try expectProcessed("Ça va ?", "Ça va ?", "space before ?")
        try expectProcessed("Attention : voici", "Attention : voici", "space before :")
        try expectProcessed("Quoi ! Non ; oui", "Quoi ! Non ; oui", "space before ! and ;")
    }

    private static func abbreviationsDoNotEndSentences() throws {
        try expectProcessed("e.g. this", "e.g. this", "e.g. at start")
        try expectProcessed("fruit, e.g. apples", "Fruit, e.g. apples", "e.g.")
        try expectProcessed("that is, i.e. the end", "That is, i.e. the end", "i.e.")
        try expectProcessed("at 3 p.m. tomorrow", "At 3 p.m. tomorrow", "p.m.")
        try expectProcessed("in the U.S. today", "In the U.S. today", "U.S.")
        try expectProcessed("apples, pears etc. are fine", "Apples, pears etc. are fine", "etc.")
        try expectProcessed("red vs. blue", "Red vs. blue", "vs.")
        try expectProcessed("ask Dr. smith", "Ask Dr. smith", "Dr.")
        try expectProcessed("about approx. ten", "About approx. ten", "approx.")
        try expectProcessed("she has a Ph.D. in physics", "She has a Ph.D. in physics", "Ph.D.")
        try expectProcessed("an M.Sc. from here", "An M.Sc. from here", "M.Sc.")
        try expectProcessed("Apple Inc. announced it", "Apple Inc. announced it", "Inc.")
        try expectProcessed("Acme Corp. and Foo Ltd. agreed", "Acme Corp. and Foo Ltd. agreed", "Corp. and Ltd.")
        try expectProcessed("(e.g. this) works", "(e.g. this) works", "abbreviation after bracket")
    }

    private static func firstWordCasingRespectsTokenShape() throws {
        try expectProcessed("iPhone is here", "iPhone is here", "iPhone")
        try expectProcessed("macOS update", "macOS update", "macOS")
        try expectProcessed("eBay listing", "eBay listing", "eBay")
        try expectProcessed("~/projects is mine", "~/projects is mine", "path")
        try expectProcessed("\"quoted\" start", "\"quoted\" start", "leading quote")
        try expectProcessed("über cool", "Über cool", "non-ASCII lowercase letter")
    }

    private static func linesProcessedIndependently() throws {
        let input = "Speaker 1: hello , there. how are you\n\n  \nSpeaker 2: fine .\n"
        let expected = "Speaker 1: hello, there. How are you\nSpeaker 2: fine."
        let actual = TranscriptPostProcessor.processPreservingLines(input)
        try expect(actual == expected, "multi-line: got \"\(actual)\"")

        let lower = TranscriptPostProcessor.processPreservingLines("first line\nsecond line")
        try expect(lower == "First line\nSecond line", "every line starts capitalized")

        let single = "just one line. ok"
        try expect(
            TranscriptPostProcessor.processPreservingLines(single) == TranscriptPostProcessor.process(single),
            "single line matches process"
        )
    }

    private static func capitalizeFirstFalseKeepsOpeningCase() throws {
        let piece = TranscriptPostProcessor.process("and then we left. next", capitalizeFirst: false)
        try expect(piece == "and then we left. Next", "mid-sentence chunk keeps its opening case: \"\(piece)\"")

        // Only the first non-empty line continues the prior piece; later lines
        // are new turns and still capitalize.
        let lines = TranscriptPostProcessor.processPreservingLines(
            "\n  \nwe agreed\nlater on",
            capitalizeFirst: false
        )
        try expect(lines == "we agreed\nLater on", "first non-empty line only: \"\(lines)\"")
    }
}
