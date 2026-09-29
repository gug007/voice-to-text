import Foundation
import OSLog
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

            // An installed model loads straight from disk. `WhisperKit.download`
            // lists the repo on Hugging Face before it looks at the disk, with no
            // offline fallback, so going through it made every cold load — each
            // launch, each LRU eviction — need the network. Only a folder that
            // is missing a model, or that fails to load, goes back to the
            // download path. That fetches the files that are missing; a file
            // that is on disk with its download record intact is kept as it is,
            // so a damaged one only goes away when the model is deleted and
            // downloaded again.
            let installed = ModelStorage.whisperKitModelFolder(variant: modelId)
            if WhisperKitModelFiles.hasRequiredModels(in: installed) {
                progress?(0.95, "Loading model into memory…")
                do {
                    pipe = try await WhisperKit(loadConfig(modelFolder: installed))
                    progress?(1.0, "Ready")
                    return
                } catch {
                    AppLog.engine.warning("Whisper \(self.modelId, privacy: .public) failed to load from disk (\(error.localizedDescription, privacy: .public)); downloading it again")
                }
            }

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

            pipe = try await WhisperKit(loadConfig(modelFolder: modelFolder))

            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Loads from `modelFolder` and never downloads. `downloadBase` still
    /// matters: it is where WhisperKit keeps (and first looks for) the
    /// tokenizer.
    private func loadConfig(modelFolder: URL) -> WhisperKitConfig {
        WhisperKitConfig(
            model: modelId,
            downloadBase: ModelStorage.whisperKitBaseURL,
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true,
            download: false,
            useBackgroundDownloadSession: true
        )
    }

    // Long audio is cut into ≤30 s chunks here rather than by the external
    // chunker, so `progress` goes unused.
    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress _: TranscribeProgress?
    ) async throws -> String {
        guard let pipe else {
            throw TranscriptionEngineError.notReady
        }
        do {
            let windowSamples = pipe.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
            var options = buildDecodingOptions(pipe: pipe, contextPrompt: contextPrompt)
            if options.language == nil {
                options = await pinningDetectedLanguage(options, pipe: pipe, samples: samples, windowSamples: windowSamples)
            }
            let pieces = samples.count > windowSamples
                ? try await transcribeLongForm(pipe: pipe, samples: samples, options: options, windowSamples: windowSamples)
                : [try await transcribeWindow(pipe: pipe, audio: samples, options: options)]
            return pieces.filter { !$0.isEmpty }.joined(separator: " ")
        } catch let error as TranscriptionEngineError {
            throw error
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Audio longer than one window. Left to itself WhisperKit walks it in
    /// back-to-back 30 s windows, so a word spoken across each 30 s mark was
    /// clipped or garbled. Instead cut where `chunkingStrategy: .vad` would —
    /// WhisperKit's own `VADAudioChunker`, at the middle of the longest
    /// silence in each window's second half — and decode the chunks in
    /// parallel, but through `transcribeWithOptions` so each chunk's outcome
    /// can be checked (see `WhisperChunkCheck`) instead of silently dropped.
    private func transcribeLongForm(
        pipe: WhisperKit,
        samples: [Float],
        options: DecodingOptions,
        windowSamples: Int
    ) async throws -> [String] {
        let chunker = VADAudioChunker(vad: pipe.voiceActivityDetector)
        let cuts = try await chunker.chunkAll(
            audioArray: samples,
            maxChunkLength: windowSamples,
            decodeOptions: options
        ).map { $0.seekOffsetIndex..<($0.seekOffsetIndex + $0.audioSamples.count) }
        let chunks = WhisperChunkCheck
            .coveringRemainder(cuts, sampleCount: samples.count, maxLength: windowSamples)
            .map { AudioChunk(seekOffsetIndex: $0.lowerBound, audioSamples: Array(samples[$0])) }
        let outcomes = await pipe.transcribeWithOptions(
            audioArrays: chunks.map(\.audioSamples),
            decodeOptionsArray: Array(repeating: options, count: chunks.count),
            seekOffsets: chunks.map(\.seekOffsetIndex)
        )
        guard outcomes.count == chunks.count else {
            throw TranscriptionEngineError.transcriptionFailed(
                "Whisper returned \(outcomes.count) results for \(chunks.count) parts of the audio."
            )
        }

        var pieces: [String] = []
        for (index, outcome) in outcomes.enumerated() {
            let audio = chunks[index].audioSamples
            let text = outcome.map { $0.map(\.text).joined(separator: " ") }
            switch checkedAction(for: text, audio: audio, options: options) {
            case .accept(let text):
                pieces.append(text)
            case .retryWithoutPrompt:
                pieces.append(try await decode(pipe: pipe, audio: audio, options: options.withoutPrompt))
            case .retry:
                if case .failure(let error) = outcome {
                    AppLog.engine.warning("Whisper part \(index + 1)/\(chunks.count) failed (\(error.localizedDescription, privacy: .public)); retrying it alone")
                }
                pieces.append(try await transcribeWindow(pipe: pipe, audio: audio, options: options))
            }
        }
        return pieces
    }

    /// One window's worth of audio, with the same empty-under-a-prompt check
    /// the chunked path applies. A failure here throws: there is no smaller
    /// piece left to retry.
    private func transcribeWindow(pipe: WhisperKit, audio: [Float], options: DecodingOptions) async throws -> String {
        let text = try await decode(pipe: pipe, audio: audio, options: options)
        switch checkedAction(for: .success(text), audio: audio, options: options) {
        case .accept(let text):
            return text
        case .retryWithoutPrompt, .retry:
            return try await decode(pipe: pipe, audio: audio, options: options.withoutPrompt)
        }
    }

    private func checkedAction(
        for outcome: Result<String, any Error>,
        audio: [Float],
        options: DecodingOptions
    ) -> WhisperChunkCheck.Action {
        WhisperChunkCheck.action(for: outcome, prompted: options.promptTokens != nil) {
            SpeechEnergy.voicedSpan(in: audio, sampleRate: WhisperKit.sampleRate) != nil
        }
    }

    private func decode(pipe: WhisperKit, audio: [Float], options: DecodingOptions) async throws -> String {
        let results = try await pipe.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Detects the take's language once and pins it for every chunk and every
    /// temperature fallback (see `WhisperLanguageProbe`). If detection fails,
    /// the options keep WhisperKit's per-window detection rather than fall
    /// back to forced English.
    private func pinningDetectedLanguage(
        _ options: DecodingOptions,
        pipe: WhisperKit,
        samples: [Float],
        windowSamples: Int
    ) async -> DecodingOptions {
        let firstSpeech = SpeechEnergy.voicedSpan(in: samples, sampleRate: WhisperKit.sampleRate)
            .map { Int($0.lowerBound * Double(WhisperKit.sampleRate)) }
        let window = WhisperLanguageProbe.window(
            firstSpeechSample: firstSpeech,
            sampleCount: samples.count,
            windowSamples: windowSamples
        )
        guard !window.isEmpty else { return options }
        do {
            let language = try await pipe.detectLangauge(audioArray: Array(samples[window])).language
            guard !language.isEmpty else { return options }
            var pinned = options
            pinned.language = language
            pinned.detectLanguage = false
            return pinned
        } catch {
            AppLog.engine.warning("Whisper language detection failed (\(error.localizedDescription, privacy: .public)); detecting per window")
            return options
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

        // A blank prompt still takes WhisperKit's prompt path (an empty
        // `<|startofprev|>` block, and no prefill cache), so treat it as none.
        let promptTokens: [Int]?
        if let text = combinedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           let tokenizer = pipe.tokenizer {
            promptTokens = tokenizer.encode(text: text)
        } else {
            promptTokens = nil
        }

        return DecodingOptions(
            language: opts.language,
            temperatureFallbackCount: opts.temperatureFallbackCount,
            // With no language set, detect it. WhisperKit's defaults
            // (`usePrefillPrompt` on, `detectLanguage` off) prefill `<|en|>`
            // instead, forcing English on every multilingual model. This
            // per-window detection is only the fallback: `transcribe` pins the
            // language it detects once for the whole take.
            detectLanguage: opts.language == nil,
            withoutTimestamps: opts.withoutTimestamps,
            promptTokens: promptTokens,
            suppressBlank: opts.suppressBlank,
            supressTokens: opts.suppressTokens.isEmpty ? nil : opts.suppressTokens,
            compressionRatioThreshold: opts.compressionRatioThreshold,
            logProbThreshold: opts.logProbThreshold,
            noSpeechThreshold: opts.noSpeechThreshold,
            concurrentWorkerCount: Self.parallelChunks
        )
    }

    /// Chunks of a long buffer decoded at once. WhisperKit's macOS default is
    /// 16, which with Large v3 means sixteen decoder caches plus encoder
    /// activations in flight on an 8 GB Mac; two keeps peak memory near a
    /// single decode while still overlapping the encoder and decoder work.
    private nonisolated static let parallelChunks = 2
}

private extension DecodingOptions {
    var withoutPrompt: DecodingOptions {
        var options = self
        options.promptTokens = nil
        return options
    }
}
