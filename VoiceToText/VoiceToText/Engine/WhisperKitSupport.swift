import Foundation

/// The files a local Whisper model folder must hold for `WhisperKitEngine` to
/// load it straight from disk, without asking Hugging Face first.
///
/// Taken from the vendored WhisperKit (0.17.0-3-gc71c5ed), not guessed:
/// `WhisperKit.loadModels` throws unless `MelSpectrogram`, `AudioEncoder` and
/// `TextDecoder` exist, each resolved by `ModelUtilities.detectModelURL` as a
/// compiled `.mlmodelc` bundle or, failing that, an `.mlpackage`'s
/// `Data/com.apple.CoreML/model.mlmodel`. `TextDecoderContextPrefill` is
/// optional. The folder's `config.json` and `generation_config.json` are never
/// read (a TODO in `Models.swift`).
///
/// The tokenizer isn't in this folder. `ModelUtilities.loadTokenizer` looks for
/// `tokenizer.json` (plus `tokenizer_config.json`) under the download base's
/// `models/openai/whisper-<size>` first and fetches it from the Hub only when
/// that's missing — which happens once, on the load right after the download —
/// so it can't be checked here without the model's size, which WhisperKit
/// only learns by loading it. A missing tokenizer offline makes that load
/// throw, and the engine falls back to the download path as before.
nonisolated enum WhisperKitModelFiles {
    static let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    static func hasRequiredModels(in folder: URL, fileManager: FileManager = .default) -> Bool {
        requiredModelNames.allSatisfy { name in
            let compiled = folder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            let package = folder.appendingPathComponent(
                "\(name).mlpackage/Data/com.apple.CoreML/model.mlmodel",
                isDirectory: false
            )
            return fileManager.fileExists(atPath: compiled.path)
                || fileManager.fileExists(atPath: package.path)
        }
    }
}

/// What `WhisperKitEngine` does with each decoded window of audio — each
/// ≤30 s chunk of a long buffer, or a short buffer whole.
///
/// WhisperKit's own `chunkingStrategy: .vad` path logs a chunk that threw at
/// debug level and drops it, so the transcript just comes back shorter. And at
/// this revision a decode with prompt tokens can end the moment the model
/// samples end-of-text during the prompt prefill (fixed upstream in
/// argmax-oss-swift 1.1.0), returning nothing for audio that has speech in it.
/// Neither may pass silently: a failed chunk gets one more pass on its own, and
/// an empty one that carried a prompt gets one more pass without it — but only
/// over speech energy, since an unprompted Whisper decode of silence is where
/// "Thank you." hallucinations come from.
nonisolated enum WhisperChunkCheck {
    enum Action: Equatable, Sendable {
        case accept(String)
        case retryWithoutPrompt
        case retry
    }

    /// `hasSpeech` is asked only for an empty prompted result.
    static func action(
        for outcome: Result<String, any Error>,
        prompted: Bool,
        hasSpeech: () -> Bool
    ) -> Action {
        switch outcome {
        case .failure:
            return .retry
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, prompted, hasSpeech() { return .retryWithoutPrompt }
            return .accept(trimmed)
        }
    }

    /// Chunk ranges that cover all `sampleCount` samples. `VADAudioChunker`
    /// stops once less than a second is left after its last cut (padding it
    /// keeps against end-of-clip hallucinations), so a word said in that last
    /// second never reached the decoder. The remainder joins the last chunk
    /// when that still fits one window; otherwise the two are split in half,
    /// since a chunk under a second would never be decoded at all.
    static func coveringRemainder(_ ranges: [Range<Int>], sampleCount: Int, maxLength: Int) -> [Range<Int>] {
        guard sampleCount > 0, maxLength > 0 else { return ranges }
        guard let last = ranges.last else { return evenSplit(0..<sampleCount, maxLength: maxLength) }
        guard last.upperBound < sampleCount else { return ranges }
        return ranges.dropLast() + evenSplit(last.lowerBound..<sampleCount, maxLength: maxLength)
    }

    private static func evenSplit(_ range: Range<Int>, maxLength: Int) -> [Range<Int>] {
        let parts = max(1, (range.count + maxLength - 1) / maxLength)
        return (0..<parts).map { part in
            let start = range.lowerBound + range.count * part / parts
            let end = range.lowerBound + range.count * (part + 1) / parts
            return start..<end
        }
    }
}

/// Where `WhisperKitEngine` listens for the take's language.
///
/// Detecting in every window (`detectLanguage` in `DecodingOptions`) let a take
/// switch language between chunks, and inside a window's temperature
/// fallbacks, which re-detect with a random sampler. So a take is detected
/// once, at temperature 0, from one window that starts at its first speech —
/// or ends at the take's end, when speech starts less than a window before it.
nonisolated enum WhisperLanguageProbe {
    static func window(firstSpeechSample: Int?, sampleCount: Int, windowSamples: Int) -> Range<Int> {
        guard sampleCount > 0 else { return 0..<0 }
        let length = min(max(1, windowSamples), sampleCount)
        let start = min(max(0, firstSpeechSample ?? 0), sampleCount - length)
        return start..<(start + length)
    }
}
