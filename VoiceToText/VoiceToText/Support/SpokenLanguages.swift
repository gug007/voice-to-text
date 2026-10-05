import Carbon.HIToolbox
import Foundation
import NaturalLanguage

/// The languages this user plausibly dictates in, as lowercase ISO 639
/// codes — what decides which model on this Mac a refused cloud take is
/// offered to (`DictationTakePolicy.localFallback`).
///
/// A failed take has no transcript to detect a language from, and the cloud
/// never answered, so the signal comes from around it, best first. A
/// `decoder.language` default, when set, is the user saying outright what
/// they speak, and is the only answer. Next, what they have actually
/// dictated: the languages of their recent dictations in History. Only when
/// History has too little to go on, the Mac's settings — the languages macOS
/// is set to show and the ones the user has keyboards for. Those are a guess
/// that over-counts: an Armenian keyboard kept for the odd message, or a
/// second menu language, says little about what someone dictates, so a guess
/// also names the one language it is sure of (`Reading.primary`), and the
/// policy keeps a model on this Mac that knows it ahead of a download.
nonisolated enum SpokenLanguages {
    /// `UserDefaults` key the engines read as their forced language
    /// (`TranscriptionDecoderOptions.language`).
    static let overrideDefaultsKey = "decoder.language"

    /// How many of the most recent dictations with a real transcript are read.
    /// Enough for a second language used now and then to show, recent enough
    /// to follow a user who has moved on from one.
    static let recentDictationsRead = 30
    /// Below this many characters a transcript says too little about its
    /// language — "OK, thanks" reads as half the languages that use Latin
    /// script — and is skipped.
    static let minimumDetectedCharacters = 20
    /// The recognizer's probability a transcript's language needs to count.
    static let minimumConfidence = 0.5
    /// Fewer usable dictations than this is no signal: the Mac's settings
    /// answer instead.
    static let minimumDetections = 3
    /// The share of usable dictations a language needs to count as one the
    /// user dictates in — and never fewer than `minimumDetectionsPerLanguage`,
    /// so one misread transcript can't add a language.
    static let minimumShare = 0.1
    static let minimumDetectionsPerLanguage = 2

    /// The languages, and how far to trust them.
    struct Reading: Equatable, Sendable {
        /// Every language the user is taken to dictate in. Empty when nothing
        /// is known, which the policy reads as covered.
        let languages: Set<String>
        /// The one language a guess from the Mac's settings is sure of — the
        /// first preferred language. nil when the user said (the override) or
        /// showed (History) what they dictate: then every language counts.
        let primary: String?
    }

    /// One recent dictation, as History holds it. `id` keys the detection
    /// cache, so each transcript is only read once.
    struct Dictation: Sendable {
        let id: UUID
        let text: String
    }

    /// The reading for this Mac right now, from the user's most recent
    /// dictations (newest first, real transcripts only, at most
    /// `recentDictationsRead`). Main actor because the Text Input Sources API
    /// is only safe there. Cheap enough to ask from a view's body: each
    /// transcript's language is detected once and kept, and the keyboards
    /// are read once and kept until the user changes them.
    @MainActor
    static func current(recentDictations: [Dictation]) -> Reading {
        let override = UserDefaults.standard.string(forKey: overrideDefaultsKey)
        let isOverridden = override.flatMap(primarySubtag) != nil
        let dictated = isOverridden ? [] : dominantLanguages(detectedLanguages(in: recentDictations))
        let needsSettings = !isOverridden && dictated.isEmpty
        return resolve(
            override: override,
            dictatedLanguages: dictated,
            preferredLanguages: needsSettings ? Locale.preferredLanguages : [],
            inputSourceLanguages: needsSettings ? enabledInputSourceLanguages() : []
        )
    }

    /// The pure rule behind `current()`: a valid override alone; else the
    /// languages the user dictates in (`dominantLanguages`); else the union of
    /// the preferred languages and the input sources' languages, with the
    /// first preferred language as the one a guess is sure of. Each is reduced
    /// to its primary subtag ("zh-Hans-CN" → "zh"). An override that isn't a
    /// language code is ignored rather than trusted — the engines drop it the
    /// same way — so a typo can't empty the set.
    static func resolve(
        override: String?,
        dictatedLanguages: Set<String>,
        preferredLanguages: [String],
        inputSourceLanguages: [String]
    ) -> Reading {
        if let forced = override.flatMap(primarySubtag) {
            return Reading(languages: [forced], primary: nil)
        }
        if !dictatedLanguages.isEmpty {
            return Reading(languages: dictatedLanguages, primary: nil)
        }
        let preferred = preferredLanguages.compactMap(primarySubtag)
        return Reading(
            languages: Set(preferred + inputSourceLanguages.compactMap(primarySubtag)),
            primary: preferred.first
        )
    }

    /// The languages a user dictates in, from the language detected in each
    /// of their recent dictations: every one seen in at least `minimumShare`
    /// of them, and at least `minimumDetectionsPerLanguage` times. Empty —
    /// no signal — with fewer than `minimumDetections` to go on.
    static func dominantLanguages(_ detected: [String]) -> Set<String> {
        guard detected.count >= minimumDetections else { return [] }
        let counts = Dictionary(detected.map { ($0, 1) }, uniquingKeysWith: +)
        let needed = max(
            minimumDetectionsPerLanguage,
            Int((Double(detected.count) * minimumShare).rounded(.up))
        )
        return Set(counts.filter { $0.value >= needed }.keys)
    }

    /// The language a transcript is written in, as a primary subtag, or nil
    /// when it is too short or the recognizer isn't sure.
    static func detectedLanguage(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumDetectedCharacters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              best.key != .undetermined,
              best.value >= minimumConfidence else {
            return nil
        }
        return primarySubtag(best.key.rawValue)
    }

    /// Each transcript's detected language, by id, with the length it was
    /// read at — a transcript regenerated since is read again. Holds only the
    /// last window asked about.
    @MainActor
    private static var detections: [UUID: (length: Int, language: String?)] = [:]

    @MainActor
    private static func detectedLanguages(in dictations: [Dictation]) -> [String] {
        var window: [UUID: (length: Int, language: String?)] = [:]
        let languages = dictations.compactMap { dictation -> String? in
            let length = dictation.text.utf8.count
            let language: String?
            if let cached = detections[dictation.id], cached.length == length {
                language = cached.language
            } else {
                language = detectedLanguage(of: dictation.text)
            }
            window[dictation.id] = (length, language)
            return language
        }
        detections = window
        return languages
    }

    /// The language part of a BCP 47 tag or a locale identifier, lowercased:
    /// "en-US" → "en", "pt_BR" → "pt", "yue-Hant" → "yue". nil for anything
    /// that isn't two or three ASCII letters.
    static func primarySubtag(_ identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first else {
            return nil
        }
        let code = first.lowercased()
        guard (2...3).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }
        return code
    }

    /// `enabledInputSourceLanguages()` as last read, until the user enables
    /// or removes a keyboard.
    @MainActor
    private static var cachedInputSourceLanguages: [String]?
    @MainActor
    private static var observesInputSourceChanges = false

    /// The intended language of each enabled keyboard layout and input mode.
    /// A source lists every language it can type, but only the first is the
    /// one it is for — the U.S. layout can type French, which says nothing
    /// about whether its owner speaks it. Empty if the API returns nothing,
    /// which leaves the preferred languages to answer alone. Kept until the
    /// system says the enabled sources changed.
    @MainActor
    private static func enabledInputSourceLanguages() -> [String] {
        if let cachedInputSourceLanguages { return cachedInputSourceLanguages }
        if !observesInputSourceChanges {
            observesInputSourceChanges = true
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { cachedInputSourceLanguages = nil }
            }
        }
        let languages = readInputSourceLanguages()
        cachedInputSourceLanguages = languages
        return languages
    }

    @MainActor
    private static func readInputSourceLanguages() -> [String] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard isSelectable(source),
                  let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
                return nil
            }
            let languages = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String]
            return languages?.first
        }
    }

    /// Only sources the user can switch to: an input method's container
    /// (Japanese's, say) is listed beside its modes but isn't one.
    @MainActor
    private static func isSelectable(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
