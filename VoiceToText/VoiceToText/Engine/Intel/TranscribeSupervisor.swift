#if arch(x86_64)
import Darwin
import Foundation
import OSLog

/// The app's side of a transcribe.cpp worker process (`TranscribeWorker`):
/// owns at most one, starts it when something needs it, and keeps it alive
/// across the GPU failures it is there to survive.
///
/// - **Crash** — the worker's output closes (it exited, or a driver fault
///   killed it). **Hang** — a call outlives its deadline, and the worker is
///   killed. Either way the worker is gone, and its last native output goes to
///   the log.
/// - A worker that could use the GPU and is lost marks the GPU failed on this
///   Mac (`TranscribeGPUPreference`, kept across launches), and the call is
///   retried once in a CPU-only worker, which reloads the model first. A
///   CPU-only worker that crashes is retried once more; one that hangs is not,
///   since the CPU would only hang again.
/// - Cancelling the calling task stops the transcription through
///   transcribe.cpp's abort callback, which is checked between decode steps.
///   A worker that doesn't stop within `cancelGrace` (a long encoder pass) is
///   killed, and the next call starts a fresh one.
///
/// One supervisor per `TranscribeCppEngine`, as each in-process engine held a
/// model of its own: dictation and a meeting transcribed in the background
/// each have their own worker, so neither waits on the other. Calls into one
/// supervisor run one at a time, in order.
actor TranscribeSupervisor {
    typealias Loaded = TranscribeWorkerProtocol.Loaded
    typealias Transcript = TranscribeWorkerProtocol.Transcript
    typealias RunOptions = TranscribeWorkerProtocol.RunOptions

    nonisolated enum Failure: LocalizedError {
        case spawn(String)
        /// transcribe.cpp returned an error; the worker is fine.
        case remote(String, isBackendFailure: Bool)
        /// The worker exited or was killed by a signal.
        case crashed(String)
        /// The worker didn't answer in time and was killed.
        case hung(String, Duration)
        /// The worker on disk is another build: the app was updated in place.
        case versionMismatch
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .spawn(let reason):
                return "Couldn't start the transcription worker: \(reason)"
            case .remote(let message, _):
                return message
            case .crashed(let detail):
                return "The transcription worker crashed (\(detail))."
            case .hung(let what, let deadline):
                return "The transcription worker didn't finish the \(what) within \(Int(deadline.components.seconds)) s."
            case .versionMismatch:
                return "VoiceToText was updated while it was running. Quit and reopen it to transcribe."
            case .notLoaded:
                return "No transcription model is loaded."
            }
        }

        /// Whether the worker process is gone.
        var isWorkerLost: Bool {
            switch self {
            case .crashed, .hung: return true
            default: return false
            }
        }

        var isBackendFailure: Bool {
            if case .remote(_, true) = self { return true }
            return false
        }

        var isHang: Bool {
            if case .hung = self { return true }
            return false
        }
    }

    private let label: String
    private var worker: TranscribeWorkerProcess?
    /// The model the engine asked for. Outlives its worker: after a crash,
    /// hang or slow cancel, the next call starts a fresh worker for it.
    private var modelPath: String?
    /// Compute devices from the latest worker's hello.
    private(set) var devices: [TranscribeWorkerProtocol.Device] = []
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// `label` names the worker in the log: the model's catalog id.
    init(label: String) {
        self.label = label
    }

    deinit {
        worker?.terminate()
    }

    /// The model as the current worker loaded it, and where it runs.
    var loaded: Loaded? { worker?.loaded }

    /// Whether the current worker was started CPU-only.
    var isCPUOnly: Bool? { worker?.cpuOnly }

    /// The current worker's process id, while it is alive.
    var workerPID: pid_t? { worker?.isAlive == true ? worker?.pid : nil }

    /// Loads `modelPath`, replacing any model loaded before. The old worker
    /// has gone before the new one starts, so two models are never held at
    /// once.
    @discardableResult
    func load(modelPath: String) async throws -> Loaded {
        await enter()
        defer { leave() }
        if modelPath == self.modelPath, let worker = usableWorker(), let loaded = worker.loaded {
            return loaded
        }
        dropWorker()
        self.modelPath = modelPath
        do {
            let started = try await start()
            worker = started
            return started.loaded!
        } catch {
            self.modelPath = nil
            throw error
        }
    }

    /// Transcribes 16 kHz mono Float32 `samples` with the loaded model.
    func transcribe(_ samples: [Float], options: RunOptions) async throws -> Transcript {
        await enter()
        defer { leave() }
        var retried = false
        while true {
            try Task.checkCancellation()
            let current = try await ensureWorker()
            let deadline = Deadlines(onGPU: current.loaded?.onGPU ?? false).run(sampleCount: samples.count)
            do {
                let request = TranscribeWorkerProtocol.Request(kind: .transcribe, run: options)
                let response = try await call(current, request, pcm: samples, deadline: deadline, what: "transcription", cancellable: true)
                guard response.kind == .transcript, let transcript = response.transcript else {
                    throw Failure.remote("The transcription worker answered a transcription with \(response.kind).", isBackendFailure: false)
                }
                return transcript
            } catch let failure as Failure where failure.isWorkerLost || failure.isBackendFailure {
                dropWorker()
                if !current.cpuOnly {
                    TranscribeGPUPreference.markGPUFailed(
                        "During a transcription with \(label) on \(current.loaded?.device ?? "the GPU"): \(failure.localizedDescription)"
                    )
                }
                // On the CPU a hang would only hang again, and a backend
                // failure there isn't the GPU's.
                if retried || (current.cpuOnly && (failure.isHang || failure.isBackendFailure)) {
                    throw failure
                }
                retried = true
                AppLog.engine.warning("Retrying the \(self.label, privacy: .public) transcription in a fresh CPU-only worker")
            }
        }
    }

    /// Frees the model and stops the worker.
    func unload() async {
        await enter()
        defer { leave() }
        dropWorker()
        modelPath = nil
    }

    // MARK: - Workers

    /// A worker that is alive and was started the way the GPU preference now
    /// asks for. Turning the GPU switch, or a GPU failure in another engine's
    /// worker, takes effect here at the next call.
    private func usableWorker() -> TranscribeWorkerProcess? {
        guard let worker, worker.isAlive, worker.cpuOnly == !TranscribeGPUPreference.allowsGPU else { return nil }
        return worker
    }

    private func ensureWorker() async throws -> TranscribeWorkerProcess {
        if let worker = usableWorker() { return worker }
        guard modelPath != nil else { throw Failure.notLoaded }
        if worker != nil {
            AppLog.engine.info("Starting a fresh transcription worker for \(self.label, privacy: .public)")
        }
        dropWorker()
        // A start that fails leaves the model wanted: the next call tries
        // again, and says why it can't.
        let started = try await start()
        worker = started
        return started
    }

    /// Starts a worker and loads the model in it. A worker that may use the
    /// GPU and is lost on the way — registering the GPU backends, or loading
    /// the model onto it — marks the GPU failed, and the start is retried once
    /// in a CPU-only worker.
    private func start() async throws -> TranscribeWorkerProcess {
        guard let modelPath else { throw Failure.notLoaded }
        let cpuOnly = !TranscribeGPUPreference.allowsGPU
        do {
            return try await startWorker(cpuOnly: cpuOnly, modelPath: modelPath)
        } catch let failure as Failure where !cpuOnly && (failure.isWorkerLost || failure.isBackendFailure) {
            TranscribeGPUPreference.markGPUFailed("While loading \(label): \(failure.localizedDescription)")
            AppLog.engine.warning("Retrying the \(self.label, privacy: .public) load in a CPU-only worker")
            return try await startWorker(cpuOnly: true, modelPath: modelPath)
        }
    }

    private func startWorker(cpuOnly: Bool, modelPath: String) async throws -> TranscribeWorkerProcess {
        let started = ContinuousClock.now
        let process: TranscribeWorkerProcess
        do {
            process = try TranscribeWorkerProcess.spawn(cpuOnly: cpuOnly, label: label)
        } catch {
            throw Failure.spawn(error.localizedDescription)
        }
        do {
            let hello = try await call(process, .init(kind: .hello), deadline: Deadlines.hello, what: "start-up")
            guard hello.kind == .hello, hello.version == TranscribeWorkerProtocol.version else {
                throw Failure.versionMismatch
            }
            devices = hello.devices ?? []
            let request = TranscribeWorkerProtocol.Request(
                kind: .load,
                modelPath: modelPath,
                threads: Self.threadCount
            )
            let response = try await call(process, request, deadline: Deadlines.load, what: "model load")
            guard response.kind == .loaded, let loaded = response.loaded else {
                throw Failure.remote("The transcription worker answered a load with \(response.kind).", isBackendFailure: false)
            }
            process.loaded = loaded
            let elapsed = started.duration(to: .now)
            AppLog.engine.info(
                "Worker \(process.pid) loaded \(self.label, privacy: .public) on \(loaded.device, privacy: .public) (\(loaded.backend, privacy: .public)\(cpuOnly ? ", CPU-only" : "", privacy: .public)) in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)"
            )
            return process
        } catch {
            process.terminate()
            throw error
        }
    }

    private func dropWorker() {
        worker?.terminate()
        worker = nil
    }

    /// Sends `request` and waits up to `deadline` for its answer. A worker
    /// that misses the deadline is killed. With `cancellable`, cancelling the
    /// calling task asks the worker to abort, and kills it if it hasn't
    /// answered within `cancelGrace`.
    private func call(
        _ process: TranscribeWorkerProcess,
        _ request: TranscribeWorkerProtocol.Request,
        pcm: [Float] = [],
        deadline: Duration,
        what: String,
        cancellable: Bool = false
    ) async throws -> TranscribeWorkerProtocol.Response {
        let frame = try TranscribeWorkerProtocol.encode(request, pcm: pcm)
        let pending = TranscribeWorkerProcess.Call()
        let event = await withTaskCancellationHandler {
            guard await process.send(frame) else { return TranscribeWorkerProcess.Event.closed }
            return await process.receive(pending, timeout: deadline)
        } onCancel: {
            if cancellable { process.cancel(pending, grace: Deadlines.cancelGrace) }
        }
        // Stopped for a cancel — by the abort, or by killing a worker too slow
        // to abort — which is neither a crash nor a hang.
        if cancellable && Task.isCancelled {
            if case .response(let response) = event, response.kind != .aborted, response.kind != .error {
                return response
            }
            if case .timedOut = event { process.kill() }
            throw CancellationError()
        }
        switch event {
        case .response(let response):
            switch response.kind {
            case .aborted:
                throw CancellationError()
            case .error:
                throw Failure.remote(
                    response.message ?? "The transcription worker reported an error.",
                    isBackendFailure: response.isBackendFailure ?? false
                )
            default:
                return response
            }
        case .closed:
            let detail = await process.exitDescription()
            AppLog.engine.error(
                "Transcription worker \(process.pid) for \(self.label, privacy: .public) died during the \(what, privacy: .public): \(detail, privacy: .public)\(Self.formatTail(process.nativeTail()), privacy: .public)"
            )
            let last = process.nativeTail().last.map { ": \($0)" } ?? ""
            throw Failure.crashed(detail + last)
        case .timedOut:
            process.kill()
            AppLog.engine.error(
                "Transcription worker \(process.pid) for \(self.label, privacy: .public) didn't finish the \(what, privacy: .public) within \(deadline, privacy: .public); killed it\(Self.formatTail(process.nativeTail()), privacy: .public)"
            )
            throw Failure.hung(what, deadline)
        }
    }

    /// The end of the worker's output, as much as one log message holds: the
    /// last lines are the ones that say what went wrong.
    private static func formatTail(_ lines: [String]) -> String {
        var kept: [String] = []
        var bytes = 0
        for line in lines.reversed() {
            bytes += line.utf8.count + 1
            if bytes > 800 { break }
            kept.insert(line, at: 0)
        }
        return kept.isEmpty ? "" : ". Its last output:\n" + kept.joined(separator: "\n")
    }

    // MARK: - Serial calls

    private func enter() async {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        }
        busy = true
    }

    private func leave() {
        if waiting.isEmpty {
            busy = false
        } else {
            // Hand the turn straight to the next caller; `busy` stays set.
            waiting.removeFirst().resume()
        }
    }

    // MARK: - Settings

    /// Physical cores. Hyper-threads share a core's vector units: on a
    /// 4-core Intel Mac, 8 threads ran the same transcription 1.5–2× slower
    /// than 4.
    nonisolated static let threadCount: Int = {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 else { return 4 }
        return Int(cores)
    }()

    /// How long a call may take before its worker counts as hung. On a GPU a
    /// hang is recovered from (retried on the CPU), so it is caught soon; on
    /// the CPU it only decides when to give up, and a slow Mac must not look
    /// like a hung one. Handy's numbers.
    nonisolated struct Deadlines {
        /// Spawn and backend registration, which the first time after an
        /// install compiles ggml's Metal library.
        static var hello: Duration { capped(.seconds(60)) }
        /// A slow load is slow, not hung.
        static var load: Duration { capped(.seconds(180)) }
        /// How long an aborted transcription may take to stop. The abort is
        /// checked between decode steps, not inside an encoder pass.
        static var cancelGrace: Duration { capped(.seconds(10)) }

        /// A transcription has a fixed cost however short the clip: Whisper
        /// always encodes a whole 30 s window.
        let runFloor: Duration
        /// N seconds of audio may take up to this many times N.
        let audioFactor: Double

        init(onGPU: Bool) {
            runFloor = onGPU ? .seconds(60) : .seconds(300)
            audioFactor = onGPU ? 10 : 20
        }

        func run(sampleCount: Int) -> Duration {
            let audioSeconds = Double(sampleCount) / 16_000
            return Self.capped(max(runFloor, .seconds(audioSeconds * audioFactor)))
        }

        /// Debug builds only: `VTT_WORKER_DEADLINE_SECONDS` caps every
        /// deadline, so a hang test takes seconds rather than minutes.
        private static func capped(_ deadline: Duration) -> Duration {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["VTT_WORKER_DEADLINE_SECONDS"],
               let seconds = Double(raw), seconds > 0 {
                return min(deadline, .seconds(seconds))
            }
            #endif
            return deadline
        }
    }
}

/// One worker process, as `TranscribeSupervisor` drives it. Thread-safe: its
/// output is read on threads of its own, and a cancel or kill can come from
/// any thread.
nonisolated final class TranscribeWorkerProcess: @unchecked Sendable {
    enum Event: Sendable {
        case response(TranscribeWorkerProtocol.Response)
        /// The worker's output closed: it exited, crashed or was killed.
        case closed
        case timedOut
    }

    /// One request's wait for its answer, which a cancel can cut short.
    final class Call: Sendable {
        init() {}
    }

    let pid: pid_t
    let cpuOnly: Bool
    /// Set by the supervisor once the model is loaded.
    var loaded: TranscribeWorkerProtocol.Loaded? {
        get { lock.withLock { _loaded } }
        set { lock.withLock { _loaded = newValue } }
    }

    private let label: String
    private let lock = NSLock()
    private var _loaded: TranscribeWorkerProtocol.Loaded?
    private var stdinFD: Int32
    private let writer: DispatchQueue
    private let mailbox = Mailbox()
    private let tail = OutputTail()
    private let exit = ExitState()

    /// Native output lines kept for crash reports.
    static let tailLines = 64

    private init(pid: pid_t, cpuOnly: Bool, label: String, stdinFD: Int32) {
        self.pid = pid
        self.cpuOnly = cpuOnly
        self.label = label
        self.stdinFD = stdinFD
        self.writer = DispatchQueue(label: "voice-to-text-ai.VoiceToText.transcribe-worker.\(pid).stdin")
    }

    deinit {
        terminate()
    }

    /// Answering, as far as anyone knows: its output is open and nobody
    /// killed it.
    var isAlive: Bool { !mailbox.isClosed && !exit.wasKilled }

    /// Starts the app's own executable as a worker. Its pipes are the only
    /// descriptors it inherits, so its stdin closes the moment this process
    /// goes, however it goes.
    static func spawn(cpuOnly: Bool, label: String) throws -> TranscribeWorkerProcess {
        guard let executable = Bundle.main.executablePath else {
            throw SpawnError("the app's executable can't be found")
        }
        let stdinPipe = try makePipe()
        let stdoutPipe = try makePipe()
        let stderrPipe = try makePipe()
        let childEnds = [stdinPipe.read, stdoutPipe.write, stderrPipe.write]
        let parentEnds = [stdinPipe.write, stdoutPipe.read, stderrPipe.read]

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe.read, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe.write, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe.write, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Every other descriptor closes in the child, and signals start from
        // their defaults, whatever this process ignores or blocks.
        var defaults = sigset_t()
        sigfillset(&defaults)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )
        // The executable is universal. Started from an x86_64 process under
        // Rosetta, it would otherwise run as arm64 — a build with no worker in
        // it, which would start the whole app instead.
        var cpuTypes: [cpu_type_t] = [CPU_TYPE_X86 | cpu_type_t(CPU_ARCH_ABI64)]
        var cpuSubtypes: [cpu_subtype_t] = [CPU_SUBTYPE_ANY]
        var archCount = 0
        posix_spawnattr_setarchpref_np(&attributes, 1, &cpuTypes, &cpuSubtypes, &archCount)

        var arguments = [executable, TranscribeWorkerProtocol.workerFlag]
        if cpuOnly { arguments.append(TranscribeWorkerProtocol.cpuOnlyFlag) }
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        // This process's environment, built from ProcessInfo: `_NSGetEnviron`
        // isn't visible to Swift in every SDK this builds with.
        let envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        childEnds.forEach { close($0) }
        guard status == 0 else {
            parentEnds.forEach { close($0) }
            throw SpawnError(String(cString: strerror(status)))
        }
        // A write to a worker that has died fails with EPIPE rather than
        // killing the app with SIGPIPE.
        _ = fcntl(stdinPipe.write, F_SETNOSIGPIPE, 1)

        let process = TranscribeWorkerProcess(pid: pid, cpuOnly: cpuOnly, label: label, stdinFD: stdinPipe.write)
        process.startReading(stdout: stdoutPipe.read, stderr: stderrPipe.read)
        AppLog.engine.info("Started \(cpuOnly ? "CPU-only " : "", privacy: .public)transcription worker \(pid) for \(label, privacy: .public)")
        return process
    }

    // MARK: Calls

    /// Writes `frame` to the worker's stdin, off the caller's thread: a long
    /// recording is hundreds of megabytes the worker reads as it goes.
    func send(_ frame: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            writer.async { [self] in
                let fd = lock.withLock { stdinFD }
                continuation.resume(returning: fd >= 0 && TranscribeWorkerProtocol.write(frame, to: fd))
            }
        }
    }

    func receive(_ call: Call, timeout: Duration) async -> Event {
        await mailbox.next(for: call, timeout: timeout)
    }

    /// Asks the worker to abort the transcription `call` waits on, and stops
    /// that wait if no answer has come within `grace`, leaving the caller to
    /// kill the worker. The cancel is queued behind the request itself, so it
    /// can't reach the worker first.
    func cancel(_ call: Call, grace: Duration) {
        if let frame = try? TranscribeWorkerProtocol.encode(TranscribeWorkerProtocol.Request(kind: .cancel)) {
            writer.async { [self] in
                let fd = lock.withLock { stdinFD }
                if fd >= 0 { TranscribeWorkerProtocol.write(frame, to: fd) }
            }
        }
        let mailbox = self.mailbox
        DispatchQueue.global().asyncAfter(deadline: .now() + grace.timeInterval) {
            mailbox.expire(call)
        }
    }

    /// Ends the worker at once, and reaps it in the background.
    func kill() {
        exit.kill(pid)
        exit.reap(pid, grace: .seconds(1))
    }

    /// Closes the worker's stdin, which tells it to exit, and kills it if it
    /// hasn't within two seconds. Returns at once; the worker is reaped in
    /// the background.
    func terminate() {
        let fd = lock.withLock { () -> Int32 in
            let fd = stdinFD
            stdinFD = -1
            return fd
        }
        // On the writer queue, after any write still in flight.
        if fd >= 0 { writer.async { close(fd) } }
        exit.reap(pid, grace: .seconds(2))
    }

    /// How the worker ended, once its output has closed: its exit code or the
    /// signal that killed it.
    func exitDescription() async -> String {
        let exit = self.exit
        let tail = self.tail
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [pid] in
                // Let the stderr thread catch the last lines (an abort message).
                tail.waitForEnd(timeout: .seconds(1))
                exit.reap(pid, grace: .seconds(1))
                continuation.resume(returning: Self.describe(exit.waitForStatus()))
            }
        }
    }

    /// The worker's recent output, oldest first: its log lines as
    /// `LEVEL: message`, raw native output (an assert, say) as it came.
    func nativeTail() -> [String] {
        tail.lines.map { line in
            let prefix = TranscribeWorkerProtocol.logLinePrefix
            guard line.hasPrefix(prefix) else { return line }
            return String(line.dropFirst(prefix.count)).replacingOccurrences(of: "\t", with: ": ")
        }
    }

    // MARK: Plumbing

    private func startReading(stdout: Int32, stderr: Int32) {
        let mailbox = self.mailbox
        let responses = Thread {
            while true {
                do {
                    guard let (response, _) = try TranscribeWorkerProtocol.read(
                        TranscribeWorkerProtocol.Response.self,
                        from: stdout
                    ) else { break }
                    mailbox.deliver(response)
                } catch {
                    AppLog.engine.error("Couldn't read the transcription worker's answer: \(error.localizedDescription, privacy: .public)")
                    break
                }
            }
            close(stdout)
            mailbox.close()
        }
        responses.name = "transcribe-worker-\(pid)-stdout"
        responses.start()

        // Always drained: a full pipe would block the worker.
        let tail = self.tail
        let label = self.label
        let output = Thread {
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(stderr, $0.baseAddress, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                pending.append(contentsOf: buffer[0..<count])
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                    pending.removeSubrange(pending.startIndex...newline)
                    Self.forward(line, label: label)
                    tail.append(line)
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                Self.forward(line, label: label)
                tail.append(line)
            }
            close(stderr)
            tail.end()
        }
        output.name = "transcribe-worker-\(pid)-stderr"
        output.start()
    }

    /// Warnings and errors reach the app's log as they happen; the rest stays
    /// in the tail for a crash report.
    private static func forward(_ line: String, label: String) {
        let prefix = TranscribeWorkerProtocol.logLinePrefix
        guard line.hasPrefix(prefix) else {
            if !line.isEmpty {
                AppLog.engine.warning("transcribe.cpp (\(label, privacy: .public)): \(line, privacy: .public)")
            }
            return
        }
        let fields = line.dropFirst(prefix.count).split(separator: "\t", maxSplits: 1)
        guard fields.count == 2 else { return }
        let message = String(fields[1])
        switch fields[0] {
        case "ERROR":
            AppLog.engine.error("transcribe.cpp (\(label, privacy: .public)): \(message, privacy: .public)")
        case "WARN", "WORKER":
            AppLog.engine.warning("transcribe.cpp (\(label, privacy: .public)): \(message, privacy: .public)")
        default:
            break
        }
    }

    private static func describe(_ status: Int32) -> String {
        let signal = status & 0x7f
        if signal == 0 {
            return "exited with code \((status >> 8) & 0xff)"
        }
        let name = strsignal(signal).map { String(cString: $0) } ?? "signal \(signal)"
        return "killed by \(name) (signal \(signal))"
    }

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { throw SpawnError(String(cString: strerror(errno))) }
        // So a process the app starts some other way never inherits them.
        fds.forEach { _ = fcntl($0, F_SETFD, FD_CLOEXEC) }
        return (fds[0], fds[1])
    }

    private struct SpawnError: LocalizedError {
        let errorDescription: String?

        init(_ reason: String) { errorDescription = reason }
    }

    /// The worker's answers, handed from the stdout thread to the one caller
    /// waiting for them.
    private final class Mailbox: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [TranscribeWorkerProtocol.Response] = []
        private var closed = false
        private var waiter: (call: Call, continuation: CheckedContinuation<Event, Never>)?

        var isClosed: Bool { lock.withLock { closed } }

        func deliver(_ response: TranscribeWorkerProtocol.Response) {
            let resumed = lock.withLock { () -> CheckedContinuation<Event, Never>? in
                if let waiter {
                    self.waiter = nil
                    return waiter.continuation
                }
                responses.append(response)
                return nil
            }
            resumed?.resume(returning: .response(response))
        }

        func close() {
            let resumed = lock.withLock { () -> CheckedContinuation<Event, Never>? in
                closed = true
                defer { waiter = nil }
                return waiter?.continuation
            }
            resumed?.resume(returning: .closed)
        }

        /// Ends `call`'s wait with `.timedOut`, if it is still waiting.
        func expire(_ call: Call) {
            let expired = lock.withLock { () -> CheckedContinuation<Event, Never>? in
                guard let waiter, waiter.call === call else { return nil }
                self.waiter = nil
                return waiter.continuation
            }
            expired?.resume(returning: .timedOut)
        }

        func next(for call: Call, timeout: Duration) async -> Event {
            await withCheckedContinuation { continuation in
                let immediate = lock.withLock { () -> Event? in
                    if !responses.isEmpty { return .response(responses.removeFirst()) }
                    if closed { return .closed }
                    waiter = (call, continuation)
                    return nil
                }
                if let immediate {
                    continuation.resume(returning: immediate)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) { [self] in
                    expire(call)
                }
            }
        }
    }

    /// The last `tailLines` lines of the worker's stderr.
    private final class OutputTail: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: [String] = []
        private let ended = DispatchSemaphore(value: 0)

        var lines: [String] { lock.withLock { buffer } }

        func append(_ line: String) {
            lock.withLock {
                if buffer.count == TranscribeWorkerProcess.tailLines { buffer.removeFirst() }
                buffer.append(line)
            }
        }

        func end() {
            ended.signal()
        }

        func waitForEnd(timeout: Duration) {
            if ended.wait(timeout: .now() + timeout.timeInterval) == .success { ended.signal() }
        }
    }

    /// The worker's exit, collected once by `reap`. Kept apart from the
    /// process object so a reap that outlives it never touches it.
    private final class ExitState: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        private var reaping = false
        private var killed = false
        private let reaped = DispatchSemaphore(value: 0)

        var wasKilled: Bool { lock.withLock { killed } }

        func kill(_ pid: pid_t) {
            lock.withLock {
                killed = true
                // Never after the reap, when the pid may belong to someone else.
                if status == nil { _ = Darwin.kill(pid, SIGKILL) }
            }
        }

        /// Collects the exit status in the background, killing the worker if
        /// it hasn't exited within `grace`. Runs once; later calls return.
        func reap(_ pid: pid_t, grace: Duration) {
            let first = lock.withLock { () -> Bool in
                defer { reaping = true }
                return !reaping
            }
            guard first else { return }
            DispatchQueue.global().async { [self] in
                var result: Int32 = 0
                let deadline = ContinuousClock.now + grace
                var reapedPID = waitpid(pid, &result, WNOHANG)
                while reapedPID == 0 && ContinuousClock.now < deadline {
                    usleep(10_000)
                    reapedPID = waitpid(pid, &result, WNOHANG)
                }
                if reapedPID == 0 {
                    AppLog.engine.warning("Transcription worker \(pid) didn't exit within \(grace, privacy: .public); killing it")
                    _ = Darwin.kill(pid, SIGKILL)
                    reapedPID = waitpid(pid, &result, 0)
                }
                lock.withLock { status = result }
                reaped.signal()
            }
        }

        /// Blocks until `reap` has collected the status.
        func waitForStatus() -> Int32 {
            reaped.wait()
            reaped.signal()
            return lock.withLock { status ?? 0 }
        }
    }
}

private extension Duration {
    nonisolated var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
#endif
