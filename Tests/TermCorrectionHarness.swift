import Foundation

struct TermCorrectionHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TermCorrectionHarnessFailure(description: message)
    }
}

private func rule(_ heard: String, _ replacement: String) -> TermCorrection {
    TermCorrection(heard: heard, replacement: replacement)
}

private func expectApplied(
    _ rules: [TermCorrection],
    _ input: String,
    _ expected: String,
    _ label: String
) throws {
    let actual = TermCorrections.apply(rules, to: input)
    try expect(actual == expected, "\(label): \"\(input)\" → \"\(actual)\", expected \"\(expected)\"")
}

private func expectEdits(
    _ original: String,
    _ edited: String,
    _ expected: [(String, String)],
    _ label: String
) throws {
    let actual = TermCorrectionLearner.edits(from: original, to: edited).map { ($0.heard, $0.replacement) }
    let matches = actual.count == expected.count && zip(actual, expected).allSatisfy { $0 == $1 }
    try expect(matches, "\(label): got \(actual), expected \(expected)")
}

/// A few ordinary words, standing in for the spell checker the app asks.
private let knownWords: Set<String> = [
    "cloud", "code", "jason", "there", "their", "test", "tests", "today", "hello",
    "super", "base", "engine", "cube", "control", "monday", "sunday", "friday",
    "по", "этому", "поэтому", "привет", "сегодня", "завтра",
]
private let isKnown: (String) -> Bool = { knownWords.contains($0) }
private let nothingKnown: (String) -> Bool = { _ in false }

private func expectTermFix(
    _ heard: String,
    _ replacement: String,
    _ expected: Bool,
    opensSentence: Bool = false,
    known: (String) -> Bool = isKnown,
    _ label: String
) throws {
    let actual = TermCorrectionLearner.isTermFix(
        TermEdit(heard: heard, replacement: replacement, opensSentence: opensSentence),
        isKnownWord: known
    )
    try expect(actual == expected, "\(label): \"\(heard)\" → \"\(replacement)\" is \(actual ? "" : "not ")a term fix")
}

/// A proposal with the list it would leave, if accepted at once.
@dynamicMemberLookup
private struct Proposal {
    let outcome: TermCorrectionLearner.Outcome
    let corrections: [TermCorrection]

    subscript<Value>(dynamicMember path: KeyPath<TermCorrectionLearner.Outcome, Value>) -> Value {
        outcome[keyPath: path]
    }
}

private func propose(_ edits: [TermEdit], to stored: [TermCorrection]) -> Proposal {
    let outcome = TermCorrectionLearner.propose(edits, to: stored, isKnownWord: isKnown)
    return Proposal(outcome: outcome, corrections: outcome.applied(to: stored))
}

private func propose(from original: String, to edited: String, stored: [TermCorrection] = []) -> Proposal {
    propose(TermCorrectionLearner.edits(from: original, to: edited), to: stored)
}

private func expectWording(
    _ outcome: TermCorrectionLearner.Outcome,
    _ question: String,
    _ button: String,
    _ confirmation: String,
    _ label: String
) throws {
    try expect(
        outcome.question == question && outcome.button == button && outcome.confirmation == confirmation,
        "\(label): \"\(outcome.question)\" [\(outcome.button)] → \"\(outcome.confirmation)\""
    )
}

@main
struct TermCorrectionHarness {
    static func main() throws {
        try appliesWholePhrases()
        try appliesInsideThePostProcessor()
        try findsSubstitutions()
        try judgesEachEdit()
        try proposesRememberingForgettingAndRetargeting()
        try appliesToTheListAsItIsNow()
        try wordsTheQuestion()
        try gathersEditsAroundRewrites()
        try survivesCoding()
        print("Term correction harness passed")
    }

    private static func appliesWholePhrases() throws {
        let hub = [rule("гид хаб", "GitHub")]
        try expectApplied(hub, "залей на гид хаб.", "залей на GitHub.", "phrase before punctuation")
        try expectApplied(hub, "Гид ХАБ лежит", "GitHub лежит", "any case")
        try expectApplied(hub, "гид   хаб и гид\nхаб", "GitHub и GitHub", "any whitespace, every occurrence")
        try expectApplied(hub, "автогид хаб", "автогид хаб", "not inside a longer word (before)")
        try expectApplied(hub, "гид хабы", "гид хабы", "not inside a longer word (after)")
        try expectApplied(hub, "гид, хаб", "гид, хаб", "punctuation between the words is another phrase")
        try expectApplied(hub, "(гид хаб)", "(GitHub)", "inside brackets")
        try expectApplied([], "гид хаб", "гид хаб", "no corrections")
        try expectApplied(hub, "", "", "empty text")

        try expectApplied(
            [rule("клод", "Claude"), rule("клод код", "Claude Code")],
            "открой клод код и клод",
            "открой Claude Code и Claude",
            "the longer phrase wins"
        )
        try expectApplied([rule("c++", "C++")], "i like c++ a lot", "i like C++ a lot", "symbols in the phrase")
        try expectApplied([rule("price", "$1 \\0")], "the price is", "the $1 \\0 is", "replacement is literal")
        try expectApplied([rule("a.b", "x")], "a.b axb", "x axb", "phrase is literal")
        try expectApplied([rule("github", "GitHub")], "GITHUB and GitHub", "GitHub and GitHub", "re-casing")
        try expectApplied([rule("same", "same"), rule("", "x"), rule("y", "")], "same y", "same y", "unusable corrections do nothing")

        // Contractions, possessives and elisions.
        let dan = [rule("don", "Dan")]
        try expectApplied(dan, "I don't know", "I don't know", "not inside a contraction")
        try expectApplied(dan, "I don’t know", "I don’t know", "nor with a curly apostrophe")
        try expectApplied(dan, "Ask don about it", "Ask Dan about it", "the word on its own")
        try expectApplied(dan, "don's car and don’s bike", "Dan's car and Dan’s bike", "a possessive")
        try expectApplied(dan, "don'sy", "don'sy", "not an 's that goes on")
        try expectApplied(dan, "'don'", "'Dan'", "in single quotes")
        try expectApplied([rule("github", "GitHub")], "l'github et d’github", "l'GitHub et d’GitHub", "after an elision")

        // A combining mark carries the word on.
        try expectApplied([rule("कम", "X")], "कमी कम", "कमी X", "not before a vowel sign")
        try expectApplied([rule("до", "X")], "до\u{0301} до", "до\u{0301} X", "not before a stress mark")

        // One pass over the text as it came in.
        let cloud = [rule("cloud", "Claude"), rule("google cloud", "Google Cloud")]
        try expectApplied(cloud, "we moved to google cloud last year", "we moved to Google Cloud last year", "a longer exception")
        try expectApplied(cloud, "cloud and google cloud", "Claude and Google Cloud", "each where it matches")
        try expectApplied(
            [rule("clod", "Claude"), rule("claude", "Claude Code")],
            "clod is here, claude too",
            "Claude is here, Claude Code too",
            "what one correction writes is not corrected again"
        )
        try expectApplied([rule("alpha", "beta"), rule("beta", "gamma")], "alpha beta", "beta gamma", "no chains")
        try expectApplied([rule("cd ef", "Y"), rule("ab cd", "X")], "ab cd ef", "X ef", "of two as long, the earlier")
        let untouched = "nothing to see here"
        try expect(
            TermCorrections.apply(dan, to: untouched).utf8.elementsEqual(untouched.utf8),
            "no match leaves the text as it was"
        )

        try expect(TermCorrections.normalized("  гид \n хаб ") == "гид хаб", "normalized trims and single-spaces")
        try expect(TermCorrections.key("Гид  ХАБ") == TermCorrections.key("гид хаб"), "key ignores case and spacing")
        try expect(rule(" Git  Hub ", " GitHub ").heard == "Git Hub", "a correction is stored normalized")
    }

    private static func appliesInsideThePostProcessor() throws {
        let rules = [rule("гид хаб", "GitHub"), rule("вайтлист", "whitelist"), rule("айфон", "iPhone")]
        let processed = TranscriptPostProcessor.process(
            "залей это на  гид хаб . вайтлист готов. айфон тоже",
            corrections: rules
        )
        try expect(
            processed == "Залей это на GitHub. Whitelist готов. iPhone тоже",
            "corrected, then cased: \"\(processed)\""
        )
        let lines = TranscriptPostProcessor.processPreservingLines(
            "Speaker 1: это гид хаб\nSpeaker 2: вайтлист",
            corrections: rules
        )
        try expect(lines == "Speaker 1: это GitHub\nSpeaker 2: whitelist", "every line corrected: \"\(lines)\"")
        try expect(
            TranscriptPostProcessor.process("гид хаб") == "Гид хаб",
            "no corrections by default"
        )
    }

    private static func findsSubstitutions() throws {
        try expectEdits(
            "Залей ветку на гид хаб и открой там пул-реквест. Потом проверь гид хаб ещё раз.",
            "Залей ветку на GitHub и открой там пул-реквест. Потом проверь GitHub ещё раз.",
            [("гид хаб", "GitHub"), ("гид хаб", "GitHub")],
            "the same fix twice"
        )
        try expectEdits("open cloud code now", "open Claude Code now", [("cloud code", "Claude Code")], "two words for two")
        try expectEdits("say (гид хаб), ok", "say (GitHub), ok", [("гид хаб", "GitHub")], "punctuation around the run is not part of it")
        try expectEdits("use c, plus plus here", "use C++ here", [("c, plus plus", "C++")], "punctuation inside the run is")
        try expectEdits("hello world", "hello, world!", [], "punctuation alone")
        try expectEdits("hello world", "hello big world", [], "an added word")
        try expectEdits("hello big world", "hello world", [], "a removed word")
        try expectEdits("same text", "same text", [], "nothing changed")
        try expectEdits("", "new text", [], "from nothing")
        try expectEdits("old text", "", [], "to nothing")
        try expectEdits(
            "one two three four five six seven",
            "one a b c d e seven",
            [],
            "more words than a term has"
        )
        try expectEdits("line one\nгид хаб here", "line one\nGitHub here", [("гид хаб", "GitHub")], "across lines")

        // Two fixes far apart in a long take are still two fixes; a long take
        // typed over from end to end is not diffed at all.
        let filler = (1...1500).map { "слово\($0)" }.joined(separator: " ")
        try expectEdits(
            "гид хаб \(filler) клод",
            "GitHub \(filler) Claude",
            [("гид хаб", "GitHub"), ("клод", "Claude")],
            "fixes at both ends of a long take"
        )
        let rewrite = (1...1500).map { "word\($0)" }.joined(separator: " ")
        try expectEdits("start \(filler) end", "start \(rewrite) end", [], "a wholesale rewrite")

        // Words deleted or added beside a fix are not part of it.
        try expectEdits("I use cloud code daily", "I use Claude Code", [("cloud code", "Claude Code")], "deleted after")
        try expectEdits("um cloud code", "so Claude Code", [("um cloud code", "so Claude Code")], "a word swapped beside it stays")
        try expectEdits("um cloud code is nice", "Claude Code is nice", [("cloud code", "Claude Code")], "deleted before")
        try expectEdits("the the cloud code", "the Claude Code", [("cloud code", "Claude Code")], "a doubled word deleted")
        try expectEdits("open cloud code now", "open Claude Code app now", [("cloud code", "Claude Code")], "added after")
        try expectEdits("open cloud code now", "open the Claude Code now", [("cloud code", "Claude Code")], "added before")
        for (heard, replacement) in [
            ("git hub", "GitHub"), ("pay pal", "PayPal"), ("super base", "Supabase"), ("cube control", "kubectl"),
            ("engine x", "nginx"), ("эс кью эль", "SQL"), ("гид хаб", "GitHub"), ("Zandro Velits", "zandrovex"),
            // A word that sounds little like its letter or its digits is still part of the term.
            ("jay son", "JSON"), ("are sync", "rsync"), ("and video", "Nvidia"), ("open a eye", "OpenAI"),
            ("gpt four", "GPT-4"), ("iphone fifteen", "iPhone 15"), ("gpt four oh", "GPT-4o"), ("k eight s", "k8s"),
        ] {
            try expectEdits("we use \(heard) now", "we use \(replacement) now", [(heard, replacement)], "\(heard) stays whole")
        }
        let keptStart = TermCorrectionLearner.edits(from: "Done. cloud code works", to: "Done. So Claude Code works")
        try expect(
            keptStart.count == 1 && keptStart[0].replacement == "Claude Code" && !keptStart[0].opensSentence,
            "the sentence opens on an added word: \(keptStart)"
        )
        let keptOpening = TermCorrectionLearner.edits(from: "Done. um cloud code works", to: "Done. Claude Code works")
        try expect(keptOpening.count == 1 && keptOpening[0].opensSentence, "on the kept one: \(keptOpening)")

        let opening = TermCorrectionLearner.edits(from: "Done. привет all", to: "Done. Привет all")
        try expect(opening.count == 1 && opening[0].opensSentence, "after a full stop opens a sentence")
        let quoted = TermCorrectionLearner.edits(from: "He said \"stop.\" привет all", to: "He said \"stop.\" Привет all")
        try expect(quoted.count == 1 && quoted[0].opensSentence, "after a closing quote too")
        let lineStart = TermCorrectionLearner.edits(from: "one\nпривет all", to: "one\nПривет all")
        try expect(lineStart.count == 1 && lineStart[0].opensSentence, "a new line opens a sentence")
        let middle = TermCorrectionLearner.edits(from: "Done, привет all", to: "Done, Привет all")
        try expect(middle.count == 1 && !middle[0].opensSentence, "after a comma does not")
    }

    private static func judgesEachEdit() throws {
        // The spelling or the alphabet says it is a term.
        try expectTermFix("гид хаб", "GitHub", true, "гид хаб → GitHub")
        try expectTermFix("гид хаб", "github", true, "into one alphabet, lowercase")
        try expectTermFix("клод", "Claude", true, "клод → Claude")
        try expectTermFix("клод код", "Claude Code", true, "клод код → Claude Code")
        try expectTermFix("cloud code", "Claude Code", true, "cloud code → Claude Code")
        try expectTermFix("super base", "Supabase", true, "super base → Supabase")
        try expectTermFix("вайтлист", "whitelist", true, "вайтлист → whitelist")
        try expectTermFix("юкассу", "ЮKassу", true, "юкассу → ЮKassу")
        try expectTermFix("git hub", "GitHub", true, "re-spaced and re-cased")
        try expectTermFix("github", "GitHub", true, "re-cased")
        try expectTermFix("pay pal", "PayPal", true, "joined into one term")
        try expectTermFix("Chat GPT", "ChatGPT", true, "joined")
        try expectTermFix("Nasa", "NASA", true, "an acronym the engine wrote as a name")
        try expectTermFix("jason", "JSON", true, known: nothingKnown, "jason → JSON, jason not a word")
        try expectTermFix("engine x", "Nginx", true, "engine x → Nginx")
        try expectTermFix("cube control", "Kubectl", true, "cube control → Kubectl")
        try expectTermFix("node js", "Node.js", true, "node js → Node.js")
        try expectTermFix("эс кью эль", "SQL", true, "a spelled-out acronym")
        try expectTermFix("саммари", "summary", true, "a loanword put back in its own alphabet")

        // It sounds alike, and only the user knows it is a fix.
        try expectTermFix("Zandrovelits", "zandrovex", true, "a name the engine made up, fixed in lowercase")
        try expectTermFix("Zandro Velits", "zandrovex", true, "the same name heard as two")
        try expectTermFix("Monday", "Sunday", true, "another day")
        try expectTermFix("Маша", "Миша", true, "a similar name")
        try expectTermFix("John", "Jon", true, "a name respelled")
        try expectTermFix("GitHab", "GitHub", true, "a near miss the engine capitalized")
        try expectTermFix("GitHub", "GitLab", true, "a similar product")
        try expectTermFix("JavaScript", "TypeScript", true, "a similar language")
        try expectTermFix("cloud", "Claude", true, "one plain word for a name")
        try expectTermFix("jason", "JSON", true, "jason → JSON, jason a word")
        try expectTermFix("мария", "Мария", true, "a word capitalized mid-sentence")
        try expectTermFix("git hub", "github", true, "joined into a word no dictionary has")
        try expectTermFix("engine x", "nginx", true, "a term typed in lowercase")
        try expectTermFix("cube control", "kubectl", true, "kubectl in lowercase")
        try expectTermFix("правок", "правокcurso", true, "letters typed in the wrong layout")

        // Changes of mind, wording and grammar.
        try expectTermFix("сегодня", "завтра", false, "a different word")
        try expectTermFix("я думаю", "мне кажется", false, "a reworded phrase")
        try expectTermFix("there", "their", false, "a homophone")
        try expectTermFix("test", "tests", false, "a plural")
        try expectTermFix("по этому", "поэтому", false, "words joined into a word")
        try expectTermFix("привет", "Привет", false, opensSentence: true, "a sentence's own capital")
        try expectTermFix("he", "She", false, "too short to correct everywhere")
        try expectTermFix("не", "НЕ", false, "emphasis on a two-letter word")
        try expectTermFix("not", "NOT", false, "emphasis in capitals")
        try expectTermFix("очень важно", "ОЧЕНЬ ВАЖНО", false, "a phrase in capitals")
        try expectTermFix("сегодня", "today", false, "a translation that shares a few letters")
        try expectTermFix("Иван", "Пётр", false, "another person")
        try expectTermFix("Москве", "Питере", false, "another place")
        try expectTermFix("iPhone", "iPad", false, "another device")
        try expectTermFix("GPT-4", "GPT-5", false, "another version")
        try expectTermFix("5", "10", false, "another number")
        try expectTermFix("привет", "hello", false, "a translation")
        try expectTermFix("GitHub", "гид хаб", false, "what a correction replaced, typed back")
    }

    private static func proposesRememberingForgettingAndRetargeting() throws {
        let hub = TermEdit(heard: "гид хаб", replacement: "GitHub")
        let hubBack = TermEdit(heard: "GitHub", replacement: "гид хаб")

        let first = propose([hub, hub], to: [])
        try expect(first.corrections.count == 1, "the same fix twice is one correction")
        try expect(first.corrections[0].heard == "гид хаб" && first.corrections[0].replacement == "GitHub", "proposed as typed")
        try expect(first.corrections[0].isLearned, "marked learned")
        try expect(first.remembered == first.corrections && first.forgotten.isEmpty && first.changes, "reported as remembered")

        let again = propose([hub], to: first.corrections)
        try expect(!again.changes && again.corrections == first.corrections, "a fix identical to a stored one proposes nothing")

        let ignored = propose([TermEdit(heard: "сегодня", replacement: "завтра")], to: first.corrections)
        try expect(!ignored.changes && ignored.corrections == first.corrections, "a rewording proposes nothing")

        let undone = propose([hubBack], to: first.corrections)
        try expect(
            undone.corrections.isEmpty && undone.forgotten == first.corrections && undone.remembered.isEmpty,
            "typing it back proposes forgetting it"
        )

        let undoneAtSentenceStart = propose(
            [TermEdit(heard: "Whitelist", replacement: "вайтлист", opensSentence: true)],
            to: [rule("вайтлист", "whitelist")]
        )
        try expect(undoneAtSentenceStart.corrections.isEmpty, "typed back where the sentence capitalized it")

        let backAndForth = propose([hub, hubBack], to: [])
        try expect(backAndForth.corrections.isEmpty && !backAndForth.changes, "made and typed back in the same edits")

        let forthAndBack = propose([hubBack, hub], to: first.corrections)
        try expect(!forthAndBack.changes, "dropped and made again in the same edits: \(forthAndBack)")

        // Fixing what a correction wrote changes what it writes, as one change.
        let rough = [rule("гид хаб", "Github")]
        let retargeted = propose([TermEdit(heard: "Github", replacement: "GitHub")], to: rough)
        try expect(
            retargeted.corrections.count == 1 && retargeted.corrections[0].id == rough[0].id
                && retargeted.corrections[0].replacement == "GitHub",
            "the correction now writes the fixed spelling, and nothing else is added: \(retargeted.corrections)"
        )
        try expect(retargeted.remembered.count == 1 && retargeted.forgotten.isEmpty, "one change")
        try expectWording(retargeted.outcome, "гид хаб → GitHub", "Remember", "Remembered “GitHub”", "retargeted")

        let renamed = propose(from: "Ask Claude about it", to: "Ask Clyde about it", stored: [rule("cloud", "Claude")])
        try expect(renamed.corrections.map(\.replacement) == ["Clyde"], "a name a correction wrote, renamed")
        try expect(renamed.question == "cloud → Clyde", "asked as the correction it leaves: \(renamed.question)")

        let reworded = propose([TermEdit(heard: "Github", replacement: "нашего сервиса")], to: rough)
        try expect(reworded.corrections == rough && !reworded.changes, "rewording a correction's output leaves it alone")

        let replaced = propose([TermEdit(heard: "Гид Хаб", replacement: "GitHub")], to: rough)
        try expect(replaced.corrections.count == 1 && replaced.corrections[0].replacement == "GitHub", "one correction per phrase, the latest")
        try expect(replaced.corrections[0].id == rough[0].id, "updated in place")

        // A correction that only re-cases is undone by its exact reverse.
        let recase = [rule("github", "GitHub")]
        let sameAgain = propose([TermEdit(heard: "github", replacement: "GitHub")], to: recase)
        try expect(sameAgain.corrections == recase && !sameAgain.changes, "making a re-casing again proposes nothing")
        let lowered = propose([TermEdit(heard: "GitHub", replacement: "github")], to: recase)
        try expect(lowered.corrections.isEmpty && lowered.forgotten == recase, "its reverse proposes forgetting it")
        let recased = propose(from: "we use GitHub daily", to: "we use Github daily", stored: recase)
        try expect(
            recased.forgotten.isEmpty && recased.corrections.count == 1 && recased.corrections[0].id == recase[0].id
                && recased.corrections[0].replacement == "Github",
            "re-casing what it wrote retargets it: \(recased.corrections)"
        )
        try expectWording(recased.outcome, "github → Github", "Remember", "Remembered “Github”", "re-case retarget")

        let manual = [rule("hub", "Hub")]
        let kept = propose([hub], to: manual)
        try expect(kept.corrections.first == manual[0] && kept.corrections.count == 2, "existing corrections stay, in order")
        try expect(kept.remembered.map(\.replacement) == ["GitHub"], "only the new one is remembered")

        // A later fix of the same words replaces the earlier one.
        let monday = TermEdit(heard: "Monday", replacement: "Sunday")
        let respelled = propose([monday, TermEdit(heard: "Monday", replacement: "Friday")], to: [])
        try expect(respelled.remembered.map(\.replacement) == ["Friday"], "the latest fix: \(respelled.remembered)")

        let several = propose([hub, monday], to: [])
        try expect(several.remembered.count == 2 && several.forgotten.isEmpty, "several")
        try expectWording(
            several.outcome,
            "гид хаб → GitHub, Monday → Sunday", "Remember", "Remembered 2 corrections",
            "several"
        )

        let mixed = propose([monday, hubBack], to: first.corrections)
        try expect(
            mixed.remembered.map(\.replacement) == ["Sunday"] && mixed.forgotten == first.corrections,
            "one remembered, one forgotten: \(mixed.outcome)"
        )
        try expectWording(mixed.outcome, "Update 2 corrections?", "Update", "Updated 2 corrections", "mixed")

        // Words deleted or added beside a fix are not part of it.
        let trailing = propose(from: "I use cloud code daily", to: "I use Claude Code")
        try expect(
            trailing.remembered.map { "\($0.heard)|\($0.replacement)" } == ["cloud code|Claude Code"],
            "a word deleted after the fix: \(trailing.remembered)"
        )
        let leading = propose(from: "um cloud code is nice", to: "Claude Code is nice")
        try expect(
            leading.remembered.map { "\($0.heard)|\($0.replacement)" } == ["cloud code|Claude Code"],
            "a word deleted before the fix: \(leading.remembered)"
        )
        try expect(leading.question == "cloud code → Claude Code", "asked as the fix: \(leading.question)")
    }

    private static func appliesToTheListAsItIsNow() throws {
        let hub = rule("гид хаб", "Github")
        let claude = rule("клод", "Claude")
        let sunday = rule("Monday", "Sunday")
        let proposal = TermCorrectionLearner.propose(
            [
                TermEdit(heard: "Github", replacement: "GitHub"),
                TermEdit(heard: "Claude", replacement: "клод"),
                TermEdit(heard: "cloud code", replacement: "Claude Code"),
            ],
            to: [hub, claude],
            isKnownWord: isKnown
        )
        try expect(proposal.remembered.count == 2 && proposal.forgotten == [claude], "proposed: \(proposal)")

        // While the card asked, Settings added one, removed none, and changed
        // nothing the proposal touches.
        let now = [hub, claude, sunday]
        let after = proposal.applied(to: now)
        try expect(after.contains(sunday), "a correction added meanwhile stays: \(after)")
        try expect(!after.contains { $0.id == claude.id }, "the forgotten one goes")
        try expect(
            after.first { $0.id == hub.id }?.replacement == "GitHub" && after.first == after.first { $0.id == hub.id },
            "the retargeted one changes in place"
        )
        try expect(after.contains { $0.heard == "cloud code" && $0.replacement == "Claude Code" }, "the new one is added")
        try expect(after.count == 3, "nothing else: \(after)")

        // Settings removed the correction a proposal forgets: nothing to do.
        try expect(proposal.applied(to: [hub]).count == 2, "forgetting one already gone")

        // Settings typed in a correction for the same words: the accepted
        // fix takes its place, one per phrase.
        let typedIn = rule("cloud code", "Cloud Code")
        let placed = proposal.applied(to: [hub, typedIn])
        try expect(
            placed.filter { TermCorrections.key($0.heard) == "cloud code" }.map(\.replacement) == ["Claude Code"],
            "one correction per phrase: \(placed)"
        )
    }

    private static func wordsTheQuestion() throws {
        func outcome(remembered: [TermCorrection] = [], forgotten: [TermCorrection] = []) -> TermCorrectionLearner.Outcome {
            TermCorrectionLearner.Outcome(remembered: remembered, forgotten: forgotten)
        }
        let hub = rule("гид хаб", "GitHub")
        let claude = rule("клод", "Claude")
        let long = rule("x", "A Very Long Product Name")
        try expect(!outcome().changes, "nothing to ask")
        try expectWording(outcome(remembered: [hub]), "гид хаб → GitHub", "Remember", "Remembered “GitHub”", "one remembered")
        try expectWording(
            outcome(remembered: [long]),
            "x → A Very Long Product Name", "Remember", "Remembered a correction",
            "one too long to quote"
        )
        try expectWording(
            outcome(remembered: [hub, claude]),
            "гид хаб → GitHub, клод → Claude", "Remember", "Remembered 2 corrections",
            "several remembered"
        )
        try expectWording(outcome(forgotten: [hub]), "гид хаб → GitHub", "Forget", "Forgot “GitHub”", "one forgotten")
        try expectWording(
            outcome(forgotten: [long]),
            "x → A Very Long Product Name", "Forget", "Forgot a correction",
            "one forgotten, too long to quote"
        )
        try expectWording(
            outcome(forgotten: [hub, claude]),
            "гид хаб → GitHub, клод → Claude", "Forget", "Forgot 2 corrections",
            "several forgotten"
        )
        try expectWording(
            outcome(remembered: [hub], forgotten: [claude]),
            "Update 2 corrections?", "Update", "Updated 2 corrections",
            "both"
        )
    }

    private static func gathersEditsAroundRewrites() throws {
        var log = ReviewEditLog()
        try expect(log.finish(with: "anything").isEmpty, "nothing on the card, nothing learned")

        log.appWrote("открой гид хаб")
        let simple = log.finish(with: "открой GitHub")
        try expect(simple == [TermEdit(heard: "гид хаб", replacement: "GitHub")], "an edit, then paste")
        try expect(log.finish(with: "открой клод").isEmpty, "finish ends the session")

        // Edit, Resume, edit again: the spliced take is not the user's typing.
        log.appWrote("открой гид хаб")
        log.userWrote("открой GitHub")
        log.userWrote("открой GitHub")
        log.appWrote("открой GitHub и спроси клод про счёт")
        let resumed = log.finish(with: "открой GitHub и спроси Claude про счёт")
        try expect(
            resumed == [
                TermEdit(heard: "гид хаб", replacement: "GitHub"),
                TermEdit(heard: "клод", replacement: "Claude"),
            ],
            "edits before and after a Resume: \(resumed)"
        )

        // An action's rewrite is not the user's either, and neither is its undo.
        log.appWrote("открой гид хаб пожалуйста")
        log.userWrote("открой гид хаб пожалуйста")
        log.appWrote("Open Git Hub, please")
        log.appWrote("открой гид хаб пожалуйста")
        try expect(log.finish(with: "открой гид хаб пожалуйста").isEmpty, "an action run and undone teaches nothing")

        log.appWrote("открой гид хаб")
        log.reset()
        try expect(log.finish(with: "открой GitHub").isEmpty, "reset forgets the card")
    }

    private static func survivesCoding() throws {
        let stored = [TermCorrection(heard: "гид хаб", replacement: "GitHub", isLearned: true), rule("клод", "Claude")]
        let decoded = try JSONDecoder().decode([TermCorrection].self, from: JSONEncoder().encode(stored))
        try expect(decoded == stored, "round-trips")

        let legacy = Data(#"[{"id":"7E0E4C2E-6B0C-4B4E-9A51-0B3E1D2C3F40","heard":"  клод ","replacement":"Claude"}]"#.utf8)
        let old = try JSONDecoder().decode([TermCorrection].self, from: legacy)
        try expect(old.count == 1 && old[0].heard == "клод" && !old[0].isLearned, "a missing flag reads as typed in, normalized")
    }
}
