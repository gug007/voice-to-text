import AppKit

/// Whether a word is an ordinary dictionary word in one of the user's
/// languages, for `TermCorrectionLearner.isTermFix(_:isKnownWord:)`. It only
/// decides whether to bother the user with an offer to remember a fix, so a
/// wrong answer costs one missed or one extra offer, never a correction.
enum KnownWords {
    /// `word` is lowercased. True when a spelling dictionary of one of the
    /// user's own languages, in the word's alphabet, has it — and when no
    /// such dictionary exists, since then nothing can tell a term from a
    /// plain word and the offer would only be noise.
    ///
    /// Only the user's languages are asked, and only about their own
    /// alphabet: a dictionary passes every word written in another one, and
    /// the dozens of languages macOS checks by default pass almost anything
    /// between them ("nginx" is fine by the Finnish one).
    static func contains(_ word: String) -> Bool {
        guard let script = script(of: word) else { return true }
        let judges = dictionaries(writtenIn: script)
        guard !judges.isEmpty else { return true }
        let checker = NSSpellChecker.shared
        return judges.contains { language in
            checker.checkSpelling(
                of: word,
                startingAt: 0,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            ).location == NSNotFound
        }
    }

    /// The spelling dictionaries for the languages the Mac is set to, among
    /// those written in `script`.
    private static func dictionaries(writtenIn script: String) -> [String] {
        let own = Set(Locale.preferredLanguages.compactMap { Locale.Language(identifier: $0).languageCode?.identifier })
        return NSSpellChecker.shared.availableLanguages.filter { identifier in
            let language = Locale.Language(identifier: identifier)
            guard let code = language.languageCode?.identifier, own.contains(code) else { return false }
            return Locale.Language(identifier: language.maximalIdentifier).script?.identifier == script
        }
    }

    /// The ISO 15924 code of the one alphabet `word` is written in, for the
    /// two the app's users mix; nil for any other and for a word in both.
    private static func script(of word: String) -> String? {
        var scripts = Set<String>()
        for scalar in word.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case ..<0x250, 0x1E00...0x1EFF: scripts.insert("Latn")
            case 0x400...0x52F: scripts.insert("Cyrl")
            default: return nil
            }
        }
        return scripts.count == 1 ? scripts.first : nil
    }
}
