import AVFoundation
import Foundation

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetSampleRate = AudioConfig.targetSampleRate
    private let tapBufferSize = AudioConfig.tapBufferSize
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var buffer: [Float] = []
    private let queue = DispatchQueue(label: "AudioRecorder.queue")
    private(set) var isRecording = false
    private var preprocessor = AudioPreprocessor()
    private var configChangeObserver: NSObjectProtocol?

    /// Called on the main actor if the audio engine's input configuration changes
    /// mid-recording (e.g. USB mic unplugged). Recording has already been stopped
    /// by the time this fires; the callback should surface an error and clean up UI.
    var onConfigurationChange: (@MainActor @Sendable () -> Void)?

    /// Called on the main actor with a perceptual mic level (0...1) for each
    /// processed tap buffer. Used to drive the live voice indicator in the HUD.
    var onLevel: (@MainActor @Sendable (Double) -> Void)?

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

        let input = engine.inputNode
        input.removeTap(onBus: 0)
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
        try engine.start()
        isRecording = true
    }

    func currentSamples() -> [Float] {
        queue.sync { buffer }
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
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

    private func handleConfigurationChange() {
        _ = stop()
        let cb = onConfigurationChange
        Task { @MainActor in cb?() }
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

        if preprocessingEnabled {
            preprocessor.process(&samples)
        }

        queue.sync { buffer.append(contentsOf: samples) }

        if let onLevel {
            let level = Self.perceptualLevel(samples)
            Task { @MainActor in onLevel(level) }
        }
    }

    /// RMS of a sample window mapped to a perceptual 0...1 scale.
    /// -60 dBFS → 0, -10 dBFS → 1, with a square-root shape in between so
    /// normal speech lands in the middle of the range instead of hugging zero.
    private static func perceptualLevel(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for s in samples { sumSquares += s * s }
        let rms = sqrt(sumSquares / Float(samples.count))
        let db = 20 * log10(max(rms, 1e-7))
        let norm = (Double(db) + 60) / 50
        return max(0, min(1, sqrt(max(0, norm))))
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
