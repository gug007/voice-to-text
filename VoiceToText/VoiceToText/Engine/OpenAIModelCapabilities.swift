import Foundation

/// Per-model wire differences for the transcription models behind OpenAI's
/// API shape — OpenAI's own, and the Whisper models Groq serves on the same
/// `/audio/transcriptions` contract — in one place.
///
/// The batch and realtime engines used to branch on bare `modelId == "…"` string
/// equalities scattered across two files. Each new model added another clause to
/// every one of them, and a missed clause is not a degraded transcription — it is
/// a 400 or a rejected session, because these models *reject* fields they don't
/// support rather than ignoring them. Adding a model should mean adding one arm
/// to `forModel` and nothing else.
///
/// Foundation-only and `nonisolated` so the offline harness can compile it
/// standalone (see `Tests/OpenAIRequestBuilderHarness.swift`).
nonisolated struct OpenAIModelCapabilities: Sendable {
    /// `prompt` on the batch `/v1/audio/transcriptions` request. Rejected
    /// outright by the diarizing model and by `gpt-realtime-whisper`, not merely
    /// ignored.
    let supportsPrompt: Bool
    /// Whether to put `prompt` inside a realtime `session.update`.
    ///
    /// Deliberately narrower than `supportsPrompt`: the realtime engine never
    /// sent a `prompt` before July 2026, and a rejected `session.update` costs
    /// the whole take (the fallback ladder recovers by dropping to no-VAD, which
    /// kills live partials). So only the models added *with* that wiring opt in;
    /// the pre-existing realtime models keep the exact payload they shipped with.
    let sendsRealtimePrompt: Bool
    /// `keywords` / `keywords[]` — biasing hints for names and jargon. Only the
    /// July 2026 models accept the field at all.
    let supportsKeywords: Bool
    /// These models take `languages` (array) *instead of* the singular
    /// `language`; the docs say don't send both.
    let usesPluralLanguages: Bool
    /// Speaker-diarizing model — a different `response_format`, no `prompt`
    /// support, and cross-request speaker pinning.
    let isDiarize: Bool
    /// Realtime models that do not support VAD turn detection: the config must
    /// omit `turn_detection` and audio only transcribes after an explicit
    /// `input_audio_buffer.commit`.
    let realtimeUsesManualCommit: Bool
    /// `response_format` for the batch `/v1/audio/transcriptions` request.
    let batchResponseFormat: String
    /// Send the singular `language` only when `validatedLanguageCode` accepts
    /// it, and leave the server to auto-detect otherwise. Off for OpenAI's
    /// models, which have always been sent the raw `decoder.language`; on for
    /// Groq's, which are new to the app, so no existing setting depends on a
    /// malformed code still reaching them.
    let validatesLanguage: Bool
    /// UTF-8 byte budget for `prompt`, spent by `byteBudgetedPrompt`. nil for
    /// OpenAI's models, which keep their character clamp (or none) — see
    /// `combinedPrompt`.
    let promptByteLimit: Int?

    static func forModel(_ backendModelId: String) -> OpenAIModelCapabilities {
        switch backendModelId {
        case "gpt-transcribe":
            // Batch-only in this app. It *can* run in a realtime session, but
            // there it emits nothing until an explicit commit — so if it is ever
            // registered on the `.openAIRealtime` backend, this arm needs
            // `realtimeUsesManualCommit: true` or the trailing utterance is lost.
            return OpenAIModelCapabilities(
                supportsPrompt: true,
                sendsRealtimePrompt: true,
                supportsKeywords: true,
                usesPluralLanguages: true,
                isDiarize: false,
                realtimeUsesManualCommit: false,
                batchResponseFormat: "json",
                validatesLanguage: false,
                promptByteLimit: nil
            )
        case "gpt-live-transcribe":
            // Supports server VAD: the realtime-VAD guide scopes the
            // "turn detection must be null" rule to `gpt-realtime-whisper` alone
            // and says VAD-capable models default to `server_vad`.
            return OpenAIModelCapabilities(
                supportsPrompt: true,
                sendsRealtimePrompt: true,
                supportsKeywords: true,
                usesPluralLanguages: true,
                isDiarize: false,
                realtimeUsesManualCommit: false,
                batchResponseFormat: "json",
                validatesLanguage: false,
                promptByteLimit: nil
            )
        case "gpt-4o-transcribe-diarize":
            return OpenAIModelCapabilities(
                supportsPrompt: false,
                sendsRealtimePrompt: false,
                supportsKeywords: false,
                usesPluralLanguages: false,
                isDiarize: true,
                realtimeUsesManualCommit: false,
                batchResponseFormat: "diarized_json",
                validatesLanguage: false,
                promptByteLimit: nil
            )
        case "gpt-realtime-whisper":
            return OpenAIModelCapabilities(
                supportsPrompt: false,
                sendsRealtimePrompt: false,
                supportsKeywords: false,
                usesPluralLanguages: false,
                isDiarize: false,
                realtimeUsesManualCommit: true,
                batchResponseFormat: "json",
                validatesLanguage: false,
                promptByteLimit: nil
            )
        case "whisper-large-v3", "whisper-large-v3-turbo":
            // Groq's ids; no OpenAI model shares them. Groq takes the classic
            // Whisper request: `prompt`, a singular ISO-639-1 `language`, `json`,
            // and no `keywords`. Its reference documents `prompt` as "Limited to
            // 224 tokens" without saying whether more is truncated or refused,
            // so the prompt is held to a budget that fits either way.
            return OpenAIModelCapabilities(
                supportsPrompt: true,
                sendsRealtimePrompt: false,
                supportsKeywords: false,
                usesPluralLanguages: false,
                isDiarize: false,
                realtimeUsesManualCommit: false,
                batchResponseFormat: "json",
                validatesLanguage: true,
                promptByteLimit: groqPromptByteLimit
            )
        default:
            // gpt-4o-transcribe, gpt-4o-mini-transcribe, whisper-1 — and any
            // future id, which lands on the most conservative shape that still
            // matches every model shipped before July 2026.
            return OpenAIModelCapabilities(
                supportsPrompt: true,
                sendsRealtimePrompt: false,
                supportsKeywords: false,
                usesPluralLanguages: false,
                isDiarize: false,
                realtimeUsesManualCommit: false,
                batchResponseFormat: "json",
                validatesLanguage: false,
                promptByteLimit: nil
            )
        }
    }

    // MARK: - Batch request fields

    /// The singular `language` field, or nil to leave it out. The models on the
    /// plural form never get it (see `OpenAIRequestBuilder`); the ones that
    /// validate get a well-formed code or nothing; every other model keeps the
    /// raw value it has always been sent.
    func batchLanguage(_ raw: String?) -> String? {
        guard !usesPluralLanguages else { return nil }
        return validatesLanguage ? Self.validatedLanguageCode(raw) : raw
    }

    /// The `languages[]` values: the validated code for the models that take the
    /// plural form — which reject a malformed one outright — and none otherwise.
    func batchLanguages(_ raw: String?) -> [String] {
        guard usesPluralLanguages else { return [] }
        return [Self.validatedLanguageCode(raw)].compactMap { $0 }
    }

    /// The `prompt` to send — the user's standing prompt joined with the rolling
    /// context — or nil to send none.
    ///
    /// The clamp is scoped per model. An over-long `prompt` is documented as
    /// rejecting the whole request only on the models that take `languages`, so
    /// they get the character clamp; the older OpenAI models have always sent the
    /// full concatenation, and clamping them would silently truncate a long user
    /// glossary that used to reach the API. Groq's models get their byte budget.
    func batchPrompt(initial: String?, context: String?) -> String? {
        guard supportsPrompt else { return nil }
        if let promptByteLimit {
            return Self.byteBudgetedPrompt(initial: initial, context: context, byteLimit: promptByteLimit)
        }
        return Self.combinedPrompt(
            initial: initial,
            context: context,
            limit: usesPluralLanguages ? Self.promptCharacterLimit : nil
        )
    }

    // MARK: - Request-boundary sanitization

    /// Conservative `prompt` budget. The real limit is undocumented for every
    /// model except whisper-1, and an overrun rejects the whole request rather
    /// than truncating — so clamp well below any plausible ceiling.
    static let promptCharacterLimit = 900

    /// Upper bounds on `keywords`. Both are guesses: no limit is published, and
    /// an overrun is request-fatal.
    static let keywordCharacterLimit = 100
    static let keywordCountLimit = 32

    /// Cleans a user-supplied keyword list into something the API cannot reject.
    ///
    /// The API "rejects the entire request when it encounters" `<`, `>`, CR or LF
    /// in *any* keyword — so one stray character in a `UserDefaults` CSV would
    /// fail every transcription until the user found and fixed it. Keywords are
    /// only a hint, so the failure mode must be "fewer/cleaner keywords", never
    /// "no transcript": everything here scrubs rather than rejects, and the
    /// function is total.
    static func sanitizedKeywords(from raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for candidate in raw {
            var scrubbed = ""
            scrubbed.reserveCapacity(candidate.count)
            for scalar in candidate.unicodeScalars {
                if scalar == "<" || scalar == ">" {
                    continue
                }
                // CR/LF/tab and friends become a space rather than vanishing, so
                // a pasted two-line keyword stays two words instead of fusing.
                if CharacterSet.controlCharacters.contains(scalar) {
                    scrubbed.unicodeScalars.append(" ")
                } else {
                    scrubbed.unicodeScalars.append(scalar)
                }
            }
            let collapsed = scrubbed
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            guard !collapsed.isEmpty else { continue }
            let clipped = String(collapsed.prefix(keywordCharacterLimit))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clipped.isEmpty, seen.insert(clipped).inserted else { continue }
            result.append(clipped)
            if result.count == keywordCountLimit { break }
        }
        return result
    }

    /// Returns `raw` as a lowercased ISO 639-1 code, or nil if it isn't one.
    ///
    /// `decoder.language` is free-form `UserDefaults` text with no in-app writer.
    /// For the models that take `languages`, "The API rejects unsupported or
    /// incorrectly formatted language codes" — so a value that used to be a bad
    /// hint is now a hard 400. The guide accepts a wider set (ISO 639-3, regional
    /// `zh` locales) than the API reference's flat "ISO-639-1", so we send only
    /// the intersection; anything else is dropped and the server auto-detects,
    /// which is strictly better than failing the request.
    static func validatedLanguageCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Length-first: this is what rejects "eng"/"en-US"/"zh-cn" before they
        // reach a table that happens to contain some three-letter subtags.
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        guard Locale.LanguageCode.isoLanguageCodes.contains(where: { $0.identifier == code }) else {
            return nil
        }
        return code
    }

    /// nil for nil/empty input, otherwise `text` truncated to `limit` characters.
    /// A nil `limit` means "no clamp" — see `combinedPrompt`.
    static func clampedPrompt(_ text: String?, limit: Int? = promptCharacterLimit) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let limit, text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    /// Joins the user's standing prompt with rolling/caller context inside the
    /// clamp budget, spending it on `context` first.
    ///
    /// `decoder.initialPrompt` is unbounded user text while `context` is the tail
    /// of what was just transcribed — the part that keeps punctuation and proper
    /// nouns consistent across a chunk or session boundary. Truncating the user's
    /// half first means a long standing prompt degrades the hint instead of
    /// silently destroying cross-chunk continuity.
    ///
    /// Pass `limit: nil` for the models that were shipping before this clamp
    /// existed: an overrun is only *known* to be request-fatal on the models that
    /// take `languages`, and whisper-1 in particular truncates server-side. For
    /// those, clamping here would silently drop glossary text that used to reach
    /// the API — a regression, not a safeguard.
    static func combinedPrompt(
        initial: String?,
        context: String?,
        limit: Int? = promptCharacterLimit
    ) -> String? {
        let context = clampedPrompt(context, limit: limit)
        guard let initial = clampedPrompt(initial, limit: limit) else { return context }
        guard let context else { return initial }
        guard let limit else { return initial + " " + context }
        let budget = limit - context.count - 1 // -1 for the joining space
        guard budget > 0 else { return context }
        return String(initial.prefix(budget)) + " " + context
    }

    /// Groq's `prompt` budget in UTF-8 bytes, standing in for its documented
    /// 224 Whisper tokens. Whisper's tokenizer is byte-level BPE, so bytes bound
    /// tokens where characters can't: English runs about four bytes a token
    /// (~112 tokens here), and CJK's three bytes a character keep 150 characters
    /// near the ceiling even at one and a half tokens each. Whether Groq
    /// truncates or refuses a longer prompt is undocumented, so this stays under
    /// the limit rather than finding out.
    static let groqPromptByteLimit = 450

    /// Joins the user's standing prompt with the rolling context inside a UTF-8
    /// byte budget, spending it on `context` first — the same priority as
    /// `combinedPrompt`, for the same reason.
    ///
    /// What survives of each half is the part that matters: the *end* of
    /// `context`, the words nearest the chunk boundary, and the *start* of
    /// `initial`, where a user puts what counts. Cuts fall between `Character`s,
    /// so no grapheme cluster — an accented letter, an emoji sequence, a UTF-8
    /// scalar — is ever split; a half reduced to nothing is dropped, never sent
    /// as an empty or dangling field. Context ends up last either way, which is
    /// also the part a server that truncates from the front would keep.
    static func byteBudgetedPrompt(initial: String?, context: String?, byteLimit: Int) -> String? {
        let context = context.flatMap { suffix(of: $0, maxUTF8Bytes: byteLimit) }
        guard let context else {
            return initial.flatMap { prefix(of: $0, maxUTF8Bytes: byteLimit) }
        }
        let remaining = byteLimit - context.utf8.count - 1 // -1 for the joining space
        guard let initial = initial.flatMap({ prefix(of: $0, maxUTF8Bytes: remaining) }) else {
            return context
        }
        return initial + " " + context
    }

    /// The longest leading run of whole `Character`s within `maxUTF8Bytes`, or
    /// nil when that is nothing.
    private static func prefix(of text: String, maxUTF8Bytes: Int) -> String? {
        var bytes = 0
        var end = text.startIndex
        while end < text.endIndex {
            let next = text.index(after: end)
            bytes += text[end..<next].utf8.count
            guard bytes <= maxUTF8Bytes else { break }
            end = next
        }
        return end == text.startIndex ? nil : String(text[..<end])
    }

    /// The longest trailing run of whole `Character`s within `maxUTF8Bytes`, or
    /// nil when that is nothing.
    private static func suffix(of text: String, maxUTF8Bytes: Int) -> String? {
        var bytes = 0
        var start = text.endIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            bytes += text[previous..<start].utf8.count
            guard bytes <= maxUTF8Bytes else { break }
            start = previous
        }
        return start == text.endIndex ? nil : String(text[start...])
    }
}
