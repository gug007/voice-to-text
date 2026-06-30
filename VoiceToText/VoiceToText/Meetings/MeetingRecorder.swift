import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

/// Records a long meeting by capturing **system audio + microphone** through
/// ScreenCaptureKit, converting both to 16 kHz mono Float, mixing them, and
/// streaming the result to a WAV on disk (so an hour-long session never sits in
/// RAM). Runs entirely in the background — capture is independent of which app
/// is frontmost.
///
/// `@unchecked Sendable` (like `AudioRecorder`): all audio buffers are handled
/// on a single serial queue, and the cross-actor callbacks hop to the main
/// actor explicitly. Requires Screen Recording permission.
final class MeetingRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Perceptual mic+system level (0…1) for the live indicator, on the main actor.
    var onLevel: (@MainActor @Sendable (Double) -> Void)?
    /// Fired if the OS tears the stream down mid-recording (permission revoked,
    /// display reconfigured, …) so the controller can surface an error.
    var onStopWithError: (@MainActor @Sendable (Error) -> Void)?

    private let sampleRate = Int(AudioConfig.targetSampleRate)
    private let processingQueue = DispatchQueue(label: "MeetingRecorder.audio")
    private let targetFormat: AVAudioFormat

    private var stream: SCStream?
    private var writer: StreamingWAVWriter?

    // Per-source conversion state (touched only on processingQueue).
    private var systemConverter: AVAudioConverter?
    private var systemSourceFormat: AVAudioFormat?
    private var micConverter: AVAudioConverter?
    private var micSourceFormat: AVAudioFormat?

    // Mix FIFOs (touched only on processingQueue): paired by arrival order.
    private var micQueue: [Float] = []
    private var systemQueue: [Float] = []

    private var lastLevelEmitNs: UInt64 = 0
    private static let minLevelIntervalNs: UInt64 = 33_000_000  // ~30 Hz
    /// If one source stalls while the other backs up beyond this, flush the
    /// backed-up side alone so a dead stream can't grow a FIFO unbounded or
    /// stall the whole recording.
    private var starveThresholdSamples: Int { sampleRate * 3 }

    override init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioConfig.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        super.init()
    }

    // MARK: - Lifecycle

    /// Begins capture, writing the mixed audio to `outputURL`. Throws if Screen
    /// Recording permission is missing or no display is available.
    func start(outputURL: URL) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw MeetingRecorderError.noDisplayAvailable
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = sampleRate
        config.channelCount = 1
        // Don't capture our own output (e.g. History playback) — avoids feedback.
        config.excludesCurrentProcessAudio = true
        // We only consume audio (no screen output is registered), but the
        // configuration still carries video settings — keep them tiny and slow
        // so the unused video path costs almost nothing.
        config.width = 128
        config.height = 128
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        if #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }

        let writer = try StreamingWAVWriter(url: outputURL, sampleRate: sampleRate)
        processingQueue.sync {
            self.writer = writer
            self.micQueue.removeAll(keepingCapacity: true)
            self.systemQueue.removeAll(keepingCapacity: true)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: processingQueue)
        if #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: processingQueue)
        }
        do {
            try await stream.startCapture()
        } catch {
            processingQueue.sync { self.writer?.discard(); self.writer = nil }
            throw error
        }
        // self.stream is only ever read/written on processingQueue so stop()/
        // cancel() can't race it off the main actor.
        processingQueue.sync { self.stream = stream }
        AppLog.audio.info("Meeting recording started → \(outputURL.lastPathComponent, privacy: .public)")
    }

    /// Stops capture, flushes the mix, and finalizes the WAV. Returns the
    /// playable file URL plus its duration in seconds, or nil if nothing was
    /// captured.
    func stop() async -> (url: URL, duration: Double)? {
        guard let stream = takeStream() else { return nil }
        try? await stream.stopCapture()
        // stopCapture has returned → no more sample callbacks can arrive, so the
        // final flush + finalize on the (now idle) processing queue is race-free.
        return processingQueue.sync {
            flushRemaining()
            let duration = writer?.durationSeconds ?? 0
            let url = writer?.finalize()
            writer = nil
            guard let url else { return nil }
            return (url, duration)
        }
    }

    /// Atomically reads and clears the active stream on the serial queue, so
    /// stop()/cancel() can't race it off the main actor.
    private func takeStream() -> SCStream? {
        processingQueue.sync {
            let current = stream
            stream = nil
            return current
        }
    }

    /// Stops capture and deletes the partial file (cancelled recording).
    func cancel() async {
        guard let stream = takeStream() else {
            processingQueue.sync { writer?.discard(); writer = nil }
            return
        }
        try? await stream.stopCapture()
        processingQueue.sync {
            writer?.discard()
            writer = nil
            micQueue.removeAll(keepingCapacity: false)
            systemQueue.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - SCStreamOutput (processingQueue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .audio:
            if let samples = convertToTarget(sampleBuffer, isMic: false) {
                systemQueue.append(contentsOf: samples)
                drainMix()
            }
        case .microphone:
            if let samples = convertToTarget(sampleBuffer, isMic: true) {
                micQueue.append(contentsOf: samples)
                drainMix()
            }
        default:
            break
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLog.audio.error("Meeting stream stopped with error: \(error.localizedDescription, privacy: .public)")
        let callback = onStopWithError
        Task { @MainActor in callback?(error) }
    }

    // MARK: - Mixing (processingQueue)

    private func drainMix() {
        let paired = min(micQueue.count, systemQueue.count)
        if paired > 0 {
            var mixed = [Float](repeating: 0, count: paired)
            for index in 0..<paired {
                mixed[index] = max(-1.0, min(1.0, micQueue[index] + systemQueue[index]))
            }
            micQueue.removeFirst(paired)
            systemQueue.removeFirst(paired)
            emit(mixed)
        }
        // One source stalled: don't let the other back up forever.
        if micQueue.isEmpty, systemQueue.count > starveThresholdSamples {
            emit(systemQueue)
            systemQueue.removeAll(keepingCapacity: true)
        } else if systemQueue.isEmpty, micQueue.count > starveThresholdSamples {
            emit(micQueue)
            micQueue.removeAll(keepingCapacity: true)
        }
    }

    /// Final flush on stop: pair what's left, then append the unpaired tail of
    /// whichever side ran longer so no captured audio is dropped.
    private func flushRemaining() {
        drainMix()
        if !micQueue.isEmpty {
            emit(micQueue)
            micQueue.removeAll(keepingCapacity: false)
        }
        if !systemQueue.isEmpty {
            emit(systemQueue)
            systemQueue.removeAll(keepingCapacity: false)
        }
    }

    private func emit(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        writer?.append(samples)
        emitLevelIfNeeded(samples)
    }

    private func emitLevelIfNeeded(_ samples: [Float]) {
        guard let onLevel else { return }
        let nowNs = DispatchTime.now().uptimeNanoseconds
        guard nowNs &- lastLevelEmitNs >= Self.minLevelIntervalNs else { return }
        lastLevelEmitNs = nowNs
        let level = AudioLevel.perceptual(samples)
        Task { @MainActor in onLevel(level) }
    }

    // MARK: - Conversion (processingQueue)

    private func convertToTarget(_ sampleBuffer: CMSampleBuffer, isMic: Bool) -> [Float]? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDesc)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(frames)
              ) else { return nil }
        sourceBuffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: sourceBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return nil }

        let converter = converter(for: sourceFormat, isMic: isMic)
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        guard error == nil, let channelData = outBuffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outBuffer.frameLength)))
    }

    /// Reuses a converter while the source format is stable; rebuilds it if the
    /// device's native format changes (rare, but possible across route changes).
    private func converter(for sourceFormat: AVAudioFormat, isMic: Bool) -> AVAudioConverter? {
        if isMic {
            if micConverter == nil || micSourceFormat != sourceFormat {
                micConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
                micSourceFormat = sourceFormat
            }
            return micConverter
        } else {
            if systemConverter == nil || systemSourceFormat != sourceFormat {
                systemConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
                systemSourceFormat = sourceFormat
            }
            return systemConverter
        }
    }

}

enum MeetingRecorderError: LocalizedError {
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available to capture system audio from."
        }
    }
}
