import Foundation

/// One place where the user typed a short run of words over another on the
/// review card.
nonisolated struct TermEdit: Equatable, Sendable {
    let heard: String
    let replacement: String
    /// `replacement` opens a sentence in the edited text, so a capital on its
    /// first word may be the sentence's rather than the term's.
    var opensSentence = false
}

/// Turns what the user fixes on the review card into the corrections the
/// card offers to remember. Pure and Foundation-only so
/// `Tests/TermCorrectionHarness.swift` can compile it standalone.
///
/// A remembered correction rewrites every later transcript, so only an edit
/// that reads as an engine mishearing a name or a term is offered
/// (`isTermFix(_:isKnownWord:)`), and nothing changes without the user's
/// click. Anything else — a reworded phrase, a changed number, a fixed
/// homophone — is an edit to this one transcript, and Settings → Corrections
/// is where the user says otherwise.
nonisolated enum TermCorrectionLearner {
    static let maxHeardWords = 5
    static let maxReplacementWords = 4
    static let maxPhraseLength = 60
    /// Past this many changed-region words a diff is a rewrite, not a fix,
    /// and costs more than anything it could teach.
    static let maxComparedWords = 4000
    /// Likewise past this many words that one side has and the other lacks.
    /// The diff's cost grows with the square of how far apart the texts are,
    /// and fixing terms leaves them a few words apart.
    static let maxUnsharedWords = 400

    // MARK: - What changed

    /// The short substitutions that turn `original` into `edited`: runs of
    /// words replaced by other words, with unchanged words on both sides.
    /// Words added or removed outright are not substitutions, not even beside
    /// one ("cloud code daily" → "Claude Code" is "cloud code" → "Claude
    /// Code"), and neither is a change of punctuation alone.
    static func edits(from original: String, to edited: String) -> [TermEdit] {
        let before = words(in: original)
        let after = words(in: edited)
        let shorter = min(before.count, after.count)
        var prefix = 0
        while prefix < shorter, before[prefix].core == after[prefix].core { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix,
              before[before.count - 1 - suffix].core == after[after.count - 1 - suffix].core {
            suffix += 1
        }
        let changedBefore = Array(before[prefix..<(before.count - suffix)])
        let changedAfter = Array(after[prefix..<(after.count - suffix)])
        guard !changedBefore.isEmpty, !changedAfter.isEmpty,
              changedBefore.count <= maxComparedWords, changedAfter.count <= maxComparedWords,
              unsharedWords(changedBefore, changedAfter) <= maxUnsharedWords else { return [] }

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in changedAfter.map(\.core).difference(from: changedBefore.map(\.core)) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var edits: [TermEdit] = []
        var i = 0
        var j = 0
        while i < changedBefore.count || j < changedAfter.count {
            let heardStart = i
            let replacementStart = j
            while removed.contains(i) { i += 1 }
            while inserted.contains(j) { j += 1 }
            guard i > heardStart || j > replacementStart else {
                i += 1
                j += 1
                continue
            }
            guard (1...maxHeardWords).contains(i - heardStart),
                  (1...maxReplacementWords).contains(j - replacementStart) else { continue }
            let (heard, replacement) = alikeRuns(changedBefore[heardStart..<i], changedAfter[replacementStart..<j])
            let edit = TermEdit(
                heard: phrase(heard),
                replacement: phrase(replacement),
                opensSentence: replacement.first?.opensSentence ?? false
            )
            guard edit.heard.count <= maxPhraseLength, edit.replacement.count <= maxPhraseLength else { continue }
            edits.append(edit)
        }
        return edits
    }

    /// `heard` and `replacement` without the words at their ends that were
    /// only deleted or only added beside the fix: "um cloud code" → "Claude
    /// Code" is "cloud code" → "Claude Code". An end word goes when it adds
    /// nothing but its own length to how unlike the two runs sound: none of
    /// it was needed to account for the other side. The "j" of "jay" is, so
    /// "jay son" → "JSON" stays whole. A symbol or a digit says more than
    /// `sound` hears — "c plus plus" is "C++", "four oh" is "4o" — so a run
    /// with one in it stays whole too.
    private static func alikeRuns(
        _ heard: ArraySlice<Word>,
        _ replacement: ArraySlice<Word>
    ) -> (heard: ArraySlice<Word>, replacement: ArraySlice<Word>) {
        guard heard.count > 1 || replacement.count > 1,
              !(heard + replacement).contains(where: { word in
                  word.core.contains { $0.isNumber || identifierMarks.contains($0) }
              })
        else { return (heard, replacement) }
        let heardSounds = heard.map { sound(of: String($0.text)) }
        let replacementSounds = replacement.map { sound(of: String($0.text)) }
        func distance(_ kept: Range<Int>, _ written: Range<Int>) -> Int {
            editDistance(Array(heardSounds[kept].joined()), Array(replacementSounds[written].joined()))
        }
        var kept = 0..<heardSounds.count
        var written = 0..<replacementSounds.count
        var unlikeness = distance(kept, written)
        while true {
            // Each end word that could go, with the runs it would leave.
            var cuts: [(word: [Character], kept: Range<Int>, written: Range<Int>)] = []
            if kept.count > 1 {
                cuts.append((heardSounds[kept.lowerBound], (kept.lowerBound + 1)..<kept.upperBound, written))
                cuts.append((heardSounds[kept.upperBound - 1], kept.lowerBound..<(kept.upperBound - 1), written))
            }
            if written.count > 1 {
                cuts.append((replacementSounds[written.lowerBound], kept, (written.lowerBound + 1)..<written.upperBound))
                cuts.append((replacementSounds[written.upperBound - 1], kept, written.lowerBound..<(written.upperBound - 1)))
            }
            guard let cut = cuts.first(where: { cut in
                !cut.word.isEmpty && distance(cut.kept, cut.written) + cut.word.count == unlikeness
            }) else { break }
            unlikeness -= cut.word.count
            kept = cut.kept
            written = cut.written
        }
        return (
            heard[(heard.startIndex + kept.lowerBound)..<(heard.startIndex + kept.upperBound)],
            replacement[(replacement.startIndex + written.lowerBound)..<(replacement.startIndex + written.upperBound)]
        )
    }

    /// How many words the two runs do not have in common, wherever they
    /// stand: no diff between them is shorter.
    private static func unsharedWords(_ before: [Word], _ after: [Word]) -> Int {
        var counts: [Substring: Int] = [:]
        for word in before { counts[word.core, default: 0] += 1 }
        var shared = 0
        for word in after {
            guard let count = counts[word.core], count > 0 else { continue }
            counts[word.core] = count - 1
            shared += 1
        }
        return before.count + after.count - 2 * shared
    }

    private struct Word {
        let text: Substring
        /// `text` without the punctuation around it, which is what two words
        /// are compared by: "Cloud." and "Cloud," are the same word.
        let core: Substring
        let opensSentence: Bool
    }

    private static let openingMarks: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "«"]
    private static let closingMarks: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "…", ")", "]", "}", "\"", "'", "”", "’", "»",
    ]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        for line in text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isNewline) {
            var opensSentence = true
            for token in line.split(whereSeparator: \.isWhitespace) {
                words.append(Word(text: token, core: core(of: token), opensSentence: opensSentence))
                let end = token.last { !closingMarks.contains($0) || sentenceEnds.contains($0) }
                opensSentence = end.map(sentenceEnds.contains) ?? false
            }
        }
        return words
    }

    private static func core(of token: Substring) -> Substring {
        var core = token.drop(while: openingMarks.contains)
        while let last = core.last, closingMarks.contains(last) { core = core.dropLast() }
        return core
    }

    /// The run as one phrase: punctuation between its words is part of what
    /// was written, punctuation around it is the sentence's.
    private static func phrase(_ run: ArraySlice<Word>) -> String {
        String(core(of: run.map(\.text).joined(separator: " ")[...]))
    }

    // MARK: - What is worth remembering

    /// Whether one edit fixes a name or a term the engine got wrong, which
    /// the card offers to remember, rather than an edit to this one
    /// transcript, of which nothing is said.
    ///
    /// A remembered correction rewrites every later transcript, so an edit
    /// qualifies only when it reads as a mishearing: a term spelled as one
    /// ("github" → "GitHub", "cloud code" → "Claude Code", gpt4, Node.js), a
    /// word moved out of the alphabet the engine wrote it in ("клод" →
    /// "Claude"), or a name swapped for one that sounds like it ("Monday" →
    /// "Sunday", "Маша" → "Миша"), which only the user knows was misheard.
    /// Anything that sounds unlike it — a reworded phrase, a translation —
    /// is a change of mind, and a fix into ordinary dictionary words
    /// ("there" → "their") is grammar.
    ///
    /// `isKnownWord` says whether one lowercased word is an ordinary
    /// dictionary word, which is what tells a term the user typed in
    /// lowercase from a plain word.
    ///
    /// A lowercase word typed again in capitals is emphasis ("do NOT"), not a
    /// term: remembered, it would shout that word in every transcript.
    static func isTermFix(_ edit: TermEdit, isKnownWord: (String) -> Bool) -> Bool {
        // A correction for "не" or "is" would fire on every sentence.
        guard edit.heard.filter(\.isLetter).count >= 3,
              edit.replacement.filter(\.isLetter).count >= 2 else { return false }
        // A different number is a different fact.
        let heardDigits = edit.heard.filter(\.isNumber)
        let replacementDigits = edit.replacement.filter(\.isNumber)
        if !heardDigits.isEmpty, !replacementDigits.isEmpty, heardDigits != replacementDigits { return false }

        let heardWords = edit.heard.split(whereSeparator: \.isWhitespace)
        let replacementWords = edit.replacement.split(whereSeparator: \.isWhitespace)
        // The heard run stands where the replacement does, so a sentence's
        // capital explains the first word of either.
        func isNamed(_ words: [Substring]) -> Bool {
            words.enumerated().contains { index, word in
                isTermShaped(word)
                    || (word.first?.isUppercase == true && (index > 0 || !edit.opensSentence))
            }
        }
        func hasUnknownWord() -> Bool {
            replacementWords.contains { word in
                let spelled = letters(String(word))
                return !spelled.isEmpty && !isKnownWord(spelled)
            }
        }

        // The same letters re-cased or re-spaced: "git hub" → "GitHub".
        if letters(edit.heard) == letters(edit.replacement) {
            let shouted = !edit.replacement.contains(where: \.isLowercase)
                && !edit.heard.contains(where: \.isUppercase)
            return !shouted && (isNamed(replacementWords) || hasUnknownWord())
        }

        let likeness = similarity(sound(of: edit.heard), sound(of: edit.replacement))
        let changesAlphabet = !alphabets(in: edit.heard).isSubset(of: alphabets(in: edit.replacement))
        if changesAlphabet {
            // A term the engine spelled as one, typed out in plain words of
            // another alphabet, is the user's wording: GitHub → "гид хаб".
            if heardWords.contains(where: isTermShaped), !replacementWords.contains(where: isTermShaped) {
                return false
            }
            // Transliteration only gets near the spelling: "klod", "claude".
            return likeness >= 0.3
        }
        guard likeness >= 0.4 else { return false }
        return isNamed(heardWords) || isNamed(replacementWords) || hasUnknownWord()
    }

    private static func isTermShaped(_ word: Substring) -> Bool {
        hasInnerCapital(word) || isIdentifier(word)
    }

    private static func hasInnerCapital(_ word: Substring) -> Bool {
        word.dropFirst().contains(where: \.isUppercase)
    }

    private static let identifierMarks: Set<Character> = ["_", ".", "/", "\\", "@", "+", "#"]

    private static func isIdentifier(_ word: Substring) -> Bool {
        (word.contains(where: \.isLetter) && word.contains(where: \.isNumber))
            || word.dropFirst().contains(where: identifierMarks.contains)
    }

    private enum Alphabet { case latin, other }

    private static func alphabets(in phrase: String) -> Set<Alphabet> {
        var found = Set<Alphabet>()
        for scalar in phrase.unicodeScalars where scalar.properties.isAlphabetic {
            let isLatin = scalar.value < 0x250 || (0x1E00...0x1EFF).contains(scalar.value)
            found.insert(isLatin ? .latin : .other)
        }
        return found
    }

    private static func letters(_ phrase: String) -> String {
        String(phrase.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The phrase as Latin letters, as near as transliteration gets to how it
    /// sounds: "гид хаб" → "gidhab".
    private static func sound(of phrase: String) -> [Character] {
        let latin = phrase.applyingTransform(.toLatin, reverse: false) ?? phrase
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return plain.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// 1 for the same spelling, 0 for nothing in common: one minus the edit
    /// distance over the longer length.
    private static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return 1 - Double(editDistance(a, b)) / Double(max(a.count, b.count))
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j] + (x == y ? 0 : 1), previous[j + 1] + 1, current[j] + 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Proposing

    /// What the user's edits would make of the stored corrections, for the
    /// card to ask about. Nothing is stored until they say yes.
    struct Outcome: Equatable, Sendable {
        /// Corrections that would be new or write something else, as they
        /// would be stored.
        var remembered: [TermCorrection]
        /// Stored corrections that would go.
        var forgotten: [TermCorrection]

        /// Whether saying yes changes the stored list.
        var changes: Bool { !remembered.isEmpty || !forgotten.isEmpty }

        /// `list` with this change made: `forgotten` gone, `remembered` in
        /// place. `list` may have changed since the proposal was made.
        func applied(to list: [TermCorrection]) -> [TermCorrection] {
            let gone = Set(forgotten.map(\.id))
            return remembered.reduce(list.filter { !gone.contains($0.id) }) { TermCorrections.placing($1, in: $0) }
        }

        /// The line beside the button, whose title is the question: what
        /// would be rewritten, "cloud → Clyde", so the user can see what they
        /// say yes to. The card cuts off what does not fit.
        var question: String {
            switch (remembered.isEmpty, forgotten.isEmpty) {
            case (false, true): return Self.listing(remembered)
            case (true, false): return Self.listing(forgotten)
            default: return "Update \(remembered.count + forgotten.count) corrections?"
            }
        }

        /// The button that says yes.
        var button: String {
            switch (remembered.isEmpty, forgotten.isEmpty) {
            case (false, true): return "Remember"
            case (true, false): return "Forget"
            default: return "Update"
            }
        }

        /// The line once the user has said yes, beside its Undo.
        var confirmation: String {
            switch (remembered.count, forgotten.count) {
            case (1, 0): return Self.quoted(remembered[0]).map { "Remembered \($0)" } ?? "Remembered a correction"
            case (let count, 0): return "Remembered \(count) corrections"
            case (0, 1): return Self.quoted(forgotten[0]).map { "Forgot \($0)" } ?? "Forgot a correction"
            case (0, let count): return "Forgot \(count) corrections"
            case (let added, let dropped): return "Updated \(added + dropped) corrections"
            }
        }

        private static let quotedTermLimit = 16

        private static func listing(_ corrections: [TermCorrection]) -> String {
            corrections.map { "\($0.heard) → \($0.replacement)" }.joined(separator: ", ")
        }

        /// What `correction` writes, in quotes, when it is short enough to
        /// fit the line.
        private static func quoted(_ correction: TermCorrection) -> String? {
            correction.replacement.count <= quotedTermLimit ? "“\(correction.replacement)”" : nil
        }
    }

    /// How the user's `edits`, in the order they were made, would change the
    /// `stored` corrections.
    ///
    /// Typing back what a correction replaced drops that correction. Fixing
    /// what corrections write changes what they write; any other term fix
    /// changes the correction for the same words, or adds one.
    static func propose(
        _ edits: [TermEdit],
        to stored: [TermCorrection],
        isKnownWord: (String) -> Bool
    ) -> Outcome {
        var corrections = stored
        for edit in edits {
            if let index = corrections.firstIndex(where: { undoes(edit, $0) }) {
                corrections.remove(at: index)
                continue
            }
            guard isTermFix(edit, isKnownWord: isKnownWord) else { continue }
            let heardKey = TermCorrections.key(edit.heard)
            let writers = corrections.indices.filter {
                TermCorrections.key(corrections[$0].replacement) == heardKey
            }
            if !writers.isEmpty {
                for index in writers { corrections[index].replacement = edit.replacement }
            } else if let index = corrections.firstIndex(where: { TermCorrections.key($0.heard) == heardKey }) {
                corrections[index].replacement = edit.replacement
            } else {
                corrections.append(TermCorrection(heard: edit.heard, replacement: edit.replacement, isLearned: true))
            }
        }
        corrections.removeAll { !$0.isUsable }
        // Compared by what they do, so a correction dropped and made again
        // in the same edits is no change.
        func makes(_ a: TermCorrection, _ b: TermCorrection) -> Bool {
            TermCorrections.key(a.heard) == TermCorrections.key(b.heard) && a.replacement == b.replacement
        }
        let ids = Set(corrections.map(\.id))
        return Outcome(
            remembered: corrections.filter { new in !stored.contains { makes($0, new) } },
            forgotten: stored.filter { old in !ids.contains(old.id) && !corrections.contains { makes($0, old) } }
        )
    }

    /// Whether `edit` puts back the words `correction` replaced. A correction
    /// that only re-cases ("github" → "GitHub") is undone by its exact
    /// reverse alone: in any case, making it again would look the same.
    private static func undoes(_ edit: TermEdit, _ correction: TermCorrection) -> Bool {
        guard TermCorrections.key(edit.replacement) == TermCorrections.key(correction.heard),
              TermCorrections.key(edit.heard) == TermCorrections.key(correction.replacement) else { return false }
        guard TermCorrections.key(correction.heard) == TermCorrections.key(correction.replacement) else { return true }
        return edit.heard == correction.replacement && edit.replacement == correction.heard
    }
}

/// What the user has typed over on the review card since their dictation
/// began. The card's text is also rewritten for them — a resumed take spliced
/// in, an AI action's result — and none of that is theirs, so their edits are
/// gathered between those rewrites rather than read off one diff at the end.
nonisolated struct ReviewEditLog: Sendable {
    private var baseline: String?
    private var edits: [TermEdit] = []

    /// The app put `text` on the card.
    mutating func appWrote(_ text: String) {
        baseline = text
    }

    /// The card holds `text` now, whatever the user did to it.
    mutating func userWrote(_ text: String) {
        guard let baseline, baseline != text else { return }
        edits += TermCorrectionLearner.edits(from: baseline, to: text)
        self.baseline = text
    }

    /// The user kept `text`: every edit of the session, which ends here.
    mutating func finish(with text: String) -> [TermEdit] {
        userWrote(text)
        defer { reset() }
        return edits
    }

    mutating func reset() {
        self = ReviewEditLog()
    }
}
