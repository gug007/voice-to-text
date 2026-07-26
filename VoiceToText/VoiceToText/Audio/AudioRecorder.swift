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

    /// Generous relative to a healthy device (well under a second) and to a
    /// Bluetooth mic waking into handsfree mode (a few seconds), but short
    /// enough that a wedged coreaudiod surfaces as a retryable error instead of
    /// an unbounded wait.
    private static let startTimeout: Duration = .seconds(8)
    private static let stopTimeout: Duration = .seconds(5)

    /// Called on the main actor if the audio engine's input configuration changes
    /// mid-recording (e.g. USB mic unplugged). Recording has already been stopped
    /// by the time this fires; the callback should surface an error and clean up UI.
    var onConfigurationChange: (@MainActor @Sendable () -> Void)?

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
    func stop() async -> [Float] {
        let samples: [Float]
        do {
            samples = try await runOnEngineQueue(timeout: Self.stopTimeout) { generation in
                self.stopEngine(generation: generation)
            }
        } catch {
            AppLog.audio.error("Audio engine stop timed out; recovering buffered audio")
            samples = drainBuffer()
        }
        onConfigurationChange = nil
        prewarm()
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
    /// forget; a no-op when the cached engine is already good.
    func prewarm() {
        let (queue, generation) = stateLock.withLock { (engineQueue, engineGeneration) }
        queue.async {
            let shouldWarm = self.stateLock.withLock {
                self.engineGeneration == generation
                    && !self.isRecording
                    && (self.needsFreshEngine || self.engine == nil)
            }
            guard shouldWarm else { return }
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

    /// Retires the wedged generation and its queue. The in-flight operation is
    /// left to finish (or not) in its own sandbox; it tears down whatever it
    /// built once it notices its generation is stale.
    private func abandonEngine(staleGeneration: UInt64) {
        let observer: NSObjectProtocol? = stateLock.withLock {
            guard engineGeneration == staleGeneration else { return nil }
            engineGeneration &+= 1
            engineQueue = DispatchQueue(label: "AudioRecorder.engine.\(engineGeneration)")
            let observer = configChangeObserver
            configChangeObserver = nil
            engine = nil
            needsFreshEngine = true
            isRecording = false
            return observer
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Engine queue work

    private func startEngine(generation: UInt64) throws {
        preprocessor.reset()
        queue.sync { buffer.removeAll(keepingCapacity: true) }
        targetFormat = try makeTargetFormat()

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
            return true
        }
        guard published else { throw AudioRecorderError.superseded }
    }

    private func attachAndStart(generation: UInt64, forceFresh: Bool) throws {
        let engine = try makeEngine(generation: generation, forceFresh: forceFresh)
        converter = nil

        let input = engine.inputNode
        // A reused engine may still carry the previous session's tap.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil) { [weak self] pcmBuffer, _ in
            self?.handle(inputBuffer: pcmBuffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Returns the cached engine when it's still trustworthy, otherwise builds
    /// and publishes a fresh one. Callers must be on the engine queue.
    private func makeEngine(generation: UInt64, forceFresh: Bool = false) throws -> AVAudioEngine {
        let cached: AVAudioEngine? = stateLock.withLock {
            guard engineGeneration == generation, !needsFreshEngine, !forceFresh else { return nil }
            return engine
        }
        if let cached { return cached }

        let staleObserver: NSObjectProtocol? = stateLock.withLock {
            let observer = configChangeObserver
            configChangeObserver = nil
            engine = nil
            return observer
        }
        if let staleObserver { NotificationCenter.default.removeObserver(staleObserver) }

        let fresh = AVAudioEngine()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: fresh,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
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

    private func stopEngine(generation: UInt64) -> [Float] {
        let engine: AVAudioEngine? = stateLock.withLock {
            guard engineGeneration == generation, isRecording else { return nil }
            isRecording = false
            return self.engine
        }
        guard let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return drainBuffer()
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

    private func handleConfigurationChange() {
        // Capture the callback before stopping: stop() clears
        // onConfigurationChange, so reading it afterward always yields nil and
        // the controller never learns the device changed — leaving the app
        // wedged in .recording over a dead engine.
        let cb = onConfigurationChange
        stateLock.withLock { needsFreshEngine = true }
        Task.detached { [weak self] in
            _ = await self?.stop()
            await MainActor.run { cb?() }
        }
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

    private func handle(inputBuffer: AVAudioPCMBuffer) {
        guard let targetFormat else { return }

        if converter == nil {
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
    /// The operation's engine generation was retired mid-flight (its queue was
    /// abandoned after a timeout). Never surfaced to the user — the caller that
    /// would have shown it has already moved on.
    case superseded

    var errorDescription: String? {
        switch self {
        case .targetFormatFailed:
            return "Failed to create target audio format."
        case .deviceUnresponsive:
            return "The audio input device isn't responding. Try again, or pick a different microphone in System Settings → Sound."
        case .superseded:
            return "The audio engine was restarted."
        }
    }
}
