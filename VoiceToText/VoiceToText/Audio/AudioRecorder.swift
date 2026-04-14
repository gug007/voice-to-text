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
