import Foundation
import WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    let modelId: String
    private var pipe: WhisperKit?

    init(modelId: String) {
        self.modelId = modelId
    }

    var isReady: Bool {
        get async { pipe != nil }
    }

    func prepare(progress: PrepareProgress?) async throws {
        guard pipe == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: ModelStorage.whisperKitBaseURL,
                withIntermediateDirectories: true
            )

            progress?(0.0, "Connecting to HuggingFace…")

            let modelFolder = try await WhisperKit.download(
                variant: modelId,
                downloadBase: ModelStorage.whisperKitBaseURL,
                progressCallback: { foundationProgress in
                    let fraction = foundationProgress.fractionCompleted
                    let done = foundationProgress.completedUnitCount
                    let total = max(foundationProgress.totalUnitCount, 1)
                    let message = "Downloading \(done)/\(total) files"
                    progress?(fraction, message)
                }
            )

            progress?(0.95, "Loading model into memory…")

            let config = WhisperKitConfig(
                model: modelId,
                downloadBase: ModelStorage.whisperKitBaseURL,
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                download: false,
                useBackgroundDownloadSession: true
            )
            pipe = try await WhisperKit(config)

            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    func transcribe(samples: [Float], contextPrompt: String?) async throws -> String {
        guard let pipe else {
            throw TranscriptionEngineError.notReady
        }
        do {
            let decodeOptions = buildDecodingOptions(pipe: pipe, contextPrompt: contextPrompt)
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: decodeOptions)
            return results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func buildDecodingOptions(pipe: WhisperKit, contextPrompt: String?) -> DecodingOptions {
        let opts = TranscriptionDecoderOptions.current

        // Combine user-supplied vocabulary hint with rolling context tail.
        // User prompt first so proper-noun spellings stay authoritative, then
        // the committed-tail context so Whisper keeps punctuation / casing.
        let combinedPrompt: String?
        switch (opts.initialPrompt, contextPrompt) {
        case let (user?, ctx?):
            combinedPrompt = user + " " + ctx
        case let (user?, nil):
            combinedPrompt = user
        case let (nil, ctx?):
            combinedPrompt = ctx
        case (nil, nil):
            combinedPrompt = nil
        }

        let promptTokens: [Int]?
        if let text = combinedPrompt, let tokenizer = pipe.tokenizer {
            promptTokens = tokenizer.encode(text: text)
        } else {
            promptTokens = nil
        }

        return DecodingOptions(
            language: opts.language,
            temperatureFallbackCount: opts.temperatureFallbackCount,
            withoutTimestamps: opts.withoutTimestamps,
            promptTokens: promptTokens,
            suppressBlank: opts.suppressBlank,
            supressTokens: opts.suppressTokens.isEmpty ? nil : opts.suppressTokens,
            compressionRatioThreshold: opts.compressionRatioThreshold,
            logProbThreshold: opts.logProbThreshold,
            noSpeechThreshold: opts.noSpeechThreshold
        )
    }
}
