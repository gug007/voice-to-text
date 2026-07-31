import Foundation

struct OpenAIRequestBuilderHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw OpenAIRequestBuilderHarnessFailure(description: message)
    }
}

/// Stand-in for the WAV payload — the builder treats it as opaque bytes, and a
/// short recognizable marker makes a mis-ordered body obvious.
private let wav = Data("WAVBYTES".utf8)
private let boundary = "Boundary-TEST"

private func body(
    modelId: String,
    language: String? = nil,
    prompt: String? = nil,
    responseFormat: String = "json",
    chunkingStrategy: String? = nil,
    languages: [String] = [],
    keywords: [String] = [],
    knownSpeakerNames: [String] = [],
    knownSpeakerReferences: [String] = []
) -> String {
    let data = OpenAIRequestBuilder.makeMultipartBody(
        boundary: boundary,
        modelId: modelId,
        wav: wav,
        language: language,
        prompt: prompt,
        responseFormat: responseFormat,
        chunkingStrategy: chunkingStrategy,
        languages: languages,
        keywords: keywords,
        knownSpeakerNames: knownSpeakerNames,
        knownSpeakerReferences: knownSpeakerReferences
    )
    return String(decoding: data, as: UTF8.self)
}

private func partCount(_ body: String, name: String) -> Int {
    let needle = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
    return body.components(separatedBy: needle).count - 1
}

/// Value of the first part named `name`, or nil if there is none.
private func partValue(_ body: String, name: String) -> String? {
    partValues(body, name: name).first
}

private func partValues(_ body: String, name: String) -> [String] {
    let needle = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
    return body.components(separatedBy: needle)
        .dropFirst()
        .compactMap { $0.components(separatedBy: "\r\n--\(boundary)").first }
}

@main
struct OpenAIRequestBuilderHarness {
    static func main() throws {
        try pluralLanguagesReplaceSingularLanguage()
        try legacyModelKeepsSingularLanguage()
        try keywordsEmitOneBracketedPartEach()
        try illegalKeywordsAreScrubbedNotFatal()
        try transcribeBodyHasNoDiarizeOnlyFields()
        try diarizeBodyIsUnchanged()
        try languageCodeValidation()
        try promptClamping()
        try combinedPromptPreservesRollingContext()
        try capabilityLookupCoversEveryModel()
        print("OpenAI request builder harness passed")
    }

    // 1. `languages` replaces the singular `language` — sending both is
    // documented as unsupported, so the builder must never emit both.
    private static func pluralLanguagesReplaceSingularLanguage() throws {
        let out = body(modelId: "gpt-transcribe", language: "en", languages: ["en"])
        try expect(partCount(out, name: "languages[]") == 1, "gpt-transcribe emits exactly one languages[] part")
        try expect(partCount(out, name: "language") == 0, "gpt-transcribe never emits the singular language field")
        try expect(partValue(out, name: "languages[]") == "en", "the validated code is sent verbatim")

        // The exclusion is structural: a caller passing both still gets only the
        // plural form, so no call site can produce a both-fields request.
        let bothWithConflict = body(modelId: "gpt-transcribe", language: "de", languages: ["fr", "en"])
        try expect(partCount(bothWithConflict, name: "language") == 0, "singular language is dropped, not merged")
        try expect(
            partValues(bothWithConflict, name: "languages[]") == ["fr", "en"],
            "every languages[] entry is emitted in order"
        )
    }

    // 2. Every pre-July-2026 model keeps the singular field exactly as before.
    private static func legacyModelKeepsSingularLanguage() throws {
        let out = body(modelId: "gpt-4o-transcribe", language: "en")
        try expect(partCount(out, name: "language") == 1, "gpt-4o-transcribe emits exactly one language part")
        try expect(partCount(out, name: "languages[]") == 0, "gpt-4o-transcribe emits no languages[] parts")
        try expect(partValue(out, name: "language") == "en", "the language value round-trips")
    }

    // 3. Bracketed repeated fields, one part per keyword, values sent raw.
    private static func keywordsEmitOneBracketedPartEach() throws {
        let keywords = OpenAIModelCapabilities.sanitizedKeywords(
            from: ["premium plan", "AC-42", "billing"]
        )
        let out = body(modelId: "gpt-transcribe", keywords: keywords)
        try expect(partCount(out, name: "keywords[]") == 3, "three keywords → three keywords[] parts")
        try expect(
            partValues(out, name: "keywords[]") == ["premium plan", "AC-42", "billing"],
            "keyword values keep their spaces and are not escaped"
        )
    }

    // 4. A bad keyword rejects the ENTIRE request server-side, so sanitization
    // has to degrade to fewer/cleaner keywords rather than to a failed take.
    private static func illegalKeywordsAreScrubbedNotFatal() throws {
        let cleaned = OpenAIModelCapabilities.sanitizedKeywords(
            from: ["<tag>ACME\r\nCorp</tag>", "   ", "<>", "\u{7}", "kept"]
        )
        try expect(cleaned == ["tagACME Corp/tag", "kept"], "angle brackets vanish, CR/LF become one space")
        try expect(!cleaned.contains { $0.contains("<") || $0.contains(">") }, "no keyword keeps < or >")
        try expect(
            !cleaned.contains { $0.contains("\r") || $0.contains("\n") },
            "no keyword keeps CR or LF"
        )

        let out = body(modelId: "gpt-transcribe", keywords: cleaned)
        try expect(partCount(out, name: "keywords[]") == 2, "all-junk keywords are dropped, survivors are sent")

        // Duplicates collapse and the list is capped, because both limits are
        // unpublished guesses and an overrun is request-fatal.
        let many = (0..<40).map { "kw\($0)" } + ["kw0"]
        let capped = OpenAIModelCapabilities.sanitizedKeywords(from: many)
        try expect(capped.count == 32, "the keyword list is capped at 32")
        try expect(capped.first == "kw0" && capped.last == "kw31", "the cap keeps the first 32 in order")

        let long = String(repeating: "x", count: 250)
        let clipped = OpenAIModelCapabilities.sanitizedKeywords(from: [long])
        try expect(clipped == [String(repeating: "x", count: 100)], "each keyword is truncated to 100 chars")

        let deduped = OpenAIModelCapabilities.sanitizedKeywords(from: ["one", "one ", "two"])
        try expect(deduped == ["one", "two"], "duplicates collapse, first-seen order preserved")
    }

    // 5. Both fields are documented only for the diarizing model.
    private static func transcribeBodyHasNoDiarizeOnlyFields() throws {
        let out = body(
            modelId: "gpt-transcribe",
            prompt: "context",
            languages: ["en"],
            keywords: ["AC-42"]
        )
        try expect(!out.contains("chunking_strategy"), "gpt-transcribe body carries no chunking_strategy")
        try expect(!out.contains("known_speaker_"), "gpt-transcribe body carries no known_speaker_* fields")
    }

    // 6. Regression guard: the diarize request is byte-identical to the shape
    // that shipped before the builder was extracted. Expected bytes are spelled
    // out here rather than snapshotted so a "fix" to the format has to be
    // deliberate.
    private static func diarizeBodyIsUnchanged() throws {
        let data = OpenAIRequestBuilder.makeMultipartBody(
            boundary: boundary,
            modelId: "gpt-4o-transcribe-diarize",
            wav: wav,
            language: "en",
            prompt: nil,
            responseFormat: "diarized_json",
            chunkingStrategy: "auto",
            knownSpeakerNames: ["Speaker 1"],
            knownSpeakerReferences: ["data:audio/wav;base64,AAAA"]
        )

        func field(_ name: String, _ value: String) -> String {
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }
        let expected =
            field("model", "gpt-4o-transcribe-diarize")
            + field("response_format", "diarized_json")
            + field("chunking_strategy", "auto")
            + field("language", "en")
            + field("known_speaker_names[]", "Speaker 1")
            + field("known_speaker_references[]", "data:audio/wav;base64,AAAA")
            + "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
            + "Content-Type: audio/wav\r\n\r\n"
            + "WAVBYTES\r\n"
            + "--\(boundary)--\r\n"

        try expect(data == Data(expected.utf8), "diarize body is byte-identical to the pre-extraction format")
    }

    // 7. Malformed codes are a hard reject on the plural-`languages` models, and
    // `decoder.language` is untrusted free-form UserDefaults text.
    private static func languageCodeValidation() throws {
        try expect(OpenAIModelCapabilities.validatedLanguageCode("en") == "en", "\"en\" passes through")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("EN") == "en", "\"EN\" lowercases to \"en\"")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("  fr ") == "fr", "surrounding whitespace is trimmed")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("en-US") == nil, "regional tags are rejected")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("eng") == nil, "ISO 639-3 codes are rejected")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("zh-cn") == nil, "zh locales are rejected")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("") == nil, "empty is rejected")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("zz") == nil, "a 2-letter non-language is rejected")
        try expect(OpenAIModelCapabilities.validatedLanguageCode("e1") == nil, "digits are rejected")
        try expect(OpenAIModelCapabilities.validatedLanguageCode(nil) == nil, "nil stays nil")
    }

    // 8. An over-long prompt rejects the whole request, so the clamp is total.
    private static func promptClamping() throws {
        try expect(OpenAIModelCapabilities.clampedPrompt(nil) == nil, "nil prompt stays nil")
        try expect(OpenAIModelCapabilities.clampedPrompt("") == nil, "empty prompt becomes nil")
        try expect(OpenAIModelCapabilities.clampedPrompt("hi") == "hi", "a short prompt is untouched")

        let long = String(repeating: "p", count: 1_500)
        let clamped = OpenAIModelCapabilities.clampedPrompt(long)
        try expect(clamped?.count == OpenAIModelCapabilities.promptCharacterLimit, "a long prompt truncates to the limit")
        try expect(OpenAIModelCapabilities.clampedPrompt(long, limit: 5) == "ppppp", "an explicit limit is honored")
        try expect(
            OpenAIModelCapabilities.clampedPrompt(long, limit: nil) == long,
            "a nil limit leaves the prompt whole"
        )
    }

    // The rolling tail carries cross-chunk punctuation and proper-noun
    // continuity, so the user's unbounded standing prompt is what gives way.
    private static func combinedPromptPreservesRollingContext() throws {
        try expect(
            OpenAIModelCapabilities.combinedPrompt(initial: "A", context: "B") == "A B",
            "both halves join with a single space"
        )
        try expect(
            OpenAIModelCapabilities.combinedPrompt(initial: nil, context: "B") == "B",
            "context alone survives"
        )
        try expect(
            OpenAIModelCapabilities.combinedPrompt(initial: "A", context: nil) == "A",
            "the standing prompt alone survives"
        )
        try expect(
            OpenAIModelCapabilities.combinedPrompt(initial: nil, context: nil) == nil,
            "nothing in, nothing out"
        )

        let initial = String(repeating: "i", count: 400)
        let context = String(repeating: "c", count: 40)
        let combined = OpenAIModelCapabilities.combinedPrompt(initial: initial, context: context, limit: 50)
        try expect(combined?.count == 50, "the combined prompt fits the budget exactly")
        try expect(combined?.hasSuffix(context) == true, "the rolling tail survives intact; the user's prompt is cut")

        // Context alone can exceed the budget; it is clamped and wins outright.
        let hugeContext = String(repeating: "c", count: 200)
        let contextOnly = OpenAIModelCapabilities.combinedPrompt(initial: initial, context: hugeContext, limit: 50)
        try expect(contextOnly == String(repeating: "c", count: 50), "an over-budget context leaves no room for the prompt")

        // The models that predate the clamp must keep sending the whole
        // concatenation — truncating them would drop glossary text that used to
        // reach the API. `limit: nil` is what the batch engine passes for them.
        try expect(
            OpenAIModelCapabilities.combinedPrompt(initial: initial, context: context, limit: nil)
                == initial + " " + context,
            "a nil limit reproduces the pre-clamp concatenation exactly"
        )
    }

    // The whole point of the capability table: a new model is one arm, not a new
    // clause in every branch. Pin the axes that decide the wire format.
    private static func capabilityLookupCoversEveryModel() throws {
        let new = OpenAIModelCapabilities.forModel("gpt-transcribe")
        try expect(new.supportsKeywords && new.usesPluralLanguages && new.supportsPrompt,
                   "gpt-transcribe takes prompt, keywords and plural languages")
        try expect(new.sendsRealtimePrompt, "gpt-transcribe carries prompt if ever used in a realtime session")
        try expect(!new.isDiarize && new.batchResponseFormat == "json", "gpt-transcribe uses response_format=json")

        let live = OpenAIModelCapabilities.forModel("gpt-live-transcribe")
        try expect(live.supportsKeywords && live.usesPluralLanguages, "gpt-live-transcribe takes keywords + languages")
        try expect(!live.realtimeUsesManualCommit, "gpt-live-transcribe supports server VAD (auto-commit)")
        try expect(live.sendsRealtimePrompt, "gpt-live-transcribe carries prompt in session.update")

        let whisperRealtime = OpenAIModelCapabilities.forModel("gpt-realtime-whisper")
        try expect(whisperRealtime.realtimeUsesManualCommit, "gpt-realtime-whisper is the only manual-commit model")
        try expect(!whisperRealtime.supportsPrompt, "gpt-realtime-whisper rejects prompt")
        try expect(!whisperRealtime.sendsRealtimePrompt, "gpt-realtime-whisper session.update carries no prompt")

        let diarize = OpenAIModelCapabilities.forModel("gpt-4o-transcribe-diarize")
        try expect(diarize.isDiarize && diarize.batchResponseFormat == "diarized_json", "diarize keeps diarized_json")
        try expect(!diarize.supportsPrompt, "the diarize model rejects prompt")

        for legacy in ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1", "some-future-model"] {
            let caps = OpenAIModelCapabilities.forModel(legacy)
            try expect(
                caps.supportsPrompt && !caps.supportsKeywords && !caps.usesPluralLanguages
                    && !caps.isDiarize && !caps.realtimeUsesManualCommit && caps.batchResponseFormat == "json",
                "\(legacy) keeps the pre-July-2026 request shape"
            )
            // `gpt-4o-transcribe` also runs on the realtime backend. Its
            // `session.update` never carried a `prompt`, and adding one risks a
            // rejected update — which costs live partials for the whole take.
            try expect(
                !caps.sendsRealtimePrompt,
                "\(legacy) keeps its pre-July-2026 realtime session.update payload"
            )
        }
    }
}
