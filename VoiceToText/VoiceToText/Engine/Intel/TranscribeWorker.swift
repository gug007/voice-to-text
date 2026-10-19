#if arch(x86_64)
import Darwin
import Foundation
import Synchronization
import TranscribeCpp

/// The worker process: the only place transcribe.cpp's native code runs. It is
/// the app's own executable started with `--transcribe-worker`
/// (`AppEntry`), and serves `TranscribeWorkerProtocol` requests until its
/// stdin closes.
///
/// A GPU driver that crashes, a `GGML_ASSERT` that aborts, or a Metal call
/// that never returns takes down only this process; `TranscribeSupervisor`
/// sees it go and carries on, on the CPU. A worker started with `--cpu-only`
/// restricts transcribe.cpp to its CPU backends before it registers any, so
/// no GPU driver code runs in it at all.
///
/// Never touches AppKit or SwiftUI. A dedicated thread reads stdin, so a
/// cancel reaches a running transcription and the process exits the moment
/// the app goes away — when the app quits, crashes or is killed, its end of
/// the pipe closes — even while the main thread is stuck in native code.
nonisolated enum TranscribeWorker {
    static func run(cpuOnly: Bool) -> Int32 {
        // A write to an app that has gone must fail, not kill the worker with
        // SIGPIPE before it can exit cleanly.
        signal(SIGPIPE, SIG_IGN)
        // Take the real stdout for the protocol before any native code runs,
        // and point fd 1 at stderr: ggml prints to stdout in places, and a
        // stray byte there would corrupt the protocol stream.
        let protocolOut = dup(STDOUT_FILENO)
        guard protocolOut >= 0, dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
            log("can't claim stdout: \(String(cString: strerror(errno)))")
            return 2
        }
        _ = fcntl(protocolOut, F_SETFD, FD_CLOEXEC)

        let inbox = Inbox()
        let reader = Thread { readRequests(into: inbox) }
        reader.name = "transcribe-worker-stdin"
        reader.start()

        // `--cpu-only` narrows the backend mask before anything registers a
        // backend. Registering the GPU backends runs the driver's code (and,
        // the first time, compiles ggml's Metal library), so this is where a
        // broken driver crashes or hangs, before the hello is answered.
        transcribe_log_set(logLine, nil)
        injectFault(at: .initialization, cpuOnly: cpuOnly)
        var backends = transcribe_backend_init_params()
        transcribe_backend_init_params_init(&backends)
        backends.allowed_backends = cpuOnly ? TRANSCRIBE_BACKEND_MASK_CPU : TRANSCRIBE_BACKEND_MASK_ALL
        let initStatus = transcribe_init_backends_ex(&backends)
        let initFailure = initStatus == TRANSCRIBE_OK
            ? nil
            : "transcribe.cpp registered no compute device: \(statusString(initStatus))"

        var session: OpaquePointer?
        defer { transcribe_session_free(session) }

        while true {
            let (request, pcm) = inbox.next()
            let response: TranscribeWorkerProtocol.Response
            switch request.kind {
            case .hello:
                if let initFailure {
                    response = .init(kind: .error, version: TranscribeWorkerProtocol.version, message: initFailure)
                } else {
                    response = .init(kind: .hello, version: TranscribeWorkerProtocol.version, devices: devices())
                }
            case .load:
                // Free the old model first, so two are never held at once.
                transcribe_session_free(session)
                session = nil
                injectFault(at: .load, cpuOnly: cpuOnly)
                switch load(request, cpuOnly: cpuOnly) {
                case .success(let loaded):
                    session = loaded.session
                    response = .init(kind: .loaded, loaded: loaded.info)
                case .failure(let failure):
                    response = failure.response
                }
            case .transcribe:
                if let session {
                    injectFault(at: .run, cpuOnly: cpuOnly)
                    response = transcribe(pcm, options: request.run ?? .init(), session: session)
                } else {
                    response = .init(kind: .error, message: "No model is loaded.")
                }
            case .unload:
                transcribe_session_free(session)
                session = nil
                response = .init(kind: .ok)
            case .cancel:
                // Handled on the stdin thread; never queued.
                continue
            }
            guard let frame = try? TranscribeWorkerProtocol.encode(response),
                  TranscribeWorkerProtocol.write(frame, to: protocolOut) else {
                // The app has gone; so does the worker.
                exitNow(1)
            }
        }
    }

    // MARK: - Requests

    /// Raised by a `cancel` from the stdin thread; read by transcribe.cpp's
    /// abort callback between decode steps on the main thread.
    private static let abort = AbortFlag()

    /// The stdin thread. Queues requests for the main loop and ends the
    /// process when the app closes stdin (an unload, a quit, or the app died).
    /// `_exit` skips C++ static destructors, so a model still loaded can't
    /// trip ggml-metal's teardown asserts; the OS takes back its memory.
    private static func readRequests(into inbox: Inbox) -> Never {
        while true {
            do {
                guard let (request, pcm) = try TranscribeWorkerProtocol.read(
                    TranscribeWorkerProtocol.Request.self,
                    from: STDIN_FILENO
                ) else {
                    exitNow(0)
                }
                switch request.kind {
                case .cancel:
                    abort.raise()
                case .transcribe:
                    // Lowered here rather than when the run starts, so a cancel
                    // that arrives before the main loop picks the run up still
                    // stops it.
                    abort.lower()
                    inbox.put(request, pcm)
                default:
                    inbox.put(request, pcm)
                }
            } catch {
                log("can't read a request: \(error.localizedDescription)")
                exitNow(1)
            }
        }
    }

    private static func exitNow(_ code: Int32) -> Never {
        _exit(code)
    }

    // MARK: - Devices and models

    private static func devices() -> [TranscribeWorkerProtocol.Device] {
        (0..<transcribe_device_count()).compactMap { index in
            transcribe_device_get(index).flatMap(deviceInfo)
        }
    }

    private static func deviceInfo(_ device: transcribe_device_t) -> TranscribeWorkerProtocol.Device? {
        var info = transcribe_device_info()
        transcribe_device_info_init(&info)
        guard transcribe_device_get_info(device, &info) == TRANSCRIBE_OK else { return nil }
        return TranscribeWorkerProtocol.Device(
            name: info.name.map { String(cString: $0) } ?? "",
            description: info.description.map { String(cString: $0) } ?? "",
            kind: info.kind.map { String(cString: $0) } ?? "",
            isGPU: info.device_type == TRANSCRIBE_DEVICE_TYPE_GPU || info.device_type == TRANSCRIBE_DEVICE_TYPE_IGPU,
            memoryBytes: info.memory_total
        )
    }

    private struct LoadedSession {
        let session: OpaquePointer
        let info: TranscribeWorkerProtocol.Loaded
    }

    private struct Failure: Error {
        let response: TranscribeWorkerProtocol.Response

        init(_ message: String, status: transcribe_status? = nil) {
            response = .init(
                kind: .error,
                message: message,
                isBackendFailure: status == TRANSCRIBE_ERR_BACKEND
            )
        }
    }

    private static func load(
        _ request: TranscribeWorkerProtocol.Request,
        cpuOnly: Bool
    ) -> Result<LoadedSession, Failure> {
        guard let path = request.modelPath else { return .failure(Failure("The load named no model.")) }
        var loadParams = transcribe_model_load_params()
        transcribe_model_load_params_init(&loadParams)
        // AUTO takes the first GPU that initializes and falls back to the CPU.
        loadParams.backend = cpuOnly ? TRANSCRIBE_BACKEND_CPU : TRANSCRIBE_BACKEND_AUTO
        var sessionParams = transcribe_session_params()
        transcribe_session_params_init(&sessionParams)
        sessionParams.n_threads = Int32(clamping: request.threads ?? 0)

        let started = ContinuousClock.now
        var session: OpaquePointer?
        let status = transcribe_open(path, &loadParams, &sessionParams, &session)
        guard status == TRANSCRIBE_OK, let session else {
            let name = (path as NSString).lastPathComponent
            return .failure(Failure("transcribe.cpp couldn't load \(name): \(statusString(status))", status: status))
        }
        let elapsed = started.duration(to: .now)
        transcribe_set_abort_callback(session, { data in
            guard let data else { return false }
            return Unmanaged<AbortFlag>.fromOpaque(data).takeUnretainedValue().isRaised
        }, Unmanaged.passUnretained(abort).toOpaque())

        let model = transcribe_get_model(session)
        let device = transcribe_model_device(model).flatMap(deviceInfo)
        let backend = transcribe_model_backend(model).map { String(cString: $0) } ?? ""
        let info = TranscribeWorkerProtocol.Loaded(
            architecture: transcribe_model_arch_string(model).map { String(cString: $0) } ?? "",
            backend: backend,
            device: device.map { $0.description.isEmpty ? $0.name : $0.description } ?? "unknown",
            onGPU: device?.isGPU ?? (!backend.isEmpty && backend.lowercased() != "cpu"),
            loadMilliseconds: Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15
        )
        return .success(LoadedSession(session: session, info: info))
    }

    // MARK: - Transcription

    private static func transcribe(
        _ pcm: [Float],
        options: TranscribeWorkerProtocol.RunOptions,
        session: OpaquePointer
    ) -> TranscribeWorkerProtocol.Response {
        guard !pcm.isEmpty else {
            return .init(kind: .transcript, transcript: .init(
                text: "", language: nil, melMilliseconds: 0, encodeMilliseconds: 0, decodeMilliseconds: 0
            ))
        }
        let model = transcribe_get_model(session)
        let isWhisper = transcribe_model_accepts_ext_kind(model, TRANSCRIBE_EXT_SLOT_RUN, TRANSCRIBE_EXT_KIND_WHISPER_RUN)

        var whisper = transcribe_whisper_run_ext()
        transcribe_whisper_run_ext_init(&whisper)
        if let increment = options.temperatureIncrement { whisper.temperature_inc = increment }
        if let threshold = options.compressionRatioThreshold { whisper.compression_ratio_thold = threshold }
        if let threshold = options.logProbThreshold { whisper.logprob_thold = threshold }
        if let threshold = options.noSpeechThreshold { whisper.no_speech_thold = threshold }

        let status = withOptionalCString(options.language) { language in
            withOptionalCString(isWhisper ? options.prompt : nil) { prompt in
                withUnsafePointer(to: &whisper) { whisperPointer in
                    var params = transcribe_run_params()
                    transcribe_run_params_init(&params)
                    params.timestamps = options.withoutTimestamps ? TRANSCRIBE_TIMESTAMPS_NONE : TRANSCRIBE_TIMESTAMPS_AUTO
                    params.language = language
                    params.prompt = prompt
                    if isWhisper {
                        params.family = UnsafeRawPointer(whisperPointer).assumingMemoryBound(to: transcribe_ext.self)
                    }
                    return pcm.withUnsafeBufferPointer {
                        transcribe_run(session, $0.baseAddress, Int32($0.count), &params)
                    }
                }
            }
        }

        if status == TRANSCRIBE_ERR_ABORTED || transcribe_was_aborted(session) {
            return .init(kind: .aborted)
        }
        // A decode cut off at the model's cap, or stopped because it began
        // repeating itself, still holds the text before that point: better
        // than nothing, as the log says.
        let truncated = status == TRANSCRIBE_ERR_OUTPUT_TRUNCATED || status == TRANSCRIBE_ERR_OUTPUT_REPETITION
        guard status == TRANSCRIBE_OK || truncated else {
            return Failure("transcribe.cpp stopped: \(statusString(status))", status: status).response
        }
        if truncated {
            log("transcription ended early (\(statusString(status))); returning the text before that point")
        }

        var timings = transcribe_timings()
        transcribe_timings_init(&timings)
        _ = transcribe_get_timings(session, &timings)
        let text = transcribe_full_text(session).map { String(cString: $0) } ?? ""
        let language = transcribe_detected_language(session).map { String(cString: $0) }
        return .init(kind: .transcript, transcript: .init(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language?.isEmpty == false ? language : nil,
            melMilliseconds: finite(timings.mel_ms),
            encodeMilliseconds: finite(timings.encode_ms),
            decodeMilliseconds: finite(timings.decode_ms)
        ))
    }

    private static func finite(_ value: Float) -> Double {
        value.isFinite ? Double(value) : 0
    }

    private static func withOptionalCString<Result>(
        _ string: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let string, !string.isEmpty else { return body(nil) }
        return string.withCString { body($0) }
    }

    private static func statusString(_ status: transcribe_status) -> String {
        transcribe_status_string(Int32(status.rawValue)).map { String(cString: $0) } ?? "error \(status.rawValue)"
    }

    // MARK: - Logging

    /// transcribe.cpp's and ggml's messages, as `\u{1}LEVEL\tmessage` lines on
    /// stderr, which the app keeps the tail of for its crash reports.
    /// Debug-level chatter (one line per Metal kernel compiled) is dropped
    /// unless `VTT_WORKER_LOG=debug`. Nothing here carries transcript text.
    private static let logsDebug = ProcessInfo.processInfo.environment["VTT_WORKER_LOG"] == "debug"

    private static let logLine: transcribe_log_callback = { level, message, _ in
        guard let message else { return }
        let text = String(cString: message)
        let line: String
        switch level {
        case TRANSCRIBE_LOG_LEVEL_DEBUG:
            guard logsDebug else { return }
            line = "\(TranscribeWorkerProtocol.logLinePrefix)DEBUG\t\(text)"
        case TRANSCRIBE_LOG_LEVEL_CONT:
            guard !text.isEmpty else { return }
            line = "\(TranscribeWorkerProtocol.logLinePrefix)CONT\t\(text)"
        case TRANSCRIBE_LOG_LEVEL_WARN:
            line = "\(TranscribeWorkerProtocol.logLinePrefix)WARN\t\(text)"
        case TRANSCRIBE_LOG_LEVEL_ERROR:
            line = "\(TranscribeWorkerProtocol.logLinePrefix)ERROR\t\(text)"
        default:
            line = "\(TranscribeWorkerProtocol.logLinePrefix)INFO\t\(text)"
        }
        writeToStderr(line)
    }

    static func log(_ message: String) {
        writeToStderr("\(TranscribeWorkerProtocol.logLinePrefix)WORKER\t\(message)")
    }

    private static func writeToStderr(_ line: String) {
        var line = line
        if !line.hasSuffix("\n") { line += "\n" }
        _ = TranscribeWorkerProtocol.write(Data(line.utf8), to: STDERR_FILENO)
    }

    // MARK: - Fault injection

    private enum Stage: String {
        case initialization = "init"
        case load
        case run
    }

    /// Debug builds only: `VTT_WORKER_FAULT=<crash|hang>-on-<init|load|run>`
    /// makes a worker that may use the GPU crash (a real SIGSEGV, as a faulting
    /// driver does) or hang at that stage, the way a bad GPU driver would. A
    /// CPU-only worker ignores it, so the fallback can succeed.
    private static func injectFault(at stage: Stage, cpuOnly: Bool) {
        #if DEBUG
        guard !cpuOnly, let spec = ProcessInfo.processInfo.environment["VTT_WORKER_FAULT"] else { return }
        let parts = spec.components(separatedBy: "-on-")
        guard parts.count == 2, parts[1] == stage.rawValue else { return }
        log("injected fault: \(parts[0]) at \(stage.rawValue)")
        switch parts[0] {
        case "crash":
            signal(SIGSEGV, SIG_DFL)
            raise(SIGSEGV)
        case "hang":
            while true { sleep(3600) }
        default:
            break
        }
        #endif
    }

    // MARK: - Plumbing

    /// Requests from the stdin thread to the main loop, in order.
    private final class Inbox: @unchecked Sendable {
        private let condition = NSCondition()
        private var queue: [(TranscribeWorkerProtocol.Request, [Float])] = []

        func put(_ request: TranscribeWorkerProtocol.Request, _ pcm: [Float]) {
            condition.lock()
            queue.append((request, pcm))
            condition.signal()
            condition.unlock()
        }

        func next() -> (TranscribeWorkerProtocol.Request, [Float]) {
            condition.lock()
            defer { condition.unlock() }
            while queue.isEmpty { condition.wait() }
            return queue.removeFirst()
        }
    }

    private final class AbortFlag: Sendable {
        private let raised = Atomic<Bool>(false)

        var isRaised: Bool { raised.load(ordering: .relaxed) }

        func raise() { raised.store(true, ordering: .relaxed) }

        func lower() { raised.store(false, ordering: .relaxed) }
    }
}
#endif
