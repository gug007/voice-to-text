#if arch(x86_64)
import Foundation

/// Runs the local models — Parakeet and Whisper — on transcribe.cpp in the
/// Intel (x86_64) slice, in a worker process (`TranscribeSupervisor`) that uses
/// the Mac's GPU through Metal when it works and its CPU when it doesn't.
///
/// Neither CoreML engine holds up there. WhisperKit fills its float16 model
/// buffers through `FloatType`, a 4-byte `Float` on x86_64, so its first decode
/// writes past the buffer and crashes. FluidAudio's Parakeet has no Neural
/// Engine to run on, and on an Intel or AMD GPU its CoreML load stalled or
/// crashed the app. The models are quantized GGUF builds (`TranscribeCppModel`),
/// and the Whisper decode follows `WhisperKitEngine` wherever transcribe.cpp has
/// the same setting.
///
/// `chunksInternally` stays false, as it is for the CoreML engines: a caller
/// that pre-chunks (`MeetingTranscriber`) keeps doing so, and a long buffer that
/// does arrive whole is walked by transcribe.cpp itself — Whisper window by
/// window, Parakeet in one pass.
actor TranscribeCppEngine: TranscriptionEngine {
    /// The catalog id, which `TranscribeCppModel` is keyed by.
    let modelId: String
    private let model: TranscribeCppModel?
    private let supervisor: TranscribeSupervisor
    private var isLoaded = false

    init(modelId: String) {
        self.modelId = modelId
        self.model = TranscribeCppModel.model(forCatalogID: modelId)
        self.supervisor = TranscribeSupervisor(label: modelId)
    }

    var isReady: Bool {
        get async { isLoaded }
    }

    /// Parakeet has no prompt input; Whisper takes the committed tail.
    nonisolated var usesContextPrompt: Bool {
        TranscribeCppModel.model(forCatalogID: modelId)?.family == .whisper
    }

    func prepare(progress: PrepareProgress?) async throws {
        guard !isLoaded else { return }
        do {
            guard let model else { throw UnknownModel(id: modelId) }
            if !model.isDownloaded() {
                progress?(0.0, "Connecting to HuggingFace…")
                try await TranscribeCppDownload.fetch(model, progress: progress)
            }
            // The worker starts here: the first time after an install, its
            // Metal shaders compile, which takes a few seconds.
            progress?(0.95, "Loading model into memory…")
            try await supervisor.load(modelPath: model.fileURL.path)
            isLoaded = true
            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    // transcribe.cpp walks audio longer than a window itself, so `progress`
    // goes unused.
    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress _: TranscribeProgress?
    ) async throws -> String {
        guard isLoaded, let model else {
            throw TranscriptionEngineError.notReady
        }
        do {
            switch model.family {
            case .parakeet:
                let options = TranscribeSupervisor.RunOptions(withoutTimestamps: true)
                return try await supervisor.transcribe(samples, options: options).text
            case .whisper:
                return try await transcribeWhisper(samples, contextPrompt: contextPrompt)
            }
        } catch let error as TranscriptionEngineError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func transcribeWhisper(_ samples: [Float], contextPrompt: String?) async throws -> String {
        var options = WhisperRunOptions.make(
            TranscriptionDecoderOptions.current,
            contextPrompt: contextPrompt,
            sampleCount: samples.count
        )
        if options.language == nil, let probe = Self.languageProbe(in: samples) {
            // Pinned before the decode, from the first speech: left to itself,
            // transcribe.cpp detects from the first 30 s, which here would be
            // mostly silence.
            var detect = options
            detect.prompt = nil
            detect.withoutTimestamps = true
            options.language = try await supervisor.transcribe(Array(samples[probe]), options: detect).language
        }
        let first = try await supervisor.transcribe(samples, options: options)
        // The same empty-under-a-prompt check `WhisperKitEngine` applies to
        // each window, here over the whole buffer, which is decoded at once.
        let hasSpeech = { SpeechEnergy.voicedSpan(in: samples, sampleRate: WhisperRunOptions.sampleRate) != nil }
        switch WhisperChunkCheck.action(for: .success(first.text), prompted: options.prompt != nil, hasSpeech: hasSpeech) {
        case .accept(let text):
            return text
        case .retryWithoutPrompt, .retry:
            options.prompt = nil
            options.language = options.language ?? first.language
            return try await supervisor.transcribe(samples, options: options).text
        }
    }

    /// Where to detect the take's language, when transcribe.cpp's own choice —
    /// the first 30 s window — would hear mostly silence: one window from the
    /// first speech (see `WhisperLanguageProbe`). Nil when speech starts in
    /// the first half of that window, which costs no second decode.
    private nonisolated static func languageProbe(in samples: [Float]) -> Range<Int>? {
        let sampleRate = WhisperRunOptions.sampleRate
        guard let firstSpeech = SpeechEnergy.voicedSpan(in: samples, sampleRate: sampleRate)
            .map({ Int($0.lowerBound * Double(sampleRate)) }),
            firstSpeech > WhisperRunOptions.windowSamples / 2 else { return nil }
        let window = WhisperLanguageProbe.window(
            firstSpeechSample: firstSpeech,
            sampleCount: samples.count,
            windowSamples: WhisperRunOptions.windowSamples
        )
        return window.isEmpty || window.lowerBound == 0 ? nil : window
    }

    private struct UnknownModel: LocalizedError {
        let id: String

        var errorDescription: String? { "There is no transcribe.cpp build of \(id)." }
    }
}

/// `TranscriptionDecoderOptions` as transcribe.cpp's Whisper takes them.
/// Suppressing blanks and token ids, which whisper.cpp and WhisperKit offered,
/// has no transcribe.cpp counterpart; its own recipe suppresses blanks.
nonisolated enum WhisperRunOptions {
    static let sampleRate = 16_000
    /// One 30 s window, the most Whisper decodes at once.
    static let windowSamples = sampleRate * 30

    static func make(
        _ options: TranscriptionDecoderOptions,
        contextPrompt: String?,
        sampleCount: Int
    ) -> TranscribeSupervisor.RunOptions {
        var run = TranscribeSupervisor.RunOptions()
        run.language = options.language
        // As `WhisperKitEngine` combines them: the user's hint first so its
        // proper-noun spellings stay authoritative, then the committed tail so
        // Whisper keeps punctuation and casing. A blank prompt is none. Over
        // Whisper's prompt budget, transcribe.cpp keeps the most recent text.
        let combined = [options.initialPrompt, contextPrompt]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        run.prompt = combined.isEmpty ? nil : combined
        // Whisper moves through audio longer than one window by its timestamp
        // tokens. Without them it jumps a whole 30 s at a time and clips the
        // word spoken across each mark, so they stay on there whatever the
        // setting; the text that comes back has none either way.
        run.withoutTimestamps = options.withoutTimestamps && sampleCount <= windowSamples
        // transcribe.cpp steps the temperature from 0 up to 1 by this
        // increment, where WhisperKit takes a count of 0.2 steps. 1/n keeps
        // the count: at the default five it is the same 0.2 steps, and zero
        // turns the fallback off in both.
        run.temperatureIncrement = options.temperatureFallbackCount > 0
            ? 1 / Float(options.temperatureFallbackCount)
            : 0
        run.compressionRatioThreshold = options.compressionRatioThreshold
        run.logProbThreshold = options.logProbThreshold
        run.noSpeechThreshold = options.noSpeechThreshold
        return run
    }
}
#endif
