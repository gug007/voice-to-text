import Foundation

/// Multipart body construction for `POST /v1/audio/transcriptions`.
///
/// Lives outside `OpenAITranscriptionEngine` so the offline harness can assert on
/// the exact bytes without standing up the actor or a URLSession — the wire
/// format is the part that silently breaks, and it is the part no integration
/// test can cheaply cover.
nonisolated enum OpenAIRequestBuilder {
    /// - Parameters:
    ///   - language: singular `language` field. **Ignored** when `languages` is
    ///     non-empty — see the mutual-exclusion note below.
    ///   - languages: repeated `languages[]` fields, for the models that take the
    ///     plural form. Codes must already be validated
    ///     (`OpenAIModelCapabilities.validatedLanguageCode`).
    ///   - keywords: repeated `keywords[]` fields. Must already be sanitized
    ///     (`OpenAIModelCapabilities.sanitizedKeywords`) — one illegal character
    ///     rejects the entire request.
    static func makeMultipartBody(
        boundary: String,
        modelId: String,
        wav: Data,
        language: String?,
        prompt: String?,
        responseFormat: String = "json",
        chunkingStrategy: String? = nil,
        languages: [String] = [],
        keywords: [String] = [],
        knownSpeakerNames: [String] = [],
        knownSpeakerReferences: [String] = []
    ) -> Data {
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }

        appendField("model", modelId)
        appendField("response_format", responseFormat)
        if let chunkingStrategy, !chunkingStrategy.isEmpty {
            appendField("chunking_strategy", chunkingStrategy)
        }
        // "`languages` replaces the singular `language` field. Don't send both."
        // The failure mode for sending both is undocumented, so the exclusion is
        // enforced here rather than at each call site — a caller that passes both
        // gets the plural form, never a request that might 400.
        if languages.isEmpty {
            if let language, !language.isEmpty {
                appendField("language", language)
            }
        } else {
            for code in languages {
                appendField("languages[]", code)
            }
        }
        if let prompt, !prompt.isEmpty {
            appendField("prompt", prompt)
        }
        for keyword in keywords {
            appendField("keywords[]", keyword)
        }
        for name in knownSpeakerNames {
            appendField("known_speaker_names[]", name)
        }
        for reference in knownSpeakerReferences {
            appendField("known_speaker_references[]", reference)
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n".utf8))

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
