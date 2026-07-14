import AVFoundation
import Foundation

final class AudioRecorder: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let targetSampleRate = AudioConfig.targetSampleRate
    private let tapBufferSize = AudioConfig.tapBufferSize
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var buffer: [Float] = []
    private let queue = DispatchQueue(label: "AudioRecorder.queue")
    private(set) var isRecording = false
    private var preprocessor = AudioPreprocessor()
    private var configChangeObserver: NSObjectProtocol?
    /// Throttles HUD level updates to ~display cadence. The input tap fires at
    /// the hardware rate (~47/sec at 48 kHz), and each emit drives a full
    /// waveform re-render on the main actor — far more often than the eye needs.
    private var lastLevelEmitNs: UInt64 = 0
    private static let minLevelIntervalNs: UInt64 = 33_000_000  // ~30 Hz

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

    func start() throws {
        preprocessor.reset()
        queue.sync { buffer.removeAll(keepingCapacity: true) }

        let targetFormat = try makeTargetFormat()
        self.targetFormat = targetFormat
        self.converter = nil

        // AVAudioEngine caches the input node's format at construction. After
        // sleep/wake or an audio device switch that cache goes stale and the
        // next start() throws "formats don't match". A fresh engine per start
        // stays in sync with the current hardware.
        removeConfigChangeObserver()
        let engine = AVAudioEngine()
        self.engine = engine

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil) { [weak self] pcmBuffer, _ in
            self?.handle(inputBuffer: pcmBuffer)
        }

        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            removeConfigChangeObserver()
            throw error
        }
        isRecording = true
    }

    func currentSamples() -> [Float] {
        queue.sync { buffer }
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        removeConfigChangeObserver()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        onConfigurationChange = nil

        return queue.sync {
            let result = buffer
            buffer.removeAll(keepingCapacity: false)
            return result
        }
    }

    /// Waits one drain interval before tearing the tap down so the in-flight
    /// tap buffer reaches our callback — without it the last word gets cut.
    /// Cancel paths can still use the sync `stop()` since they discard audio.
    func flushAndStop() async -> [Float] {
        guard isRecording else { return [] }
        try? await Task.sleep(for: Self.drainDuration)
        return stop()
    }

    // 2× tap buffer leaves margin for HAL scheduling jitter.
    private static let drainDuration: Duration = {
        let bufferSeconds = Double(AudioConfig.tapBufferSize) / AudioConfig.targetSampleRate
        return .milliseconds(Int((bufferSeconds * 2 * 1000).rounded(.up)))
    }()

    private func handleConfigurationChange() {
        // Capture the callback before stop(): stop() clears onConfigurationChange,
        // so reading it afterward always yields nil and the controller never learns
        // the device changed — leaving the app wedged in .recording over a dead
        // engine. Grabbing it first lets handleAudioConfigurationChange() fire.
        let cb = onConfigurationChange
        _ = stop()
        Task { @MainActor in cb?() }
    }

    private func removeConfigChangeObserver() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
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

    var errorDescription: String? {
        switch self {
        case .targetFormatFailed:
            return "Failed to create target audio format."
        }
    }
}
