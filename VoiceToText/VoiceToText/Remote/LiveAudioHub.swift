import Foundation

nonisolated protocol LiveAudioEncoding: AnyObject {
    func encode(_ samples: [Float]) -> [Data]
}

nonisolated final class LiveAudioListener: @unchecked Sendable {
    enum Next: Equatable, Sendable {
        case frame(LiveAudioFrame)
        case timedOut
        case ended
    }

    static let defaultCapacity = (3 * LiveAudioWire.sampleRate + LiveAudioWire.samplesPerPacket - 1)
        / LiveAudioWire.samplesPerPacket

    let capacity: Int
    let client: String?
    private weak var hub: LiveAudioHub?
    private let condition = NSCondition()
    private var frames: [LiveAudioFrame] = []
    private var nextSequence: UInt32 = 0
    private var isEnded = false
    private var droppedFrames = 0

    init(capacity: Int = LiveAudioListener.defaultCapacity, client: String? = nil, hub: LiveAudioHub? = nil) {
        self.capacity = max(1, capacity)
        self.client = client
        self.hub = hub
    }

    var queuedCount: Int { condition.withLock { frames.count } }
    var dropped: Int { condition.withLock { droppedFrames } }
    var hasEnded: Bool { condition.withLock { isEnded } }

    func push(_ payload: Data) {
        condition.lock()
        defer { condition.unlock() }
        guard !isEnded else { return }
        if frames.count >= capacity {
            frames.removeFirst()
            droppedFrames += 1
        }
        frames.append(LiveAudioFrame(sequence: nextSequence, payload: payload))
        nextSequence &+= 1
        condition.signal()
    }

    func end(discardingQueued: Bool = false) {
        condition.lock()
        defer { condition.unlock() }
        isEnded = true
        if discardingQueued { frames.removeAll() }
        condition.broadcast()
    }

    func next(timeout: TimeInterval) -> Next {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while frames.isEmpty, !isEnded {
            if !condition.wait(until: deadline), frames.isEmpty, !isEnded {
                return .timedOut
            }
        }
        if !frames.isEmpty { return .frame(frames.removeFirst()) }
        return .ended
    }

    func close() {
        end(discardingQueued: true)
        hub?.leave(self)
    }
}

nonisolated final class LiveAudioHub: @unchecked Sendable {
    typealias EncoderFactory = @Sendable () -> LiveAudioEncoding?

    static let maxBacklogSamples = 3 * LiveAudioWire.sampleRate
    static let maxClientIDLength = 64

    static func isValidClientID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= maxClientIDLength else { return false }
        return id.utf8.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x2D
        }
    }

    let maxListeners: Int
    let listenerCapacity: Int
    private let makeEncoder: EncoderFactory
    private let onListenerCountChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "voice-to-text-ai.VoiceToText.remote.live-audio", qos: .userInitiated)
    private let lock = NSLock()
    private var listeners: [LiveAudioListener] = []
    private var backlogSamples = 0
    private var encoder: LiveAudioEncoding?

    init(
        maxListeners: Int = LiveAudioWire.maxListeners,
        listenerCapacity: Int = LiveAudioListener.defaultCapacity,
        makeEncoder: @escaping EncoderFactory,
        onListenerCountChange: @escaping @Sendable () -> Void = {}
    ) {
        self.maxListeners = maxListeners
        self.listenerCapacity = listenerCapacity
        self.makeEncoder = makeEncoder
        self.onListenerCountChange = onListenerCountChange
    }

    var listenerCount: Int { lock.withLock { listeners.count } }

    func submit(_ samples: [Float]) {
        let accepted: Bool = lock.withLock {
            guard !listeners.isEmpty, !samples.isEmpty,
                  backlogSamples + samples.count <= Self.maxBacklogSamples else { return false }
            backlogSamples += samples.count
            return true
        }
        guard accepted else { return }
        queue.async { [self] in encode(samples) }
    }

    func join(client: String? = nil) -> LiveAudioListener? {
        let listener = LiveAudioListener(capacity: listenerCapacity, client: client, hub: self)
        let (joined, superseded): (Bool, [LiveAudioListener]) = lock.withLock {
            var superseded: [LiveAudioListener] = []
            if let client {
                superseded = listeners.filter { $0.client == client }
                listeners.removeAll { $0.client == client }
            }
            guard listeners.count < maxListeners else { return (false, superseded) }
            listeners.append(listener)
            return (true, superseded)
        }
        for old in superseded { old.end(discardingQueued: true) }
        guard joined else { return nil }
        onListenerCountChange()
        return listener
    }

    func leave(_ listener: LiveAudioListener) {
        listener.end(discardingQueued: true)
        let removed: Bool = lock.withLock {
            guard let index = listeners.firstIndex(where: { $0 === listener }) else { return false }
            listeners.remove(at: index)
            return true
        }
        guard removed else { return }
        queue.async { [self] in dropEncoderIfIdle() }
        onListenerCountChange()
    }

    func endSession() {
        finishAll(discardingQueued: false)
    }

    func disconnectAll() {
        finishAll(discardingQueued: true)
    }

    private func finishAll(discardingQueued: Bool) {
        let ended: [LiveAudioListener] = lock.withLock {
            let all = listeners
            listeners.removeAll()
            return all
        }
        guard !ended.isEmpty else { return }
        for listener in ended { listener.end(discardingQueued: discardingQueued) }
        queue.async { [self] in dropEncoderIfIdle() }
        onListenerCountChange()
    }

    private func encode(_ samples: [Float]) {
        let targets: [LiveAudioListener] = lock.withLock {
            backlogSamples -= samples.count
            return listeners
        }
        guard !targets.isEmpty else {
            encoder = nil
            return
        }
        if encoder == nil { encoder = makeEncoder() }
        guard let encoder else { return }
        for packet in encoder.encode(samples) {
            for listener in targets { listener.push(packet) }
        }
    }

    private func dropEncoderIfIdle() {
        guard lock.withLock({ listeners.isEmpty }) else { return }
        encoder = nil
    }
}
