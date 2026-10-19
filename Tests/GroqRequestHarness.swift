import Foundation

/// Groq serves Whisper behind OpenAI's `/audio/transcriptions` contract, so it
/// rides `OpenAITranscriptionEngine` and differs only where the capability
/// table says. These pin those differences — the language check and the byte
/// budget on `prompt` — prove OpenAI's own models kept the exact request they
/// had, and hold the chunker to Groq's upload limit.

struct GroqRequestHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw GroqRequestHarnessFailure(description: message)
    }
}

private let groqModels = ["whisper-large-v3", "whisper-large-v3-turbo"]
private let budget = OpenAIModelCapabilities.groqPromptByteLimit
private let boundary = "Boundary-TEST"

private func prompt(_ initial: String?, _ context: String?, limit: Int = budget) -> String? {
    OpenAIModelCapabilities.byteBudgetedPrompt(initial: initial, context: context, byteLimit: limit)
}

private func body(modelId: String, language: String?, prompt: String?, wav: Data = Data("WAVBYTES".utf8)) -> Data {
    let caps = OpenAIModelCapabilities.forModel(modelId)
    return OpenAIRequestBuilder.makeMultipartBody(
        boundary: boundary,
        modelId: modelId,
        wav: wav,
        language: caps.batchLanguage(language),
        prompt: caps.batchPrompt(initial: prompt, context: nil),
        responseFormat: caps.batchResponseFormat,
        languages: caps.batchLanguages(language),
        keywords: caps.supportsKeywords ? ["kw"] : []
    )
}

private func partValues(_ body: Data, name: String) -> [String] {
    let text = String(decoding: body, as: UTF8.self)
    let needle = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
    return text.components(separatedBy: needle)
        .dropFirst()
        .compactMap { $0.components(separatedBy: "\r\n--\(boundary)").first }
}

/// A small deterministic generator, so the property check below covers the
/// same strings on every run.
private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] }
}

@main
struct GroqRequestHarness {
    static func main() throws {
        try groqArmsTakeTheClassicWhisperRequest()
        try groqLanguageIsValidatedOpenAIsIsNot()
        try groqRequestBodyShape()
        try emptyInputsSendNoPrompt()
        try contextIsSpentFirstAndKeepsItsEnd()
        try initialPromptKeepsItsStart()
        try multiByteScriptsFillTheBudgetWithWholeCharacters()
        try graphemeClustersAreNeverSplit()
        try anOversizedClusterIsDroppedNotSent()
        try everyResultFitsAndIsMadeOfWholePieces()
        try openAIModelsKeepTheirPrompt()
        try largestChunkFitsGroqUploadLimit()
        print("Groq request harness passed")
    }

    // MARK: - Capabilities

    private static func groqArmsTakeTheClassicWhisperRequest() throws {
        for id in groqModels {
            let caps = OpenAIModelCapabilities.forModel(id)
            try expect(caps.supportsPrompt, "\(id) takes prompt")
            try expect(!caps.supportsKeywords, "\(id) takes no keywords")
            try expect(!caps.usesPluralLanguages, "\(id) takes the singular language")
            try expect(!caps.isDiarize, "\(id) never reaches the diarize path")
            try expect(!caps.sendsRealtimePrompt && !caps.realtimeUsesManualCommit, "\(id) has no realtime behaviour")
            try expect(caps.batchResponseFormat == "json", "\(id) asks for json")
            try expect(caps.validatesLanguage, "\(id) validates its language")
            try expect(caps.promptByteLimit == budget, "\(id) carries the Groq prompt budget")
        }
        try expect(budget == 450, "the Groq budget is 450 bytes")

        // OpenAI's models — and the fallback for an unknown id — must not have
        // picked up either Groq behaviour.
        for id in ["gpt-transcribe", "gpt-live-transcribe", "gpt-4o-transcribe", "gpt-4o-mini-transcribe",
                   "gpt-4o-transcribe-diarize", "gpt-realtime-whisper", "whisper-1", "some-future-model"] {
            let caps = OpenAIModelCapabilities.forModel(id)
            try expect(!caps.validatesLanguage && caps.promptByteLimit == nil, "\(id) keeps OpenAI's behaviour")
        }
    }

    // A malformed code would likely be a 400 on Groq; dropped, it means
    // auto-detect. OpenAI's older models keep receiving the raw value.
    private static func groqLanguageIsValidatedOpenAIsIsNot() throws {
        for id in groqModels {
            let caps = OpenAIModelCapabilities.forModel(id)
            try expect(caps.batchLanguage("en") == "en", "\(id): en passes")
            try expect(caps.batchLanguage(" DE ") == "de", "\(id): trimmed and lowercased")
            try expect(caps.batchLanguage("en-US") == nil, "\(id): a regional tag is dropped")
            try expect(caps.batchLanguage("eng") == nil, "\(id): ISO 639-3 is dropped")
            try expect(caps.batchLanguage("zz") == nil, "\(id): a non-language is dropped")
            try expect(caps.batchLanguage("") == nil, "\(id): empty is dropped")
            try expect(caps.batchLanguage(nil) == nil, "\(id): nil stays nil")
            try expect(caps.batchLanguages("en").isEmpty, "\(id): never the plural form")
        }

        let whisper1 = OpenAIModelCapabilities.forModel("whisper-1")
        try expect(whisper1.batchLanguage("en-US") == "en-US", "whisper-1 still gets the raw value")
        try expect(whisper1.batchLanguage(nil) == nil, "whisper-1 with no language sends none")
        try expect(whisper1.batchLanguages("en").isEmpty, "whisper-1 never gets languages[]")

        let gptTranscribe = OpenAIModelCapabilities.forModel("gpt-transcribe")
        try expect(gptTranscribe.batchLanguage("en") == nil, "gpt-transcribe never gets the singular field")
        try expect(gptTranscribe.batchLanguages("EN") == ["en"], "gpt-transcribe gets the validated plural")
        try expect(gptTranscribe.batchLanguages("en-US").isEmpty, "gpt-transcribe drops a malformed code")
    }

    private static func groqRequestBodyShape() throws {
        let out = body(modelId: "whisper-large-v3-turbo", language: "en", prompt: "Groq, Whisper")
        try expect(partValues(out, name: "model") == ["whisper-large-v3-turbo"], "the model id is Groq's own")
        try expect(partValues(out, name: "response_format") == ["json"], "json response")
        try expect(partValues(out, name: "language") == ["en"], "one singular language part")
        try expect(partValues(out, name: "languages[]").isEmpty, "no plural languages")
        try expect(partValues(out, name: "keywords[]").isEmpty, "no keywords")
        try expect(partValues(out, name: "prompt") == ["Groq, Whisper"], "the prompt is sent")
        try expect(partValues(out, name: "temperature").isEmpty, "temperature is left at Groq's default")

        let regional = body(modelId: "whisper-large-v3", language: "en-US", prompt: nil)
        try expect(partValues(regional, name: "language").isEmpty, "a malformed code sends no language part")
        try expect(partValues(regional, name: "prompt").isEmpty, "no prompt, no part")
    }

    // MARK: - Byte budget

    private static func emptyInputsSendNoPrompt() throws {
        try expect(prompt(nil, nil) == nil, "nothing in, nothing out")
        try expect(prompt("", "") == nil, "empty strings are nothing")
        try expect(prompt("", "B") == "B", "an empty standing prompt adds no space")
        try expect(prompt("A", "") == "A", "an empty context adds no space")
        try expect(prompt("A", nil) == "A", "the standing prompt alone")
        try expect(prompt(nil, "B") == "B", "the context alone")
        try expect(prompt("A", "B") == "A B", "both join with one space")
        try expect(prompt("A", "B", limit: 0) == nil, "a zero budget sends nothing")
    }

    // The words nearest the chunk boundary carry punctuation and proper nouns
    // across it, so they are the last thing to go.
    private static func contextIsSpentFirstAndKeepsItsEnd() throws {
        let context = "START " + String(repeating: "lorem ipsum ", count: 60) + "Kubernetes END"
        let out = try require(prompt("Glossary: Groq", context))
        try expect(out.utf8.count <= budget, "fits the budget")
        try expect(out.hasSuffix("Kubernetes END"), "the end of the context survives")
        try expect(!out.contains("START"), "the start of an over-long context is what goes")
        try expect(!out.contains("Glossary"), "an over-budget context leaves no room for the standing prompt")
        try expect(out == String(context.suffix(budget)), "exactly the last 450 ASCII bytes")

        // Exactly full: no dangling space and no scrap of the standing prompt.
        let full = String(repeating: "c", count: budget)
        try expect(prompt("hello", full) == full, "a context that fills the budget is sent alone")
        try expect(prompt("hello", String(repeating: "c", count: budget - 1)) == String(repeating: "c", count: budget - 1),
                   "one byte left is all the joining space")
    }

    private static func initialPromptKeepsItsStart() throws {
        let initial = "BEGIN " + String(repeating: "x", count: 600) + " FINISH"
        let context = String(repeating: "c", count: 100)
        let out = try require(prompt(initial, context))
        try expect(out.utf8.count == budget, "the leftover budget is spent exactly")
        try expect(out.hasPrefix("BEGIN "), "the start of the standing prompt survives")
        try expect(!out.contains("FINISH"), "its end is what goes")
        try expect(out.hasSuffix(" " + context), "the whole context follows, after one space")
        try expect(out == String(initial.prefix(budget - 100 - 1)) + " " + context, "prefix + space + context")

        let short = prompt("Names: Ada, Grace.", "and then we shipped it")
        try expect(short == "Names: Ada, Grace. and then we shipped it", "under budget, nothing is cut")
    }

    // Cyrillic is 2 bytes a character, CJK 3: a budget that lands mid-character
    // stops before it.
    private static func multiByteScriptsFillTheBudgetWithWholeCharacters() throws {
        let cyrillic = String(repeating: "я", count: 300)
        try expect(prompt(nil, cyrillic) == String(repeating: "я", count: 225), "Cyrillic: 225 characters, 450 bytes")
        try expect(prompt(nil, cyrillic, limit: 451) == String(repeating: "я", count: 225), "an odd budget never takes half an я")
        try expect(prompt(cyrillic, nil, limit: 451) == String(repeating: "я", count: 225), "nor does the prefix side")

        let cjk = String(repeating: "漢", count: 200)
        try expect(prompt(nil, cjk) == String(repeating: "漢", count: 150), "CJK: 150 characters, 450 bytes")
        try expect(prompt(nil, cjk, limit: 452) == String(repeating: "漢", count: 150), "two spare bytes are left unspent")
        try expect(prompt(cjk, "上下文", limit: 100) == String(repeating: "漢", count: 30) + " 上下文",
                   "100 bytes: 9 of context, 1 space, 30 characters of prompt")
    }

    private static func graphemeClustersAreNeverSplit() throws {
        // A ZWJ family is one Character of 25 bytes; it sits just past the cut.
        let family = "👨‍👩‍👧‍👦"
        try expect(family.count == 1 && family.utf8.count == 25, "test fixture: one 25-byte cluster")
        let afterFamily = String(repeating: "x", count: 440)
        let suffixCut = try require(prompt(nil, family + afterFamily))
        try expect(suffixCut == afterFamily, "the family is dropped whole, not cut into scalars")
        try expect(suffixCut.unicodeScalars.allSatisfy(\.isASCII), "no stray ZWJ or emoji scalar")

        // A decomposed é: the combining accent is never left at the front.
        let decomposed = "e\u{301}"
        try expect(decomposed.count == 1 && decomposed.utf8.count == 3, "test fixture: one 3-byte cluster")
        let accentCut = try require(prompt(nil, decomposed + String(repeating: "x", count: 448)))
        try expect(accentCut == String(repeating: "x", count: 448), "the accent goes with its letter")
        try expect(accentCut.unicodeScalars.first != "\u{301}", "no orphaned combining mark")

        // Prefix side: a flag (two regional indicators, 8 bytes) at the cut.
        let flag = "🇺🇸"
        let initial = String(repeating: "x", count: 347) + flag + "tail"
        let context = String(repeating: "c", count: 100)
        let prefixCut = try require(prompt(initial, context))
        try expect(prefixCut == String(repeating: "x", count: 347) + " " + context, "the flag is dropped whole")
        try expect(!prefixCut.unicodeScalars.contains { (0x1F1E6...0x1F1FF).contains($0.value) }, "no half flag")

        // A skin-tone emoji that fits is kept whole.
        let thumbs = "👍🏽"
        let kept = try require(prompt(nil, String(repeating: "x", count: 442) + thumbs))
        try expect(kept.hasSuffix(thumbs) && kept.utf8.count == 450, "a cluster that fits is kept, modifier and all")
    }

    private static func anOversizedClusterIsDroppedNotSent() throws {
        let zalgo = "a" + String(repeating: "\u{301}", count: 10) // one Character, 21 bytes
        try expect(zalgo.count == 1, "test fixture: one cluster")
        try expect(prompt(nil, zalgo, limit: 10) == nil, "a context that can't fit even one cluster sends nothing")
        try expect(prompt("hi", zalgo, limit: 10) == "hi", "and leaves the whole budget to the standing prompt")
        try expect(prompt(zalgo, nil, limit: 10) == nil, "a standing prompt that can't fit sends nothing")
    }

    /// Over a spread of scripts and budgets: never past the budget, and always a
    /// whole-Character prefix of the standing prompt joined to a whole-Character
    /// suffix of the context — `String.hasPrefix`/`hasSuffix` compare by
    /// Character, so a split cluster fails them.
    private static func everyResultFitsAndIsMadeOfWholePieces() throws {
        var rng = SplitMix64(state: 0x6772_6F71)
        let alphabet = ["a", "Z", " ", ".", "я", "ж", "漢", "字", "é", "e\u{301}", "👍🏽", "🇯🇵", "👨‍👩‍👧", "ß", "\u{0E01}\u{0E34}"]
        for _ in 0..<400 {
            func text() -> String? {
                let length = Int(rng.next() % 260)
                if length == 0 { return rng.next() % 2 == 0 ? nil : "" }
                return (0..<length).map { _ in rng.pick(alphabet) }.joined()
            }
            let initial = text()
            let context = text()
            let limit = Int(rng.next() % 520)
            guard let out = prompt(initial, context, limit: limit) else { continue }
            try expect(out.utf8.count <= limit, "\(out.utf8.count) bytes over a \(limit)-byte budget")

            let initialValue = initial ?? ""
            let contextValue = context ?? ""
            if contextValue.hasSuffix(out) || initialValue.hasPrefix(out) {
                continue // one half alone
            }
            // Otherwise "<prefix of initial> <suffix of context>": some split at a
            // space must satisfy both sides.
            let joined = out.indices.filter { out[$0] == " " }.contains { space in
                let head = String(out[..<space])
                let tail = String(out[out.index(after: space)...])
                return !head.isEmpty && !tail.isEmpty
                    && initialValue.hasPrefix(head) && contextValue.hasSuffix(tail)
            }
            try expect(joined, "result isn't whole pieces of its inputs: \(out.debugDescription)")
        }
    }

    // MARK: - OpenAI unchanged

    private static func openAIModelsKeepTheirPrompt() throws {
        let initial = String(repeating: "i", count: 1_000)
        let context = String(repeating: "c", count: 300)

        // The models that predate any clamp still send the full concatenation.
        for id in ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "some-future-model"] {
            let caps = OpenAIModelCapabilities.forModel(id)
            try expect(caps.batchPrompt(initial: initial, context: context) == initial + " " + context,
                       "\(id) sends the unclamped concatenation")
            try expect(caps.batchPrompt(initial: nil, context: nil) == nil, "\(id): nothing in, nothing out")
        }

        // The plural-`languages` model keeps its 900-character clamp.
        let gptTranscribe = OpenAIModelCapabilities.forModel("gpt-transcribe")
        let clamped = gptTranscribe.batchPrompt(initial: initial, context: context)
        try expect(clamped == OpenAIModelCapabilities.combinedPrompt(initial: initial, context: context),
                   "gpt-transcribe uses the character clamp")
        try expect(clamped?.count == OpenAIModelCapabilities.promptCharacterLimit, "and fills it to 900")

        for id in ["gpt-4o-transcribe-diarize", "gpt-realtime-whisper"] {
            try expect(OpenAIModelCapabilities.forModel(id).batchPrompt(initial: initial, context: context) == nil,
                       "\(id) still sends no prompt")
        }

        for id in groqModels {
            try expect(OpenAIModelCapabilities.forModel(id).batchPrompt(initial: initial, context: context)
                == prompt(initial, context), "\(id) uses the byte budget")
        }
    }

    // MARK: - Upload size

    /// Groq's free tier caps an upload at 25 MB. The chunker never splits a
    /// take of up to `minSplitThresholdSeconds`, and a split chunk runs at most
    /// `targetChunkSeconds` plus the silence search window — so the larger of
    /// the two is the longest chunk that can ever be sent. A chunker change that
    /// pushes it past the limit has to fail here, not on a user's meeting.
    private static func largestChunkFitsGroqUploadLimit() throws {
        let sampleRate = 16_000
        let groqUploadLimit = 25_000_000
        let longestChunkSeconds = max(
            AudioChunker.minSplitThresholdSeconds,
            AudioChunker.targetChunkSeconds + AudioChunker.silenceSearchWindowSeconds
        )
        let longestWAV = WAVEncoder.headerSize + Int(longestChunkSeconds * Double(sampleRate)) * 2
        try expect(longestWAV < groqUploadLimit, "the longest chunk's WAV (\(longestWAV) bytes) fits 25 MB")

        // The unsplit worst case, as the engine would actually send it: the
        // whole multipart body, with a full-budget prompt and a language.
        let unsplit = [Float](repeating: 0.25, count: Int(AudioChunker.minSplitThresholdSeconds) * sampleRate)
        let single = AudioChunker.split(samples: unsplit, sampleRate: sampleRate)
        try expect(single.count == 1, "a take at the threshold is not split")
        let wav = WAVEncoder.encode(samples: single[0], sampleRate: sampleRate)
        try expect(wav.count == longestWAV, "the threshold take is the longest chunk")
        let fullPrompt = String(repeating: "漢", count: 150)
        let request = body(modelId: "whisper-large-v3-turbo", language: "en", prompt: fullPrompt, wav: wav)
        try expect(request.count < groqUploadLimit, "the whole request (\(request.count) bytes) fits 25 MB")

        // The split worst case: the only quiet window sits at the far end of
        // the first cut's search range, so that chunk runs the full 615 s.
        let totalSeconds = 1_300
        var long = [Float](repeating: 0.5, count: totalSeconds * sampleRate)
        let farEnd = Int((AudioChunker.targetChunkSeconds + AudioChunker.silenceSearchWindowSeconds) * Double(sampleRate))
        let quiet = Int(AudioChunker.silenceWindowSeconds * Double(sampleRate))
        for index in (farEnd - quiet)..<farEnd { long[index] = 0 }
        let chunks = AudioChunker.split(samples: long, sampleRate: sampleRate)
        try expect(chunks.count > 1, "a long take is split")
        try expect(chunks[0].count == farEnd, "the first cut lands at the far end of its search window")
        for chunk in chunks {
            try expect(Double(chunk.count) <= longestChunkSeconds * Double(sampleRate), "no split chunk outruns the bound")
            try expect(WAVEncoder.headerSize + chunk.count * 2 < groqUploadLimit, "every split chunk fits 25 MB")
        }
    }

    private static func require(_ value: String?, _ message: String = "expected a prompt") throws -> String {
        guard let value else { throw GroqRequestHarnessFailure(description: message) }
        return value
    }
}
