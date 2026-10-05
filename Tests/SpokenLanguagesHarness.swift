import Foundation

struct SpokenLanguagesHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SpokenLanguagesHarnessFailure(description: message)
    }
}

@main
struct SpokenLanguagesHarness {
    @MainActor
    static func main() throws {
        try identifiersReduceToTheirLanguage()
        try aValidOverrideIsTheOnlyAnswer()
        try whatTheUserDictatesBeatsTheMacsSettings()
        try withoutHistoryMenusAndKeyboardsAreJoinedAndTheFirstMenuLanguageLeads()
        try onlyLanguagesSeenOftenEnoughCount()
        try transcriptsAreReadForTheirLanguage()
        try theOwnersMacPicksTheParakeetItHas()
        try theLiveReadingIsWellFormed()
        print("Spoken languages harness passed")
    }

    private static func identifiersReduceToTheirLanguage() throws {
        let cases: [(String, String?)] = [
            ("en-US", "en"), ("ru", "ru"), ("pt_BR", "pt"), ("zh-Hans-CN", "zh"),
            ("yue-Hant", "yue"), (" DE ", "de"), ("", nil), ("auto", nil), ("e1", nil), ("english", nil),
        ]
        for (identifier, expected) in cases {
            let got = SpokenLanguages.primarySubtag(identifier)
            try expect(got == expected, "\"\(identifier)\" → \(String(describing: got)), expected \(String(describing: expected))")
        }
    }

    private static func resolve(
        override: String? = nil,
        dictated: Set<String> = [],
        preferred: [String],
        keyboards: [String]
    ) -> SpokenLanguages.Reading {
        SpokenLanguages.resolve(
            override: override,
            dictatedLanguages: dictated,
            preferredLanguages: preferred,
            inputSourceLanguages: keyboards
        )
    }

    private static func aValidOverrideIsTheOnlyAnswer() throws {
        try expect(
            resolve(override: "ja", dictated: ["en"], preferred: ["en-US"], keyboards: ["ru"])
                == .init(languages: ["ja"], primary: nil),
            "decoder.language alone decides, over History too"
        )
        try expect(
            resolve(override: "auto", preferred: ["en-US"], keyboards: ["ru"])
                == .init(languages: ["en", "ru"], primary: "en"),
            "an override that isn't a language is ignored, not trusted"
        )
    }

    private static func whatTheUserDictatesBeatsTheMacsSettings() throws {
        try expect(
            resolve(dictated: ["en", "ru"], preferred: ["en-AM", "hy-AM", "ru-AM"], keyboards: ["en", "hy", "ru"])
                == .init(languages: ["en", "ru"], primary: nil),
            "dictations in English and Russian answer, whatever the keyboards; every one of them counts"
        )
    }

    private static func withoutHistoryMenusAndKeyboardsAreJoinedAndTheFirstMenuLanguageLeads() throws {
        try expect(
            resolve(preferred: ["en-GB", "en-US"], keyboards: ["ru", "en"])
                == .init(languages: ["en", "ru"], primary: "en"),
            "English menus and a Russian keyboard: {en, ru}, sure of English"
        )
        try expect(
            resolve(preferred: ["en-AM", "hy-AM", "ru-AM"], keyboards: ["en", "hy", "ru"])
                == .init(languages: ["en", "hy", "ru"], primary: "en"),
            "the owner's settings alone: {en, hy, ru}, sure of English"
        )
        try expect(
            resolve(preferred: [], keyboards: []) == .init(languages: [], primary: nil),
            "nothing known is an empty set, which the policy reads as covered"
        )
    }

    private static func onlyLanguagesSeenOftenEnoughCount() throws {
        let repeated = { (language: String, times: Int) in Array(repeating: language, count: times) }
        try expect(
            SpokenLanguages.dominantLanguages(repeated("en", 20) + repeated("ru", 8)) == ["en", "ru"],
            "a second language dictated now and then counts"
        )
        try expect(
            SpokenLanguages.dominantLanguages(repeated("en", 28) + ["hy"]) == ["en"],
            "one misread transcript doesn't add a language"
        )
        try expect(
            SpokenLanguages.dominantLanguages(repeated("en", 27) + repeated("de", 2)) == ["en"],
            "nor do two among thirty, under a tenth"
        )
        try expect(
            SpokenLanguages.dominantLanguages(["en", "en"]).isEmpty,
            "two dictations are too few to go on"
        )
        try expect(
            SpokenLanguages.dominantLanguages(["en", "ru", "de"]).isEmpty,
            "three dictations that agree on nothing say nothing"
        )
        try expect(
            SpokenLanguages.dominantLanguages(["en", "en", "en"]) == ["en"],
            "three that agree are enough"
        )
    }

    private static func transcriptsAreReadForTheirLanguage() throws {
        let cases: [(String, String?)] = [
            ("Let's meet tomorrow at ten and go over the quarterly numbers together.", "en"),
            ("Давай встретимся завтра в десять и вместе обсудим квартальные цифры.", "ru"),
            ("Վաղը ժամը տասին հանդիպենք և միասին քննարկենք եռամսյակի թվերը։", "hy"),
            ("OK, thanks", nil),
            ("   ", nil),
        ]
        for (text, expected) in cases {
            let got = SpokenLanguages.detectedLanguage(of: text)
            try expect(got == expected, "\"\(text)\" → \(String(describing: got)), expected \(String(describing: expected))")
        }
    }

    /// The owner dictates in English and Russian, has an Armenian keyboard,
    /// and Parakeet installed: out of credit, Parakeet transcribes at once.
    private static func theOwnersMacPicksTheParakeetItHas() throws {
        let dictated = Array(repeating: "en", count: 22) + Array(repeating: "ru", count: 8)
        let reading = resolve(
            dictated: SpokenLanguages.dominantLanguages(dictated),
            preferred: ["en-AM", "hy-AM", "ru-AM"],
            keyboards: ["en", "hy", "ru"]
        )
        let parakeetLanguages: Set<String> = [
            "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
            "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
        ]
        let candidates = [
            DictationTakePolicy.LocalCandidate(
                id: "parakeet-tdt-v3", isInstalled: true, languageCodes: parakeetLanguages, sizeMB: 470, autoPickable: true
            ),
            DictationTakePolicy.LocalCandidate(
                id: "whisper-large-v3-turbo", isInstalled: false, languageCodes: nil, sizeMB: 632, autoPickable: true
            ),
        ]
        let picked = DictationTakePolicy.localFallback(
            candidates: candidates,
            failedModelID: "openai-gpt-transcribe",
            spokenLanguages: reading.languages,
            primaryLanguage: reading.primary,
            canDownload: true
        )
        try expect(
            picked == .ready(id: "parakeet-tdt-v3", coversLanguages: true),
            "{en, ru} dictations with an Armenian keyboard pick the installed Parakeet, got \(String(describing: picked))"
        )
    }

    @MainActor
    private static func theLiveReadingIsWellFormed() throws {
        let live = SpokenLanguages.current(recentDictations: [])
        try expect(
            live.languages.allSatisfy { SpokenLanguages.primarySubtag($0) == $0 },
            "this Mac's reading is primary subtags only: \(live.languages.sorted())"
        )
        try expect(
            live.primary.map { live.languages.contains($0) } ?? true,
            "the primary language is one of the set"
        )
        try expect(SpokenLanguages.current(recentDictations: []) == live, "a second reading comes from the cache, unchanged")
    }
}
