#if arch(x86_64)
import Foundation
import OSLog
import Synchronization
import WhisperCpp

/// Runs the local Whisper models on whisper.cpp, on the CPU, in the Intel
/// (x86_64) slice. WhisperKit can't run there: it fills its float16 model
/// buffers through `FloatType`, which is a 4-byte `Float` on x86_64, so its
/// first decode writes past the buffer and crashes. The models are
/// whisper.cpp's quantized GGML builds (`WhisperCppModel`), and the decode
/// follows `WhisperKitEngine` wherever whisper.cpp has the same setting.
///
/// `chunksInternally` stays false, as it is for `WhisperKitEngine`: a caller
/// that pre-chunks (`MeetingTranscriber`) keeps doing so, and a long buffer
/// that does arrive whole is walked by `whisper_full` itself.
actor WhisperCppEngine: TranscriptionEngine {
    /// The catalog id, which `WhisperCppModel` is keyed by.
    let modelId: String
    private let model: WhisperCppModel?
    private var context: WhisperCppContext?

    init(modelId: String) {
        self.modelId = modelId
        self.model = WhisperCppModel.model(forCatalogID: modelId)
    }

    var isReady: Bool {
        get async { context != nil }
    }

    func prepare(progress: PrepareProgress?) async throws {
        guard context == nil else { return }
        do {
            guard let model else { throw WhisperCppContext.Failure.unknownModel(modelId) }
            if !model.isDownloaded() {
                progress?(0.0, "Connecting to HuggingFace…")
                try await WhisperCppDownload.fetch(model, progress: progress)
            }
            progress?(0.95, "Loading model into memory…")
            context = try await WhisperCppContext.load(contentsOf: model.fileURL)
            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    // `whisper_full` walks audio longer than 30 s itself, so `progress` goes
    // unused.
    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress _: TranscribeProgress?
    ) async throws -> String {
        guard let context else {
            throw TranscriptionEngineError.notReady
        }
        do {
            var options = WhisperCppDecodeOptions(TranscriptionDecoderOptions.current, contextPrompt: contextPrompt)
            let probe = options.language == nil ? Self.languageProbe(in: samples) : nil
            let first = try await context.transcribe(samples, options: options, languageProbe: probe)
            // The same empty-under-a-prompt check `WhisperKitEngine` applies to
            // each window, here over the whole buffer, which is decoded at once.
            let hasSpeech = { SpeechEnergy.voicedSpan(in: samples, sampleRate: WhisperCppContext.sampleRate) != nil }
            switch WhisperChunkCheck.action(for: .success(first.text), prompted: options.prompt != nil, hasSpeech: hasSpeech) {
            case .accept(let text):
                return text
            case .retryWithoutPrompt, .retry:
                options.prompt = nil
                options.language = options.language ?? first.language
                return try await context.transcribe(samples, options: options, languageProbe: nil).text
            }
        } catch let error as TranscriptionEngineError {
            throw error
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Where to detect the take's language, once, before the decode pins it:
    /// one window from the first speech (see `WhisperLanguageProbe`). Left to
    /// itself whisper.cpp detects from the first 30 s, which in a take that
    /// opens with silence is the silence.
    private nonisolated static func languageProbe(in samples: [Float]) -> Range<Int>? {
        let firstSpeech = SpeechEnergy.voicedSpan(in: samples, sampleRate: WhisperCppContext.sampleRate)
            .map { Int($0.lowerBound * Double(WhisperCppContext.sampleRate)) }
        let window = WhisperLanguageProbe.window(
            firstSpeechSample: firstSpeech,
            sampleCount: samples.count,
            windowSamples: WhisperCppContext.windowSamples
        )
        return window.isEmpty ? nil : window
    }
}

/// `TranscriptionDecoderOptions` as whisper.cpp takes them.
nonisolated struct WhisperCppDecodeOptions: Sendable, Equatable {
    /// Nil detects the language.
    var language: String?
    /// The vocabulary hint and the rolling context, as one prompt.
    var prompt: String?
    var temperatureIncrement: Float
    var withoutTimestamps: Bool
    var suppressBlank: Bool
    var suppressTokens: [Int32]
    var logProbThreshold: Float?
    var noSpeechThreshold: Float?

    init(_ options: TranscriptionDecoderOptions, contextPrompt: String?) {
        language = options.language
        // As `WhisperKitEngine` combines them: the user's hint first so its
        // proper-noun spellings stay authoritative, then the committed tail so
        // Whisper keeps punctuation and casing. A blank prompt is none.
        let combined: String?
        switch (options.initialPrompt, contextPrompt) {
        case let (user?, ctx?):
            combined = user + " " + ctx
        case let (user?, nil):
            combined = user
        case let (nil, ctx?):
            combined = ctx
        case (nil, nil):
            combined = nil
        }
        let trimmed = combined?.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt = trimmed?.isEmpty == false ? trimmed : nil
        // whisper.cpp steps the temperature from 0 up to 1 by this increment,
        // where WhisperKit takes a count of 0.2 steps. 1/n keeps the count: at
        // the default five it is the same 0.2 steps, and zero turns the
        // fallback off in both.
        temperatureIncrement = options.temperatureFallbackCount > 0
            ? 1 / Float(options.temperatureFallbackCount)
            : 0
        withoutTimestamps = options.withoutTimestamps
        suppressBlank = options.suppressBlank
        suppressTokens = options.suppressTokens.compactMap { Int32(exactly: $0) }
        logProbThreshold = options.logProbThreshold
        noSpeechThreshold = options.noSpeechThreshold
    }
}

/// A loaded whisper.cpp model. Owns the `whisper_context` and frees it when
/// the last reference goes, which can't be while a call is running: each call
/// holds the context until it returns.
///
/// Every call into the context runs on `queue`, one at a time. A context isn't
/// safe to use from two threads, and its calls block for seconds of CPU work,
/// which on the Swift cooperative pool would hold up unrelated tasks.
nonisolated final class WhisperCppContext: @unchecked Sendable {
    enum Failure: LocalizedError {
        case unknownModel(String)
        case loadFailed(String)
        case decodeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .unknownModel(let id):
                return "There is no whisper.cpp build of \(id)."
            case .loadFailed(let fileName):
                return "whisper.cpp couldn't load \(fileName). Delete the model and download it again."
            case .decodeFailed(let status):
                return "whisper.cpp stopped with error \(status)."
            }
        }
    }

    struct Transcript: Sendable {
        let text: String
        /// The language the decode ran in, when this call detected it.
        let language: String?
    }

    static let sampleRate = Int(WHISPER_SAMPLE_RATE)
    /// One 30 s window, the most Whisper decodes at once.
    static let windowSamples = Int(WHISPER_SAMPLE_RATE) * Int(WHISPER_CHUNK_SIZE)

    /// Physical cores, at most eight. Hyper-threads share a core's vector
    /// units, so more threads than cores only adds contention, and past eight
    /// the decode stops getting faster while the rest of the Mac slows down.
    static let threadCount: Int32 = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 else { return 4 }
        return min(cores, 8)
    }()

    private let pointer: OpaquePointer
    private let queue: DispatchQueue

    private init(pointer: OpaquePointer, queue: DispatchQueue) {
        self.pointer = pointer
        self.queue = queue
    }

    deinit {
        whisper_free(pointer)
    }

    static func load(contentsOf url: URL) async throws -> WhisperCppContext {
        _ = routesLogs
        let queue = DispatchQueue(label: "voice-to-text-ai.VoiceToText.whisper-cpp", qos: .userInitiated)
        return try await run(on: queue) {
            var params = whisper_context_default_params()
            params.use_gpu = false
            guard let pointer = whisper_init_from_file_with_params(url.path, params) else {
                throw Failure.loadFailed(url.lastPathComponent)
            }
            return WhisperCppContext(pointer: pointer, queue: queue)
        }
    }

    /// Decodes `samples` whole. With no language in `options`, detects it
    /// first from `languageProbe` and pins it for the decode; with no probe
    /// either, whisper.cpp detects it from the start of the audio. Cancelling
    /// the calling task stops the decode at whisper.cpp's next check.
    func transcribe(
        _ samples: [Float],
        options: WhisperCppDecodeOptions,
        languageProbe: Range<Int>?
    ) async throws -> Transcript {
        let abort = AbortFlag()
        return try await withTaskCancellationHandler {
            try await Self.run(on: queue) { [self] in
                if abort.isRaised { throw CancellationError() }
                let detected = try options.language == nil
                    ? languageProbe.flatMap { try detectLanguage(in: samples[$0], abort: abort) }
                    : nil
                let text = try decode(samples, options: options, language: options.language ?? detected, abort: abort)
                return Transcript(text: text, language: detected)
            }
        } onCancel: {
            abort.raise()
        }
    }

    /// `whisper_full` with `detect_language` only detects: it runs the
    /// encoder over `audio` and stops. Unlike `whisper_lang_auto_detect`, it
    /// stops early when the task is cancelled.
    private func detectLanguage(in audio: ArraySlice<Float>, abort: AbortFlag) throws -> String? {
        guard whisper_is_multilingual(pointer) != 0 else { return nil }
        var params = Self.baseParams(abort: abort)
        params.detect_language = true
        let status = audio.withUnsafeBufferPointer {
            whisper_full(pointer, params, $0.baseAddress, Int32($0.count))
        }
        if abort.isRaised { throw CancellationError() }
        guard status == 0, let code = whisper_lang_str(whisper_full_lang_id(pointer)) else {
            AppLog.engine.warning("whisper.cpp language detection failed; detecting from the start of the audio")
            return nil
        }
        return String(cString: code)
    }

    private func decode(
        _ samples: [Float],
        options: WhisperCppDecodeOptions,
        language: String?,
        abort: AbortFlag
    ) throws -> String {
        var params = Self.baseParams(abort: abort)
        // whisper.cpp moves through audio longer than one window by its
        // timestamp tokens. Without them it jumps a whole 30 s at a time and
        // clips the word spoken across each mark, so they stay on there
        // whatever the setting; the text it returns has none either way.
        params.no_timestamps = options.withoutTimestamps && samples.count <= Self.windowSamples
        params.suppress_blank = options.suppressBlank
        params.temperature_inc = options.temperatureIncrement
        if let threshold = options.logProbThreshold { params.logprob_thold = threshold }
        if let threshold = options.noSpeechThreshold { params.no_speech_thold = threshold }
        // The prompt reaches every window, as it reaches every chunk in
        // `WhisperKitEngine`, rather than only the first.
        params.carry_initial_prompt = true
        // The user's suppressed token ids, as WhisperKit's `SuppressTokensFilter`
        // takes them: text tokens only, never the special ones a decode needs.
        let eot = whisper_token_eot(pointer)
        let suppressed = TokenList(options.suppressTokens.filter { $0 >= 0 && $0 < eot })
        if !suppressed.ids.isEmpty {
            params.logits_filter_callback = { _, _, _, _, logits, data in
                guard let logits, let data else { return }
                for id in Unmanaged<TokenList>.fromOpaque(data).takeUnretainedValue().ids {
                    logits[Int(id)] = -.infinity
                }
            }
            params.logits_filter_callback_user_data = Unmanaged.passUnretained(suppressed).toOpaque()
        }

        let status = withExtendedLifetime(suppressed) {
            (language ?? "auto").withCString { language in
                Self.withOptionalCString(options.prompt) { prompt in
                    params.language = language
                    params.initial_prompt = prompt
                    return samples.withUnsafeBufferPointer {
                        whisper_full(pointer, params, $0.baseAddress, Int32($0.count))
                    }
                }
            }
        }
        if abort.isRaised { throw CancellationError() }
        guard status == 0 else { throw Failure.decodeFailed(status) }

        // Each segment's text carries its own leading space where the language
        // has one, so they join with nothing between.
        var text = ""
        for index in 0..<whisper_full_n_segments(pointer) {
            if let segment = whisper_full_get_segment_text(pointer, index) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What every call shares: the thread count, no printing, and `abort`
    /// checked between compute steps. `no_context` (whisper.cpp's default)
    /// keeps a call from carrying text over from the one before it.
    private static func baseParams(abort: AbortFlag) -> whisper_full_params {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = threadCount
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.no_context = true
        params.abort_callback = { data in
            guard let data else { return false }
            return Unmanaged<AbortFlag>.fromOpaque(data).takeUnretainedValue().isRaised
        }
        params.abort_callback_user_data = Unmanaged.passUnretained(abort).toOpaque()
        return params
    }

    private static func withOptionalCString<Result>(
        _ string: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let string else { return body(nil) }
        return string.withCString { body($0) }
    }

    private static func run<T: Sendable>(
        on queue: DispatchQueue,
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    /// whisper.cpp and ggml print everything to stderr unless given a logger:
    /// the model's hyperparameters on each load, timings after each decode.
    /// Their warnings and errors go to the engine log; the rest is dropped.
    private static let routesLogs: Void = {
        whisper_log_set({ level, text, _ in
            guard let text, level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR else { return }
            let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            AppLog.engine.warning("whisper.cpp: \(message, privacy: .public)")
        }, nil)
    }()

    private final class TokenList: Sendable {
        let ids: [Int32]

        init(_ ids: [Int32]) { self.ids = ids }
    }

    /// Read by whisper.cpp's abort callback between compute steps, from its
    /// worker thread; raised from whichever thread cancels the task.
    private final class AbortFlag: Sendable {
        private let raised = Atomic<Bool>(false)

        var isRaised: Bool { raised.load(ordering: .relaxed) }

        func raise() { raised.store(true, ordering: .relaxed) }
    }
}
#endif
