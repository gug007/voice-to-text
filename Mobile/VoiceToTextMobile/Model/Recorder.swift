import AVFoundation
import Foundation
import Observation

nonisolated final class CaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private let writer: StreamingWAVWriter
    private let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioConfig.targetSampleRate,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private var currentLevel: Float = 0

    init(writer: StreamingWAVWriter) {
        self.writer = writer
    }

    var level: Float { lock.withLock { currentLevel } }
    var durationSeconds: Double { lock.withLock { writer.durationSeconds } }
    var didFail: Bool { lock.withLock { writer.didFail } }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        if converter == nil || converterInput != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converterInput = buffer.format
        }
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        writer.append(samples)

        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        currentLevel = min(max((db + 55) / 45, 0), 1)
    }

    func finish() -> (url: URL, duration: Double)? {
        lock.lock()
        defer { lock.unlock() }
        let duration = writer.durationSeconds
        guard let url = writer.finalize() else { return nil }
        return (url, duration)
    }

    func discard() {
        lock.withLock { writer.discard() }
    }
}

enum RecorderError: LocalizedError {
    case microphoneDenied
    case noInput
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Voice to Text can't use the microphone. Allow it in Settings → Privacy & Security → Microphone."
        case .noInput:
            return "No microphone is available right now."
        case .failed(let reason):
            return "Recording couldn't start: \(reason)"
        }
    }
}

@Observable
final class Recorder {
    static let shared = Recorder()

    enum Phase: Equatable {
        case idle
        case recording
        case interrupted
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: Double = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: Recorder.levelCount)
    static let levelCount = 28

    var isActive: Bool { phase != .idle }

    private var engine: AVAudioEngine?
    private var sink: CaptureSink?
    private var recordingID: UUID?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() async throws {
        guard phase == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.microphoneDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            throw RecorderError.failed(error.localizedDescription)
        }

        let id = UUID()
        let sink: CaptureSink
        do {
            try FileManager.default.createDirectory(at: Library.directory, withIntermediateDirectories: true)
            let writer = try StreamingWAVWriter(
                url: Library.newAudioURL(id: id),
                sampleRate: Int(AudioConfig.targetSampleRate)
            )
            sink = CaptureSink(writer: writer)
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.failed(error.localizedDescription)
        }

        self.sink = sink
        self.recordingID = id
        do {
            try startEngine()
        } catch {
            sink.discard()
            self.sink = nil
            self.recordingID = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        elapsed = 0
        levels = Array(repeating: 0, count: Self.levelCount)
        phase = .recording
        observe()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() -> (id: UUID, duration: Double)? {
        guard phase != .idle, let sink, let id = recordingID else { return nil }
        teardown()
        guard let finished = sink.finish(), finished.duration >= 0.3 else {
            sink.discard()
            return nil
        }
        return (id, finished.duration)
    }

    func cancel() {
        guard phase != .idle else { return }
        let sink = self.sink
        teardown()
        sink?.discard()
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        guard let sink else { throw RecorderError.noInput }
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            sink.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.failed(error.localizedDescription)
        }
        self.engine = engine
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func resumeCapture() {
        guard phase != .idle else { return }
        stopEngine()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try startEngine()
            phase = .recording
        } catch {
            phase = .interrupted
        }
    }

    private func teardown() {
        ticker?.invalidate()
        ticker = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sink = nil
        recordingID = nil
        phase = .idle
    }

    private func tick() {
        guard let sink else { return }
        elapsed = sink.durationSeconds
        levels.removeFirst()
        levels.append(phase == .recording ? sink.level : 0)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            Task { @MainActor in
                guard let self, self.phase != .idle else { return }
                if type == .began {
                    self.stopEngine()
                    self.phase = .interrupted
                } else {
                    self.resumeCapture()
                }
            }
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let changed = note.object as AnyObject?
            Task { @MainActor in
                guard let self, self.phase == .recording, changed === self.engine else { return }
                self.resumeCapture()
            }
        })
    }

    func resumeAfterInterruption() {
        guard phase == .interrupted else { return }
        resumeCapture()
    }
}
