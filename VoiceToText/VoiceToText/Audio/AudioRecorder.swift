import AppKit
import AVFoundation
import Foundation
import OSLog

/// Microphone capture for dictation.
///
/// Every AVAudioEngine lifecycle call here (`inputNode`, `prepare`, `start`,
/// `stop`, tap install/remove) is a **blocking round-trip into coreaudiod**:
/// `inputNode` alone runs `AVAudioIOUnit::GetHWFormat` → `GetSubDevices` →
/// `mach_msg`, which on a Bluetooth input can take many seconds while the link
/// renegotiates. Running those on the main actor froze the whole app — including
/// the Carbon global hotkey, which is dispatched on the main thread's event loop,
/// so the app's only way back in was dead exactly when it was needed (two
/// captured hangs, 16.4s and 21.8s, the second a main ↔ AVAudioIOUnit turnstile
/// deadlock). So: all of it runs on `engineQueue` and is awaited, bounded by a
/// timeout. A wedged CoreAudio now costs a recording, not the app.
final class AudioRecorder: @unchecked Sendable {
    private let targetSampleRate = AudioConfig.targetSampleRate
    private let tapBufferSize = AudioConfig.tapBufferSize

    // MARK: Audio-thread state

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var buffer: [Float] = []
    private let queue = DispatchQueue(label: "AudioRecorder.queue")
    private var preprocessor = AudioPreprocessor()
    /// Throttles HUD level updates to ~display cadence. The input tap fires at
    /// the hardware rate (~47/sec at 48 kHz), and each emit drives a full
    /// waveform re-render on the main actor — far more often than the eye needs.
    private var lastLevelEmitNs: UInt64 = 0
    private static let minLevelIntervalNs: UInt64 = 33_000_000  // ~30 Hz

    /// Guards the two fields below, which the tap thread shares with the
    /// restart path. Held only across trivial field access, so a watchdog
    /// asking whether capture moved can never block behind an audio-thread
    /// append the way reading `buffer` through `queue.sync` would.
    private let tapControlLock = NSLock()
    /// Samples handed to `buffer` over this recorder's whole life. Monotonic on
    /// purpose: a restart compares two readings, so it never has to care where
    /// a session boundary fell.
    private var tapSampleCount = 0
    /// Set by a restart before it re-installs the tap, consumed by the first
    /// buffer that arrives afterwards. It does two jobs the tap thread is the
    /// only one able to do safely: reset the filter state (`removeTap` does
    /// not join an in-flight callback, so no other thread provably owns the
    /// preprocessor) and close the gap measurement below.
    private var captureResuming = false
    /// Bumped for each tap installed. `removeTap` does not join an in-flight
    /// callback — this file says so in three places — so a buffer from the
    /// engine we just replaced can still arrive after the new tap is in.
    /// Stamping the tap it came from is what stops such a straggler consuming
    /// `captureResuming` and recording a one-buffer gap in place of the real
    /// hole.
    private var tapEpoch: UInt64 = 0
    /// Uptime of the most recent tap buffer, so the first buffer after a
    /// restart can measure the hole in the audio rather than the wall-clock
    /// the restart machinery took.
    private var lastTapAtNs: UInt64 = 0
    /// Audio missing from the middle of this take, summed across its restarts.
    /// A splice is invisible downstream — the buffer is a bare `[Float]` with
    /// no timestamps — so the transcript joins the two halves into a fluent
    /// sentence that is wrong, and only this number can warn anyone.
    private var restartGapSeconds: TimeInterval = 0

    // MARK: Engine state

    /// Guards every field below. Only ever held across trivial field access —
    /// never across a CoreAudio call — so it can't inherit CoreAudio's stalls.
    private let stateLock = NSLock()
    /// Serial queue owning all AVAudioEngine work. Replaced wholesale when an
    /// operation times out: the wedged block never returns, so its queue can
    /// never drain and everything behind it would inherit the stall.
    private var engineQueue = DispatchQueue(label: "AudioRecorder.engine.0")
    /// Bumped whenever the queue is abandoned. An operation carries the
    /// generation it started under and refuses to publish anything once stale,
    /// so a late-returning wedged call can't scribble over the live engine.
    private var engineGeneration: UInt64 = 0
    private var engine: AVAudioEngine?
    private var configChangeObserver: NSObjectProtocol?
    /// The engine caches its input node's format at construction; after
    /// sleep/wake or a device switch that cache goes stale and `start()` throws
    /// "formats don't match". Rather than rebuild on every start — which put a
    /// full CoreAudio device enumeration on every hotkey press — we rebuild only
    /// when we know it's stale, and `startEngine` retries once with a fresh
    /// engine if a start fails anyway, so a missed signal costs a retry, not a
    /// failed recording.
    private var needsFreshEngine = true
    private var isRecording = false
    /// Identifies the take, bumped as one starts and as one stops. Distinct
    /// from `engineGeneration`, which is the queue-abandonment token and is
    /// deliberately *not* bumped per take: two consecutive takes share a
    /// generation, so it cannot tell a restart that its own recording is over.
    /// Every deferred step of a restart carries the take it belongs to and
    /// re-checks it, because the gap between deciding to restart and finishing
    /// one spans a settle delay plus an 8 s engine-queue round trip — far too
    /// wide for a single check at the front.
    ///
    /// `abandonEngine` does not bump it: it forces `isRecording = false`
    /// instead, which is how a restart tells "my take ended normally" from
    /// "my take is still notionally running over a dead engine" — only the
    /// second has a controller left to notify.
    private var takeID: UInt64 = 0
    /// Bounds how a mid-recording configuration change is answered. Reset per
    /// session in `startEngine`, so every take gets a full restart budget.
    private var policy = AudioConfigChangePolicy()
    /// Monotonic seconds at which the current take's capture started, for the
    /// "ms into the take" figure the change log needs. Written in the same
    /// locked block that sets `isRecording`, which is what every reader is
    /// gated on.
    private var captureStartedAt: TimeInterval = 0
    /// Per-session notification counter. The whole reason this exists: the HAL
    /// posts 8-10 raw stream-format changes per attempt and nobody knows how
    /// many of those reach us, because the old handler ended the take on the
    /// first one and the rest were dropped by a state guard.
    private var configChangeOrdinal = 0
    /// `tapSampleCount` as the take began, so the change log can report what
    /// *this* take had banked rather than the counter's lifetime total.
    private var captureStartTapCount = 0
    /// `tapSampleCount` at the last point capture is known to have been
    /// working — the take's start, then each landed restart. The policy's
    /// health evidence is this compared against the live counter.
    private var healthBaselineTapCount = 0
    /// Set when a give-up has dispatched its teardown, so the rest of the
    /// burst cannot queue a second one behind it. `isRecording` stays true for
    /// the whole drain and stop round trip, so without this every further
    /// notification re-enters the teardown and the controller is told about
    /// the same interrupted take several times.
    private var teardownInFlight = false
    /// Set when a restart must not try the cheap in-place re-wire — the tap
    /// starved, so re-installing it on the same engine is the one thing we
    /// already know does not work.
    private var restartMustRebuild = false
    private var restartWork: DispatchWorkItem?
    private var starvationWork: DispatchWorkItem?
    private var deviceLogWork: DispatchWorkItem?
    /// Bumped by each published take. Answers "did a recording begin while I
    /// was tearing the last one down?" without arithmetic on `takeID`, which
    /// counts starts and stops together and cannot separate them.
    private var takesStarted: UInt64 = 0

    // MARK: Restart scheduling

    /// Owns the settle delay and the starvation check only — the restart
    /// itself hops to `engineQueue`, so nothing here can inherit a CoreAudio
    /// stall. Separate from `prewarmScheduler` because a restart must not be
    /// able to queue behind a debounced prewarm.
    private let restartScheduler = DispatchQueue(label: "AudioRecorder.restart")

    // MARK: Prewarm scheduling

    /// Owns the debounce timer only — the rebuild itself hops to `engineQueue`,
    /// so nothing here can inherit a CoreAudio stall.
    private let prewarmScheduler = DispatchQueue(label: "AudioRecorder.prewarm")
    /// Guards the two fields below. Kept separate from `stateLock` so scheduling
    /// never waits behind engine bookkeeping.
    private let prewarmLock = NSLock()
    private var pendingPrewarm: DispatchWorkItem?
    private var lastPrewarmStartedAt: Date?

    /// Collapses a burst of invalidations into a single rebuild. A route change,
    /// a sleep/wake, or another app grabbing the input fires several
    /// configuration changes back to back, and each rebuild is a multi-second
    /// device enumeration.
    private static let prewarmDebounce: DispatchTimeInterval = .milliseconds(1500)
    /// Floor between two rebuilds. A Bluetooth mic renegotiates its profile
    /// whenever anything touches the input, and every renegotiation posts a
    /// configuration change — while the rebuild itself instantiates a fresh
    /// input unit, which is another thing touching the input. Answering every
    /// change with a rebuild therefore feeds itself and pins a core (measured:
    /// `GetSubDevices` looping under AVAudioEngine's lock while the next change
    /// queued up behind it). Past this floor we simply leave the engine stale;
    /// `start()` rebuilds it, costing one slow press instead of a steady spin.
    private static let prewarmMinInterval: TimeInterval = 30

    /// Generous relative to a healthy device (well under a second) and to a
    /// Bluetooth mic waking into handsfree mode (a few seconds), but short
    /// enough that a wedged coreaudiod surfaces as a retryable error instead of
    /// an unbounded wait.
    private static let startTimeout: Duration = .seconds(8)
    private static let stopTimeout: Duration = .seconds(5)

    /// Called on the main actor when a mid-recording input configuration change
    /// could not be recovered from — the restart budget ran out, or the device
    /// really did go away. A benign change (a Bluetooth mic switching into its
    /// voice profile, which is most of them) never reaches here: capture is
    /// restarted in place and the recording continues. Recording has been
    /// stopped by the time this fires, and every sample it captured rides the
    /// callback — the controller decides whether that is a transcript or a
    /// failure card, but it is never handed nothing while audio exists.
    var onConfigurationChange: (@MainActor @Sendable ([Float]) -> Void)? {
        didSet { configCallbackArmings &+= 1 }
    }

    /// Bumped on every write to `onConfigurationChange`. `stop()` clears that
    /// callback, and a fire-and-forget stop from a take that is already over
    /// must not clear one a newer take armed — including while that take is
    /// still inside `startEngine`, where no take id or `isRecording` has moved
    /// yet. Comparing arming counts asks the question directly: is this still
    /// the callback I was handed?
    private var configCallbackArmings: UInt64 = 0

    /// Called on the main actor with a perceptual mic level (0...1) for each
    /// processed tap buffer. Used to drive the live voice indicator in the HUD.
    var onLevel: (@MainActor @Sendable (Double) -> Void)?

    /// Called on the audio thread with each processed buffer of 16 kHz mono
    /// Float32 samples, for engines that stream audio live (e.g. ElevenLabs).
    /// Set before `start()`; cleared when the streaming session ends. The same
    /// samples are still accumulated into the buffer for VAD and retry.
    var onAudioChunk: (@Sendable ([Float]) -> Void)?

    private var preprocessingEnabled: Bool {
        if let val = UserDefaults.standard.object(forKey: "audio.preprocess.enabled") as? Bool {
            return val
        }
        return DictationConfig.enableAudioPreprocessing
    }

    init() {
        // Waking invalidates the engine's cached hardware format. Rebuilding
        // here (off-main, ahead of the next hotkey press) keeps that cost off
        // the press itself. Long-lived object — no deinit teardown needed.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateEngine()
        }
    }

    // MARK: - Lifecycle

    /// Starts capture. Throws `AudioRecorderError.deviceUnresponsive` if
    /// CoreAudio doesn't answer within `startTimeout` — the caller should
    /// surface that as a retryable error rather than waiting it out.
    func start() async throws {
        try await runOnEngineQueue(timeout: Self.startTimeout) { generation in
            try self.startEngine(generation: generation)
        }
    }

    /// Stops capture and returns everything captured. Never throws: if the
    /// engine teardown wedges we still hand back the audio, which lives on a
    /// separate queue and is reachable regardless.
    ///
    /// `prewarming` is false only on the configuration-change path: rebuilding
    /// the engine in direct response to a route change is what turns a single
    /// Bluetooth renegotiation into a self-feeding storm of HAL enumerations.
    func stop(prewarming: Bool = true, forTake fencedTake: UInt64? = nil) async -> [Float] {
        let armingAtEntry = stateLock.withLock { configCallbackArmings }
        let samples: [Float]
        do {
            samples = try await runOnEngineQueue(timeout: Self.stopTimeout) { generation in
                self.stopEngine(generation: generation, takeID: fencedTake)
            }
        } catch {
            AppLog.audio.error("Audio engine stop timed out; recovering buffered audio")
            samples = drainBuffer()
        }
        // C4: clearing this disarms device-change detection, and a
        // fire-and-forget stop from a take that is already over must not
        // disarm the take that replaced it — that leaves the new recording
        // deaf to the next change and wedged in `.recording` over a dead
        // engine. The identity of the callback, not a count of takes: a newer
        // take arms its own before `startEngine` publishes, so nothing about
        // `takeID` or `isRecording` has moved yet at the moment it matters.
        let ownsCallback = stateLock.withLock { configCallbackArmings == armingAtEntry }
        if ownsCallback { onConfigurationChange = nil }
        if prewarming { prewarm() }
        return samples
    }

    /// Waits one drain interval before tearing the tap down so the in-flight
    /// tap buffer reaches our callback — without it the last word gets cut.
    /// Cancel paths can still use plain `stop()` since they discard audio.
    func flushAndStop() async -> [Float] {
        guard stateLock.withLock({ isRecording }) else { return [] }
        try? await Task.sleep(for: Self.drainDuration)
        return await stop()
    }

    /// Pays the CoreAudio device-enumeration cost ahead of time, on the engine
    /// queue, so the next hotkey press doesn't have to wait for it. Fire and
    /// forget; debounced and rate-limited, and a no-op when the cached engine is
    /// already good.
    func prewarm() {
        let item = DispatchWorkItem { [weak self] in self?.performPrewarm() }
        let superseded: DispatchWorkItem? = prewarmLock.withLock {
            let previous = pendingPrewarm
            pendingPrewarm = item
            return previous
        }
        superseded?.cancel()
        prewarmScheduler.asyncAfter(deadline: .now() + Self.prewarmDebounce, execute: item)
    }

    private func performPrewarm() {
        let withinFloor = prewarmLock.withLock { () -> Bool in
            pendingPrewarm = nil
            guard let last = lastPrewarmStartedAt else { return false }
            return Date().timeIntervalSince(last) < Self.prewarmMinInterval
        }
        guard !withinFloor else {
            // Leaving the engine stale is always safe: `start()` rebuilds it.
            AppLog.audio.info("Skipping audio engine prewarm; rebuilt too recently")
            return
        }

        let (queue, generation) = stateLock.withLock { (engineQueue, engineGeneration) }
        queue.async {
            let shouldWarm = self.stateLock.withLock {
                self.engineGeneration == generation
                    && !self.isRecording
                    && (self.needsFreshEngine || self.engine == nil)
            }
            guard shouldWarm else { return }
            // Stamped only when a rebuild actually happens, so a run of no-op
            // prewarms can't consume the floor and starve a real one.
            self.prewarmLock.withLock { self.lastPrewarmStartedAt = Date() }
            do {
                // Touching `inputNode` is what triggers the expensive HAL
                // enumeration — the whole point of prewarming.
                _ = try self.makeEngine(generation: generation).inputNode
                AppLog.audio.info("Audio engine prewarmed")
            } catch {
                AppLog.audio.warning("Audio engine prewarm failed: \(error.localizedDescription)")
            }
        }
    }

    /// Marks the cached engine stale and rebuilds it in the background.
    func invalidateEngine() {
        stateLock.withLock { needsFreshEngine = true }
        prewarm()
    }

    // MARK: - Engine queue

    /// Runs blocking CoreAudio work on the engine queue, bounded by `timeout`.
    /// On timeout the queue is abandoned and the operation's generation retired,
    /// so the still-running call can't publish anything and the next attempt
    /// starts on a fresh queue instead of stacking up behind the wedge.
    private func runOnEngineQueue<T: Sendable>(
        timeout: Duration,
        _ work: @escaping @Sendable (UInt64) throws -> T
    ) async throws -> T {
        let (queue, generation) = stateLock.withLock { (engineQueue, engineGeneration) }
        let gate = TimeoutGate()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let result = Result { try work(generation) }
                if gate.resolve() { continuation.resume(with: result) }
            }
            // Detached on purpose: the countdown itself must not depend on the
            // executor that called us. The bookkeeping hop back to the main
            // actor is only lock-guarded field swaps — no CoreAudio, so nothing
            // there can stall.
            Task.detached { [weak self] in
                try? await Task.sleep(for: timeout)
                guard gate.resolve() else { return }
                AppLog.audio.error("CoreAudio did not respond within \(timeout, privacy: .public); abandoning engine")
                if let recorder = self {
                    await MainActor.run { recorder.abandonEngine(staleGeneration: generation) }
                }
                continuation.resume(throwing: AudioRecorderError.deviceUnresponsive)
            }
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        stateLock.withLock { engineGeneration == generation }
    }

    /// Whether the take a deferred restart step belongs to is still the one
    /// being recorded.
    private func isCurrentTake(_ id: UInt64) -> Bool {
        stateLock.withLock { takeID == id && isRecording }
    }

    /// Runs `body` under `stateLock` only while `id` is still this recorder's
    /// take, and reports whether it ran. `policy` and the restart bookkeeping
    /// are shared across takes: a step whose take is gone must not clear the
    /// live take's in-flight flag or spend its budget. Deliberately does not
    /// require `isRecording` — `abandonEngine` clears that without ending the
    /// take, and those steps still have work to do.
    @discardableResult
    private func withTake<T>(_ id: UInt64, _ body: () -> T) -> T? {
        stateLock.withLock { takeID == id ? body() : nil }
    }

    /// Retires the wedged generation and its queue. The in-flight operation is
    /// left to finish (or not) in its own sandbox; it tears down whatever it
    /// built once it notices its generation is stale.
    private func abandonEngine(staleGeneration: UInt64) {
        // The retired engine leaves the lock alive and dies in `retire`: this
        // runs on main, where its dealloc is exactly what must not happen.
        let (observer, retired) = stateLock.withLock { () -> (NSObjectProtocol?, AVAudioEngine?) in
            guard engineGeneration == staleGeneration else { return (nil, nil) }
            engineGeneration &+= 1
            engineQueue = DispatchQueue(label: "AudioRecorder.engine.\(engineGeneration)")
            let observer = configChangeObserver
            let previous = engine
            configChangeObserver = nil
            engine = nil
            needsFreshEngine = true
            isRecording = false
            return (observer, previous)
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        Self.retire(retired)
    }

    /// How long a retired engine is held before its last reference is dropped.
    /// Longer than the HAL's burst of configuration changes for one route
    /// switch, which is what a notification still in flight is riding on.
    private static let retireGrace: DispatchTimeInterval = .seconds(3)

    /// Drops a retired engine's last reference on a thread nothing waits on.
    ///
    /// `-[AVAudioEngine dealloc]` does a `dispatch_sync` onto the engine's own
    /// private queue, and that queue may be blocked posting an
    /// `AVAudioEngineConfigurationChange` to our `queue: .main` observer. So the
    /// release may never happen on main, which the post is waiting for, nor
    /// under `stateLock`, which the observer takes to answer, nor on
    /// `engineQueue`, where a dealloc blocked in CoreAudio would stall the next
    /// start. The grace keeps our own reference alive past the burst, so a
    /// notification still in flight is never left holding the last one.
    private static func retire(_ engine: AVAudioEngine?) {
        guard let engine else { return }
        // `unsafe` only because `Unmanaged` carries a non-Sendable instance. The
        // +1 is what stops the caller from ever owning the final release.
        nonisolated(unsafe) let handoff = Unmanaged.passRetained(engine)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.retireGrace) {
            handoff.release()
        }
    }

    // MARK: - Engine queue work

    private func startEngine(generation: UInt64) throws {
        cancelPendingRestartWork()
        cancelPendingDeviceLog()
        preprocessor.reset()
        queue.sync { buffer.removeAll(keepingCapacity: true) }
        targetFormat = try makeTargetFormat()
        let tapCountAtStart = tapControlLock.withLock { () -> Int in
            captureResuming = false
            restartGapSeconds = 0
            lastTapAtNs = 0
            return tapSampleCount
        }
        stateLock.withLock {
            policy.reset()
            teardownInFlight = false
            restartMustRebuild = false
            configChangeOrdinal = 0
            captureStartTapCount = tapCountAtStart
            healthBaselineTapCount = tapCountAtStart
        }

        do {
            try attachAndStart(generation: generation, forceFresh: false)
        } catch {
            // Don't retry under a retired generation — our queue was abandoned
            // and nothing we build can be published anyway.
            guard isCurrent(generation) else { throw error }
            // Most likely the cached engine's input format went stale without us
            // seeing the invalidation signal ("formats don't match"). One rebuild
            // and retry is what makes reusing an engine safe at all.
            AppLog.audio.warning("Engine start failed (\(error.localizedDescription)); retrying with a fresh engine")
            try attachAndStart(generation: generation, forceFresh: true)
        }

        let published = stateLock.withLock { () -> Bool in
            guard engineGeneration == generation else { return false }
            isRecording = true
            takeID &+= 1
            takesStarted &+= 1
            captureStartedAt = Self.monotonicNow()
            return true
        }
        guard published else { throw AudioRecorderError.superseded }
        logInputDevice()
    }

    /// Delay past the Bluetooth profile switch our own `start()` provokes, so
    /// the read lands on a settled HAL rather than a contended one.
    private static let deviceLogDelay: DispatchTimeInterval = .seconds(1)

    /// Names the microphone in the log, once per take. Dispatched to a queue
    /// nothing waits on and deliberately not to `engineQueue`: a HAL property
    /// read can block for seconds while a Bluetooth link renegotiates, and a
    /// diagnostic must never be able to delay a restart — or a Stop — queued
    /// behind it.
    ///
    /// A new take drops the previous take's read *if it has not started yet* —
    /// `DispatchWorkItem.cancel()` cannot stop one already executing, and this
    /// runs on a concurrent global queue, so a read already blocked in the HAL
    /// keeps blocking. Cancellation narrows the overlap; it does not prevent
    /// it. That is acceptable precisely because nothing waits on this queue:
    /// the worst case is one stale log line and a thread parked in coreaudiod.
    ///
    /// It deliberately survives its own take ending: a sub-second take that
    /// died to a device change is exactly the one whose microphone we want
    /// named, and by then nothing is contending for the HAL anyway.
    private func logInputDevice() {
        let item = DispatchWorkItem {
            AppLog.audio.notice("Capture input device: \(AudioDeviceProbe.defaultInputSummary(), privacy: .public)")
        }
        stateLock.withLock { deviceLogWork = item }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.deviceLogDelay, execute: item)
    }

    /// Dropped as a new take begins, so a pending read can never take HAL
    /// locks while this start is negotiating with the same device.
    private func cancelPendingDeviceLog() {
        let pending = stateLock.withLock { () -> DispatchWorkItem? in
            let previous = deviceLogWork
            deviceLogWork = nil
            return previous
        }
        pending?.cancel()
    }

    @discardableResult
    private func attachAndStart(
        generation: UInt64,
        forceFresh: Bool,
        awaitingSettle: Bool = false,
        resuming: Bool = false
    ) throws -> AVAudioEngine {
        let engine = try makeEngine(generation: generation, forceFresh: forceFresh)
        try installTapAndStart(on: engine, awaitingSettle: awaitingSettle, resuming: resuming)
        return engine
    }

    /// Re-wires the input graph onto whatever the hardware currently is and
    /// starts it. Split out of `attachAndStart` because the restart path needs
    /// exactly this against an engine it already has, without paying for
    /// another device enumeration.
    private func installTapAndStart(
        on engine: AVAudioEngine,
        awaitingSettle: Bool = false,
        resuming: Bool = false
    ) throws {
        let input = engine.inputNode
        try probeInputAvailability(on: input, awaitingSettle: awaitingSettle)
        // A reused engine may still carry the previous session's tap.
        input.removeTap(onBus: 0)
        // The resume flag is armed in the same lock hold that stamps the new
        // tap, and not a moment earlier. Armed at the top of the restart it
        // spent `removeTap`, `stop()` and up to 300 ms of probing matching the
        // *outgoing* tap's epoch, so a straggler from the tap being torn down
        // could consume it and bank its own inter-buffer time as the gap —
        // losing the real hole entirely. Nothing can reach `handle` with this
        // epoch until `installTap` below.
        let epoch = tapControlLock.withLock { () -> UInt64 in
            tapEpoch &+= 1
            if resuming { captureResuming = true }
            return tapEpoch
        }
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil) { [weak self] pcmBuffer, _ in
            self?.handle(inputBuffer: pcmBuffer, tapEpoch: epoch)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Reads at 0 / 120 / 300 ms, stopping at the first usable answer.
    private static let inputProbeRetryDelays: [TimeInterval] = [0.120, 0.180]

    /// Apple's documented test for "is input enabled": a non-zero sample rate
    /// and channel count on the input node's hardware format. Two things make
    /// it worth doing before every tap install.
    ///
    /// Installing a tap on an input node reporting `0 ch, 0 Hz` raises an ObjC
    /// exception Swift cannot catch, so the probe is what turns a dead device
    /// into a clean throw instead of a crash on the audio path. And the read is
    /// retried because a real profile switch dips through exactly that state:
    /// the captured trace shows `0 ch, 0 Hz` for 22 ms in the middle of the
    /// renegotiation, so a single read there would end a take over a device
    /// that was already coming back. An unusable answer is never treated as
    /// device loss on its own — it throws, and the restart budget decides.
    private func probeInputAvailability(on input: AVAudioInputNode, awaitingSettle: Bool) throws {
        var format = input.inputFormat(forBus: 0)
        var reads = 1
        // Only a restart waits. A cold start has no take to protect and no
        // renegotiation in flight, so a Mac with no working input would
        // otherwise pay the whole ladder on the engine queue on every single
        // hotkey press, forever.
        for delay in (awaitingSettle ? Self.inputProbeRetryDelays : []) {
            if format.sampleRate > 0 && format.channelCount > 0 { break }
            Thread.sleep(forTimeInterval: delay)
            format = input.inputFormat(forBus: 0)
            reads += 1
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioRecorderError.inputUnavailable
        }
        // `.notice` rather than `.info`: info is memory-only and does not reach
        // the log archive, which is why the first investigation into this bug
        // could not tell "never captured anything" from "the logs aged out".
        AppLog.audio.notice("Input hardware format: \(Int(format.sampleRate)) Hz, \(format.channelCount) ch (\(reads) read(s) to settle)")
    }

    /// Returns the cached engine when it's still trustworthy, otherwise builds
    /// and publishes a fresh one. Callers must be on the engine queue.
    private func makeEngine(generation: UInt64, forceFresh: Bool = false) throws -> AVAudioEngine {
        let cached: AVAudioEngine? = stateLock.withLock {
            guard engineGeneration == generation, !needsFreshEngine, !forceFresh else { return nil }
            return engine
        }
        if let cached { return cached }

        // Fenced like every other publish in this file. Unfenced, a work item
        // queued behind a wedge on an abandoned queue still runs later, fails
        // the cached check above on its stale generation, and then nils the
        // *live* engine and removes the *live* observer on its way to throwing
        // `.superseded` — leaving an in-progress recording with no
        // device-change detection at all. Every restart path routes through
        // here, so this is newly reachable.
        let (staleObserver, staleEngine) = try stateLock.withLock { () throws -> (NSObjectProtocol?, AVAudioEngine?) in
            guard engineGeneration == generation else { throw AudioRecorderError.superseded }
            let observer = configChangeObserver
            let retired = engine
            configChangeObserver = nil
            engine = nil
            return (observer, retired)
        }
        if let staleObserver { NotificationCenter.default.removeObserver(staleObserver) }
        Self.retire(staleEngine)

        let fresh = AVAudioEngine()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: fresh,
            queue: .main
        ) { [weak self] notification in
            self?.handleConfigurationChange(from: notification.object as? AVAudioEngine)
        }

        let published = stateLock.withLock { () -> Bool in
            guard engineGeneration == generation else { return false }
            engine = fresh
            configChangeObserver = observer
            needsFreshEngine = false
            return true
        }
        guard published else {
            NotificationCenter.default.removeObserver(observer)
            throw AudioRecorderError.superseded
        }
        return fresh
    }

    /// `takeID` fences the teardown to one take: the salvage path decides to
    /// stop a take and then waits out a drain interval plus this round trip
    /// before it lands, which is long enough for the user's own Stop to finish
    /// and a new take to begin.
    private func stopEngine(generation: UInt64, takeID fencedTake: UInt64?) -> [Float] {
        let engine: AVAudioEngine? = stateLock.withLock {
            guard engineGeneration == generation, isRecording else { return nil }
            if let fencedTake, takeID != fencedTake { return nil }
            isRecording = false
            takeID &+= 1
            return self.engine
        }
        guard let engine else { return [] }
        cancelPendingRestartWork()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // A restart whose audio never came back leaves the measurement open,
        // and that is the case where the loss was largest — the take would
        // have been the one take not to warn anybody.
        tapControlLock.withLock {
            if captureResuming { closeCaptureGapLocked(at: DispatchTime.now().uptimeNanoseconds) }
            captureResuming = false
        }
        return drainBuffer()
    }

    /// Drops the settle delay and the starvation check left over from a
    /// restart, so a recording path cannot accumulate timers that outlive
    /// their take — the shape `prewarmDebounce` and `prewarmMinInterval` were
    /// added to contain.
    ///
    /// Best-effort only, and never the thing that makes a restart safe. It
    /// cannot reach a work item already dequeued, and it cannot reach into a
    /// restart in flight at all: that one is parked on the engine queue behind
    /// an 8 s timeout, and it will come back and want to publish. What makes
    /// those safe is the `takeID` every deferred step carries and re-checks.
    private func cancelPendingRestartWork() {
        let (restart, starvation) = stateLock.withLock {
            let items = (restartWork, starvationWork)
            restartWork = nil
            starvationWork = nil
            return items
        }
        restart?.cancel()
        starvation?.cancel()
    }

    /// Adds the hole between the last buffer and `nowNs` to this take's total.
    /// Caller holds `tapControlLock`. Clamped rather than trusted: two tap
    /// objects can briefly overlap across a restart, and an out-of-order pair
    /// would otherwise wrap into a gap of several centuries.
    private func closeCaptureGapLocked(at nowNs: UInt64) {
        guard lastTapAtNs != 0, nowNs > lastTapAtNs else { return }
        restartGapSeconds += Double(nowNs - lastTapAtNs) / 1_000_000_000
    }

    /// Audio this take lost to the middle of itself, summed over its
    /// restarts. Read once the take is over, when no tap can still be running:
    /// pulled rather than pushed through a fourth callback property, because
    /// the three this class already has are plain unguarded fields written on
    /// main and read from the realtime thread, and a fourth would widen a race
    /// rather than add a feature.
    func interruptionGapSeconds() -> TimeInterval {
        tapControlLock.withLock { restartGapSeconds }
    }

    /// Monotonic seconds for the restart budget. `Date` is not: a clock
    /// adjustment mid-take must not expire — or silently extend — a deadline.
    private static func monotonicNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    private func drainBuffer() -> [Float] {
        queue.sync {
            let result = buffer
            buffer.removeAll(keepingCapacity: false)
            return result
        }
    }

    // 2× tap buffer leaves margin for HAL scheduling jitter.
    private static let drainDuration: Duration = {
        let bufferSeconds = Double(AudioConfig.tapBufferSize) / AudioConfig.targetSampleRate
        return .milliseconds(Int((bufferSeconds * 2 * 1000).rounded(.up)))
    }()

    /// Everything one notification's outcome needs, read under `stateLock`
    /// and acted on outside it. `takeID` rides along so the decision and the
    /// take it was made for cannot drift apart between the two.
    private struct ConfigChangeReport {
        let takeID: UInt64
        let ordinal: Int
        let sinceCaptureStart: TimeInterval
        let capturedInTake: Int
        let budgetSpent: Int
    }

    private enum ConfigChangeRoute {
        /// Posted by an engine we have already replaced.
        case stale
        case idle
        case recording(ConfigChangeReport, AudioConfigChangePolicy.Decision)
    }

    /// Runs on the main thread (the observer is registered with `queue: .main`)
    /// and must stay that way: lock-guarded field swaps and a dispatch, never a
    /// CoreAudio call. Everything the answer costs happens on `engineQueue`.
    private func handleConfigurationChange(from posting: AVAudioEngine?) {
        let now = Self.monotonicNow()
        // Read before taking `stateLock`, never inside it: the two locks are
        // only ever held one at a time.
        let tapCount = tapControlLock.withLock { tapSampleCount }
        let route: ConfigChangeRoute = stateLock.withLock {
            // A change posted by an engine `makeEngine` already swapped out can
            // still be sitting on the main queue when `removeObserver` runs.
            // The notification names its poster, so that one is free to drop —
            // it used to be discarded, which made a spurious call
            // indistinguishable from a real device change.
            guard posting == nil || posting === engine else { return .stale }
            needsFreshEngine = true
            guard isRecording else { return .idle }
            configChangeOrdinal += 1
            // Healthy means the tap has delivered audio since the last restart
            // landed — or since capture began, if none has. It is what lets
            // the policy tell an unrelated route change minutes later from
            // another notification in the burst it is already answering.
            let decision = policy.changeObserved(
                now: now,
                captureHealthy: tapCount > healthBaselineTapCount
            )
            return .recording(
                ConfigChangeReport(
                    takeID: takeID,
                    ordinal: configChangeOrdinal,
                    sinceCaptureStart: now - captureStartedAt,
                    capturedInTake: tapCount - captureStartTapCount,
                    budgetSpent: policy.restartsUsed
                ),
                decision
            )
        }

        switch route {
        // Worth a line: this filter is what stops a swapped-out engine's
        // straggler from being answered as a live device change, and nothing
        // else would show that it ever fires.
        case .stale:
            AppLog.audio.notice("Ignoring an audio configuration change from a replaced engine")

        // Idle: no recording to salvage and nobody to notify, so don't touch
        // CoreAudio from here. A prewarmed app holds a live input unit, so it
        // receives every route change the machine sees — and a Bluetooth mic
        // renegotiates constantly. Tearing the engine down and rebuilding it on
        // each one is what pinned a core: the rebuild's `GetSubDevices` held
        // AVAudioEngine's lock for seconds while the next change queued behind
        // it. Marking the engine stale is the whole obligation; the debounced
        // prewarm rebuilds once the hardware settles, and `start()` rebuilds
        // regardless if it hasn't.
        case .idle:
            prewarm()

        case .recording(let report, let decision):
            // Logged for every notification, including the ones a restart in
            // flight absorbs: how many of the HAL's 8-10 per-attempt format
            // changes actually reach us is what sizes the restart budget, and
            // the spend is printed alongside so the burst window can be read
            // straight off the log.
            AppLog.audio.warning("Audio configuration change #\(report.ordinal) at \(Int(report.sinceCaptureStart * 1000)) ms into capture, \(report.capturedInTake) samples in, \(report.budgetSpent)/\(AudioConfigChangePolicy.defaultMaxRestarts) restarts spent: \(decision.description, privacy: .public)")
            applyRestartDecision(decision, for: report.takeID)
        }
    }

    private func applyRestartDecision(_ decision: AudioConfigChangePolicy.Decision, for takeID: UInt64) {
        switch decision {
        case .ignoreCoalesced:
            return
        case .scheduleRestart(let after):
            scheduleRestart(after: after, for: takeID)
        case .giveUp(let reason):
            guard claimTeardown(for: takeID) else { return }
            AppLog.audio.error("Ending the take after an audio configuration change: \(reason.description, privacy: .public)")
            Task.detached { [weak self] in await self?.salvageAndTeardown(for: takeID) }
        }
    }

    /// Claims the one teardown a take is allowed. `isRecording` stays true
    /// across the drain and the stop round trip, so without this latch every
    /// remaining notification of a burst starts another teardown and the
    /// controller hears about the same interrupted take several times.
    private func claimTeardown(for takeID: UInt64) -> Bool {
        withTake(takeID) { () -> Bool in
            guard !teardownInFlight else { return false }
            teardownInFlight = true
            return true
        } ?? false
    }

    private func scheduleRestart(after delay: TimeInterval, for takeID: UInt64) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Detached so the engine-queue round trip never runs on whatever
            // executor happens to be awaiting us — same rule as `start()`.
            Task.detached { await self.performRestart(for: takeID) }
        }
        stateLock.withLock { restartWork = item }
        restartScheduler.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Answers a configuration change by restarting capture instead of ending
    /// the take. Exactly one `runOnEngineQueue` item, never nested inside
    /// another: `engineQueue` is serial, so an inner dispatch could never run
    /// and would burn its whole timeout before abandoning the queue its own
    /// caller is running on.
    private func performRestart(for takeID: UInt64) async {
        guard isCurrentTake(takeID) else {
            // The take ended (or its queue was abandoned) while the settle
            // delay ran. Fenced: if a *newer* take is running, its policy is
            // its own and clearing its in-flight flag here would let two
            // restarts run at once.
            withTake(takeID) { policy.restartAbandoned() }
            return
        }
        withTake(takeID) { policy.restartBegan() }

        let started = Self.monotonicNow()
        do {
            let capturedAtRestart = try await runOnEngineQueue(timeout: Self.startTimeout) { generation in
                try self.restartEngine(generation: generation, takeID: takeID)
            }
            let now = Self.monotonicNow()
            // Re-checked, not assumed: the take can end anywhere in the 8 s
            // this round trip is allowed to take, and everything below
            // publishes something. An unfenced tail arms a watchdog for a dead
            // take and can hand `.scheduleRestart` to whichever take is
            // current by then.
            let stillRecording = stateLock.withLock { () -> Bool in
                guard self.takeID == takeID, isRecording else { return false }
                // The baseline the next change's health evidence is measured
                // against: audio banked after this point is proof the restart
                // really worked, not just that it returned.
                healthBaselineTapCount = capturedAtRestart
                return true
            }
            guard stillRecording else {
                AppLog.audio.notice("Capture restarted into a take that had already ended; leaving it torn down")
                withTake(takeID) { policy.restartAbandoned() }
                return
            }
            AppLog.audio.warning("Capture restarted in \(Int((now - started) * 1000)) ms after an audio configuration change")
            armStarvationWatchdog(capturedAtRestart: capturedAtRestart, takeID: takeID)
            // The device may not be the one the take started on, and the log
            // still names that one.
            logInputDevice()
            guard let decision = withTake(takeID, { policy.restartSucceeded(now: now) }) else { return }
            applyRestartDecision(decision, for: takeID)
        } catch {
            let elapsed = Int((Self.monotonicNow() - started) * 1000)
            switch failureOutcome(for: takeID) {
            case .takeAlreadyOver:
                // A normal Stop got there first. Nobody is waiting on this,
                // and the policy now belongs to whatever take replaced ours.
                AppLog.audio.notice("Capture restart dropped after \(elapsed) ms: its take had already ended")
                withTake(takeID) { policy.restartAbandoned() }
            case .abandonedMidTake:
                // A timeout abandoned the queue under us and `abandonEngine`
                // already forced `isRecording = false` without telling anyone.
                // Returning quietly here is what leaves the controller in
                // `.recording` over a dead engine with the clock still running.
                AppLog.audio.error("Capture restart failed after \(elapsed) ms: \(error.localizedDescription)")
                guard claimTeardown(for: takeID) else { return }
                await salvageAndTeardown(for: takeID)
            case .stillRecording:
                AppLog.audio.error("Capture restart failed after \(elapsed) ms: \(error.localizedDescription)")
                guard let decision = withTake(takeID, { policy.restartFailed(now: Self.monotonicNow()) }) else { return }
                applyRestartDecision(decision, for: takeID)
            }
        }
    }

    private enum RestartFailureOutcome {
        case stillRecording
        case abandonedMidTake
        case takeAlreadyOver
    }

    /// Which of the three a failed restart is deciding between. The take id
    /// separates them: a Stop bumps it, while `abandonEngine` leaves it alone
    /// and clears `isRecording` — so an unchanged id with no recording is a
    /// take that still has a controller sitting in `.recording`.
    private func failureOutcome(for takeID: UInt64) -> RestartFailureOutcome {
        stateLock.withLock {
            guard self.takeID == takeID else { return .takeAlreadyOver }
            return isRecording ? .stillRecording : .abandonedMidTake
        }
    }

    /// Runs on the engine queue. Keeps `buffer`, `isRecording`, all three
    /// callbacks and any live streaming session: the take loses only the
    /// ~300 ms the hardware spent renegotiating, spliced out silently because
    /// both halves arrive already resampled to the target format.
    ///
    /// `isRecording` deliberately stays true throughout. It is what keeps
    /// `performPrewarm` ineligible to replace the engine mid-restart, what lets
    /// a user Stop enqueued behind us still tear down and drain, and what keeps
    /// `flushAndStop` from short-circuiting to `[]`.
    ///
    /// Returns the capture counter at the moment the restart succeeded, for the
    /// starvation watchdog to compare against.
    private func restartEngine(generation: UInt64, takeID: UInt64) throws -> Int {
        guard isCurrent(generation) else { throw AudioRecorderError.superseded }
        // The engine queue is serial, so a Stop cannot interleave with this —
        // but it can have completed while this item sat in the queue, and a
        // generation check would not notice: a normal Stop does not retire the
        // generation. Without this, a restart dequeued after its own Stop
        // re-installs the tap and starts the engine, leaving a hot mic and a
        // lit recording indicator behind a take that is over.
        guard isCurrentTake(takeID) else { throw AudioRecorderError.takeEnded }
        // Both branches below pass `resuming: true`, so whichever installs the
        // next tap arms the filter reset and the gap measurement with it.
        let (existing, mustRebuild) = stateLock.withLock { () -> (AVAudioEngine?, Bool) in
            let forced = restartMustRebuild
            restartMustRebuild = false
            return (engine, forced)
        }

        let running: AVAudioEngine
        if let existing, !mustRebuild {
            do {
                try rewireInPlace(existing, generation: generation)
                running = existing
            } catch {
                // Escalation, not the first resort: a fresh engine means
                // another `GetSubDevices` enumeration and another private
                // aggregate device — the most expensive possible recovery, and
                // itself another thing touching the input.
                AppLog.audio.warning("In-place capture re-wire failed (\(error.localizedDescription)); rebuilding the engine")
                running = try attachAndStart(
                    generation: generation, forceFresh: true, awaitingSettle: true, resuming: true
                )
            }
        } else {
            running = try attachAndStart(
                generation: generation, forceFresh: true, awaitingSettle: true, resuming: true
            )
        }

        guard isCurrent(generation) else { throw AudioRecorderError.superseded }
        guard isCurrentTake(takeID) else {
            // A Stop landed while we were re-wiring. It already tore down the
            // engine it knew about, and we have just started one again — so
            // undo it here rather than hand the user a microphone nothing owns.
            running.inputNode.removeTap(onBus: 0)
            running.stop()
            throw AudioRecorderError.takeEnded
        }
        // A restart pays the same HAL cost a prewarm does, so it stamps the
        // same floor: otherwise `stop(prewarming: true)` at the end of the
        // session rebuilds all over again 1.5 s after the device finally
        // settled.
        prewarmLock.withLock { lastPrewarmStartedAt = Date() }
        return tapControlLock.withLock { tapSampleCount }
    }

    /// Apple's documented recovery for this notification — re-wire the
    /// connections and start the engine — on the engine object we already
    /// have. The per-engine observer is bound to that same object, so nothing
    /// needs re-registering and no notification can be missed across the seam.
    private func rewireInPlace(_ engine: AVAudioEngine, generation: UInt64) throws {
        engine.inputNode.removeTap(onBus: 0)
        // Idempotent: AVFoundation stops and uninitializes the engine itself
        // before posting the change. Cheap insurance for the cases where it
        // didn't — a change posted for the output side, or a duplicate.
        engine.stop()
        try installTapAndStart(on: engine, awaitingSettle: true, resuming: true)
        // The handler marked the engine stale on its way in. It is now running
        // against the current hardware format, which is exactly what the flag
        // is about, so clearing it keeps the next prewarm from rebuilding an
        // engine that is already correct.
        stateLock.withLock {
            guard engineGeneration == generation else { return }
            needsFreshEngine = false
        }
    }

    /// A tap installed while the hardware was still flapping can anchor to a
    /// rate the device no longer runs at and then deliver nothing at all, with
    /// no error anywhere. Nothing downstream would notice until the VAD gate
    /// rejected a full-length silent take, so a restart has to prove capture
    /// actually resumed.
    private func armStarvationWatchdog(capturedAtRestart: Int, takeID: UInt64) {
        let grace = stateLock.withLock { policy.captureStarvation }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isCurrentTake(takeID) else { return }
            guard self.tapControlLock.withLock({ self.tapSampleCount }) == capturedAtRestart else { return }
            AppLog.audio.error("Capture delivered nothing in the \(Int(grace * 1000)) ms after a restart; treating the tap as dead")
            // Re-installing the same tap on the same engine is the one thing
            // this take has already proved does not work, so the escalation
            // goes straight to a fresh engine — which is what the fallback
            // exists for, and which a starved tap never reaches on its own
            // because nothing threw.
            guard let decision = self.withTake(takeID, { () -> AudioConfigChangePolicy.Decision in
                self.restartMustRebuild = true
                self.needsFreshEngine = true
                return self.policy.captureStarved(now: Self.monotonicNow())
            }) else { return }
            self.applyRestartDecision(decision, for: takeID)
        }
        // Superseded rather than merely replaced: an earlier restart's timer
        // left running fires against a later restart and cuts its grace short,
        // spending budget on a tap that was still filling.
        let superseded: DispatchWorkItem? = stateLock.withLock {
            let previous = starvationWork
            starvationWork = item
            return previous
        }
        superseded?.cancel()
        restartScheduler.asyncAfter(deadline: .now() + grace, execute: item)
    }

    /// The end of the road: capture could not be brought back, so the take
    /// ends — but never empty-handed.
    private func salvageAndTeardown(for takeID: UInt64) async {
        // Captured before the teardown: stop() clears onConfigurationChange,
        // so reading it afterward always yields nil and the controller never
        // learns the device changed — leaving the app wedged in .recording
        // over a dead engine.
        let cb = onConfigurationChange
        let startsAtEntry = stateLock.withLock { takesStarted }
        // One drain interval before tearing the tap down, for the same reason
        // `flushAndStop` waits: without it the in-flight tap buffer never
        // reaches us and the last word is clipped. This path used to use plain
        // `stop()` and pay exactly that.
        try? await Task.sleep(for: Self.drainDuration)
        // Re-checked after the wait, not only before it: this is the last
        // deferred step of a restart and the longest, so a teardown decided
        // for one take could otherwise stop the next one, drain its buffer and
        // report it to the controller as interrupted. The take id, not
        // `isRecording` — `abandonEngine` clears that without ending the take,
        // and that case is exactly the one still owed a callback.
        guard stateLock.withLock({ self.takeID == takeID }) else {
            AppLog.audio.notice("Salvage dropped: its take had already ended")
            return
        }
        // Stop first, drain second. Draining first loses everything the
        // still-installed tap appends between the drain and the teardown, and
        // lets the tap keep feeding a live streaming socket across the hop to
        // the controller.
        var samples = await stop(prewarming: false, forTake: takeID)
        if samples.isEmpty, stateLock.withLock({ self.takeID == takeID }) {
            // `stopEngine` returns `[]` without draining when the generation
            // was already retired — a timeout forced `isRecording = false`.
            // The buffer queue is independent of CoreAudio, so the audio is
            // still there. Fenced again so a lost race drains its own take's
            // buffer rather than the next take's.
            samples = drainBuffer()
        }
        // The last unfenced step, and the one with teeth: the controller's
        // handler ends whatever take is in `.recording` when it arrives, so
        // delivering this to a recording that started while we were tearing
        // the old one down would kill a take that is perfectly healthy.
        // Counted starts, not `takeID`, which moves for stops as well.
        guard stateLock.withLock({ takesStarted == startsAtEntry }) else {
            AppLog.audio.notice("Salvage callback dropped (\(samples.count) samples): a newer take is already recording")
            return
        }
        AppLog.audio.warning("Salvaged \(samples.count) samples (\(Double(samples.count) / AudioConfig.targetSampleRate, format: .fixed(precision: 2))s) from the interrupted take")
        await MainActor.run { cb?(samples) }
    }

    // MARK: - Private

    private func makeTargetFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.targetFormatFailed
        }
        return format
    }

    private func handle(inputBuffer: AVAudioPCMBuffer, tapEpoch epoch: UInt64) {
        guard let targetFormat else { return }

        // Requested by a restart rather than performed by it: `removeTap` does
        // not join an in-flight callback, so this thread is the only one that
        // provably owns the filter state. Left alone, the AGC peak learned from
        // the old device makes an audible level step across the splice.
        //
        // The gap is measured from the last buffer before the restart to this
        // one, which is the hole that actually ends up in the recording —
        // shorter and more honest than the wall-clock the restart took, since
        // the engine had already stopped itself before we were even told.
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let resuming = tapControlLock.withLock { () -> Bool in
            // Only the tap the restart installed may close the measurement. A
            // straggler from the engine we just replaced would otherwise
            // consume the flag and bank its own inter-buffer time as the gap,
            // hiding the real hole entirely.
            guard epoch == tapEpoch else {
                lastTapAtNs = max(lastTapAtNs, nowNs)
                return false
            }
            let wasResuming = captureResuming
            if wasResuming { closeCaptureGapLocked(at: nowNs) }
            captureResuming = false
            lastTapAtNs = nowNs
            return wasResuming
        }
        if resuming {
            preprocessor.reset()
            lastLevelEmitNs = 0
        }

        // Keyed on the source format, not built once per session: the tap is
        // installed with `format: nil`, so its buffers follow the hardware and
        // a route change hands us a different rate mid-stream. A converter's
        // input format is fixed at init, so a stale one resamples from a rate
        // it is no longer being fed — every buffer dropped at best, an
        // uncatchable ObjC exception on the audio thread at worst. Rebuilding
        // here rather than on the engine queue keeps `converter`
        // single-threaded: `removeTap` does not join an in-flight tap
        // callback, so there is no window on the engine queue where touching
        // it would be safe.
        if converter?.inputFormat != inputBuffer.format {
            if let previous = converter?.inputFormat {
                AppLog.audio.warning("Capture format changed mid-take (\(Int(previous.sampleRate)) Hz \(previous.channelCount) ch -> \(Int(inputBuffer.format.sampleRate)) Hz \(inputBuffer.format.channelCount) ch); rebuilding converter")
            }
            converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat)
        }
        guard let converter else { return }

        let ratio = targetSampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            return
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, let channelData = outputBuffer.floatChannelData?[0] else { return }
        let frameCount = Int(outputBuffer.frameLength)
        var samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Measure loudness on the raw signal — the preprocessor's AGC slams
        // quiet audio toward full scale, which would make the HUD ribbon read
        // loud even when the user isn't talking. Throttled to ~30 Hz: skipped
        // buffers don't even pay for the RMS pass.
        let levelToEmit: Double?
        if onLevel != nil {
            let nowNs = DispatchTime.now().uptimeNanoseconds
            if nowNs &- lastLevelEmitNs >= Self.minLevelIntervalNs {
                lastLevelEmitNs = nowNs
                levelToEmit = AudioLevel.perceptual(samples)
            } else {
                levelToEmit = nil
            }
        } else {
            levelToEmit = nil
        }

        if preprocessingEnabled {
            preprocessor.process(&samples)
        }

        queue.sync { buffer.append(contentsOf: samples) }
        // Monotonic capture counter, so a restart's starvation watchdog can ask
        // whether audio actually resumed without a `queue.sync` that would
        // block it behind this very append.
        tapControlLock.withLock { tapSampleCount += samples.count }

        // Feed the same processed samples to a live streaming engine, in capture
        // order, on this audio thread (the engine buffers and sends in order).
        onAudioChunk?(samples)

        if let levelToEmit, let onLevel {
            Task { @MainActor in onLevel(levelToEmit) }
        }
    }

}

enum AudioRecorderError: LocalizedError {
    case targetFormatFailed
    case deviceUnresponsive
    /// The input node reports no channels and no sample rate after the settle
    /// probe — Apple's own test for "input is not enabled". Thrown rather than
    /// treated as device loss on the spot: the restart budget decides.
    case inputUnavailable
    /// The operation's engine generation was retired mid-flight (its queue was
    /// abandoned after a timeout). `startEngine` does surface it — the
    /// controller renders it as "Could not start recording: …" — but nothing
    /// downstream can act on it beyond retrying.
    case superseded
    /// The recording a deferred restart belonged to ended before the restart
    /// could finish. Never surfaced: the take is already over and whatever
    /// ended it has done the reporting.
    case takeEnded

    var errorDescription: String? {
        switch self {
        case .targetFormatFailed:
            return "Failed to create target audio format."
        case .deviceUnresponsive:
            return "The audio input device isn't responding. Try again, or pick a different microphone in System Settings → Sound."
        case .inputUnavailable:
            return "The audio input device disconnected. Pick a microphone in System Settings → Sound, then try again."
        case .superseded:
            return "The audio engine was restarted."
        case .takeEnded:
            return "The recording ended before the audio engine could restart."
        }
    }
}
