import Foundation

struct LiveAudioHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw LiveAudioHarnessFailure(description: message)
    }
}

private func waitFor(_ timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(2_000)
    }
    return condition()
}

private func settle(_ listener: LiveAudioListener) {
    var last = -1
    while true {
        let heard = listener.queuedCount + listener.dropped
        if heard == last { return }
        last = heard
        usleep(50_000)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
    func decrement() { lock.withLock { count -= 1 } }
}

private final class FakeEncoder: LiveAudioEncoding {
    private let alive: Counter
    private let delay: useconds_t
    private var pending = 0
    private var packet: UInt32 = 0

    init(alive: Counter, delay: useconds_t = 0) {
        self.alive = alive
        self.delay = delay
        alive.increment()
    }

    deinit { alive.decrement() }

    func encode(_ samples: [Float]) -> [Data] {
        if delay > 0 { usleep(delay) }
        pending += samples.count
        var packets: [Data] = []
        while pending >= LiveAudioWire.samplesPerPacket {
            pending -= LiveAudioWire.samplesPerPacket
            var value = packet.bigEndian
            packets.append(Data(bytes: &value, count: 4))
            packet &+= 1
        }
        return packets
    }
}

@main
struct LiveAudioHarness {
    static func main() throws {
        try headerRoundTrips()
        try framesRoundTripAcrossEveryChunkBoundary()
        try framesRoundTripInRandomChunks()
        try refusesBadStreams()
        try listenerDropsOldestWhenFull()
        try listenerEndsAfterDrainingOrAtOnce()
        try listenerTimesOutWhileEmpty()
        try hubCapsListeners()
        try hubEncodesOnlyWhileSomeoneListens()
        try hubFansOutToEveryListener()
        try submitStaysPromptWhileListenerNeverDrains()
        try submitStaysPromptWhileEncoderIsSlow()
        try endSessionFinishesEveryListener()
        try closeFreesTheSlot()
        try aDeviceRejoiningReplacesItsOwnStream()
        try validatesClientIDs()
        print("Live audio harness passed")
    }

    // MARK: - Wire

    private static func headerRoundTrips() throws {
        let bytes = LiveAudioStreamHeader.standard.encoded()
        try expect(bytes.count == LiveAudioWire.headerLength, "the header is 12 bytes")
        try expect(Array(bytes.prefix(4)) == Array("VTLA".utf8), "magic")
        var parser = LiveAudioStreamParser()
        let frames = try parser.append(bytes)
        try expect(frames.isEmpty, "a header alone carries no frames")
        try expect(parser.header == .standard, "the header round-trips")
        try expect(parser.header?.sampleRate == 16_000 && parser.header?.channels == 1, "16 kHz mono")
    }

    private static func sampleFrames() -> [LiveAudioFrame] {
        var frames: [LiveAudioFrame] = []
        for index in 0..<40 {
            let size = [0, 1, 5, 6, 7, 180, 291, 768, 2048, LiveAudioWire.maxPayload][index % 10]
            let payload = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ index) })
            frames.append(LiveAudioFrame(sequence: UInt32(index) &+ 0xFFFF_FFF0, payload: payload))
        }
        return frames
    }

    private static func stream(_ frames: [LiveAudioFrame]) -> Data {
        var data = LiveAudioStreamHeader.standard.encoded()
        for frame in frames { data.append(frame.encoded()) }
        return data
    }

    private static func framesRoundTripAcrossEveryChunkBoundary() throws {
        let frames = Array(sampleFrames().prefix(12)).filter { $0.payload.count <= 291 }
        let data = stream(frames)
        for split in 0...data.count {
            var parser = LiveAudioStreamParser()
            var parsed = try parser.append(data.subdata(in: 0..<split))
            parsed += try parser.append(data.subdata(in: split..<data.count))
            try expect(parsed == frames, "frames survive a split at byte \(split)")
            try expect(parser.header == .standard, "the header survives a split at byte \(split)")
        }
        var parser = LiveAudioStreamParser()
        var parsed: [LiveAudioFrame] = []
        for byte in data { parsed += try parser.append(Data([byte])) }
        try expect(parsed == frames, "frames survive one byte at a time")
    }

    private static func framesRoundTripInRandomChunks() throws {
        let frames = sampleFrames()
        let data = stream(frames)
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            var parser = LiveAudioStreamParser()
            var parsed: [LiveAudioFrame] = []
            var offset = 0
            while offset < data.count {
                let length = min(data.count - offset, Int.random(in: 1...9000, using: &generator))
                parsed += try parser.append(data.subdata(in: offset..<(offset + length)))
                offset += length
            }
            try expect(parsed == frames, "frames survive random chunking")
        }
        try expect(frames.last?.sequence == 0xFFFF_FFF0 &+ 39, "sequences wrap without trouble")
        try expect(LiveAudioFrame(sequence: 1, payload: Data(count: 7)).encoded().count == 13, "a frame is a 6-byte head plus its payload")
    }

    private static func refusesBadStreams() throws {
        var header = Array(LiveAudioStreamHeader.standard.encoded())
        header[0] = UInt8(ascii: "X")
        try expectFailure(Data(header), .badMagic, "bad magic")

        header = Array(LiveAudioStreamHeader.standard.encoded())
        header[4] = 2
        try expectFailure(Data(header), .unsupportedVersion(2), "a newer version")

        header = Array(LiveAudioStreamHeader.standard.encoded())
        header[5] = 9
        try expectFailure(Data(header), .unsupportedCodec(9), "an unknown codec")

        var oversized = LiveAudioStreamHeader.standard.encoded()
        oversized.append(contentsOf: [0, 0, 0, 1, 0x20, 0x01])
        try expectFailure(oversized, .oversizedFrame(LiveAudioWire.maxPayload + 1), "a frame over the limit")

        var parser = LiveAudioStreamParser()
        let partial = try parser.append(Data(LiveAudioStreamHeader.standard.encoded().prefix(11)))
        try expect(partial.isEmpty && parser.header == nil, "a short header waits for more")
    }

    private static func expectFailure(_ data: Data, _ failure: LiveAudioStreamParser.Failure, _ message: String) throws {
        var parser = LiveAudioStreamParser()
        do {
            _ = try parser.append(data)
            throw LiveAudioHarnessFailure(description: "\(message): accepted")
        } catch let error as LiveAudioStreamParser.Failure {
            try expect(error == failure, "\(message): \(error)")
        }
    }

    // MARK: - Listener queue

    private static func payload(_ value: Int) -> Data {
        Data([UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    private static func listenerDropsOldestWhenFull() throws {
        try expect(LiveAudioListener.defaultCapacity == 47, "about three seconds of packets")
        let listener = LiveAudioListener(capacity: 5)
        for value in 0..<12 { listener.push(payload(value)) }
        try expect(listener.queuedCount == 5, "the queue is bounded")
        try expect(listener.dropped == 7, "the overflow is counted")
        var sequences: [UInt32] = []
        var payloads: [Data] = []
        while case .frame(let frame) = listener.next(timeout: 0) {
            sequences.append(frame.sequence)
            payloads.append(frame.payload)
        }
        try expect(sequences == [7, 8, 9, 10, 11], "the oldest go first, and the gap shows in the sequence")
        try expect(payloads == (7..<12).map(payload), "the newest payloads are kept")
        listener.push(payload(99))
        guard case .frame(let next) = listener.next(timeout: 0) else {
            throw LiveAudioHarnessFailure(description: "a frame after draining")
        }
        try expect(next.sequence == 12, "sequences keep counting after a drain")
    }

    private static func listenerEndsAfterDrainingOrAtOnce() throws {
        let draining = LiveAudioListener(capacity: 10)
        for value in 0..<3 { draining.push(payload(value)) }
        draining.end()
        draining.push(payload(3))
        var delivered = 0
        while case .frame = draining.next(timeout: 0) { delivered += 1 }
        try expect(delivered == 3, "an ended session still delivers what was queued, and nothing after")
        try expect(draining.next(timeout: 0) == .ended, "then it ends")
        try expect(draining.next(timeout: 5) == .ended, "and stays ended without waiting")

        let discarding = LiveAudioListener(capacity: 10)
        for value in 0..<3 { discarding.push(payload(value)) }
        discarding.end(discardingQueued: true)
        try expect(discarding.next(timeout: 0) == .ended, "a disconnect ends at once")

        let waiting = LiveAudioListener(capacity: 10)
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { waiting.end() }
        let outcome = waiting.next(timeout: 5)
        let waited = Date().timeIntervalSince(started)
        try expect(outcome == .ended, "a waiting reader wakes on end")
        try expect(waited < 1, "and wakes promptly (\(waited) s)")

        let fed = LiveAudioListener(capacity: 10)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { fed.push(payload(1)) }
        guard case .frame(let frame) = fed.next(timeout: 5) else {
            throw LiveAudioHarnessFailure(description: "a waiting reader wakes on a frame")
        }
        try expect(frame.sequence == 0, "a new listener starts at sequence 0")
    }

    private static func listenerTimesOutWhileEmpty() throws {
        let listener = LiveAudioListener(capacity: 4)
        let started = Date()
        let outcome = listener.next(timeout: 0.15)
        let waited = Date().timeIntervalSince(started)
        try expect(outcome == .timedOut, "an empty queue times out")
        try expect(waited >= 0.14 && waited < 1, "after about the timeout (\(waited) s)")
    }

    // MARK: - Hub

    private static func hubCapsListeners() throws {
        let alive = Counter()
        let changes = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) }, onListenerCountChange: { changes.increment() })
        try expect(LiveAudioWire.maxListeners == 2, "two listeners at most")
        let first = hub.join()
        let second = hub.join()
        let third = hub.join()
        try expect(first != nil && second != nil, "two may join")
        try expect(third == nil, "a third is refused")
        try expect(hub.listenerCount == 2, "the count says two")
        try expect(changes.value == 2, "the count change is published per join, not for a refusal")
        first?.close()
        try expect(hub.listenerCount == 1, "a close leaves")
        try expect(changes.value == 3, "and is published")
        first?.close()
        try expect(changes.value == 3, "a second close is a no-op")
        try expect(hub.join() != nil, "the freed slot can be taken")
    }

    private static func hubEncodesOnlyWhileSomeoneListens() throws {
        let alive = Counter()
        let made = Counter()
        let hub = LiveAudioHub(makeEncoder: { made.increment(); return FakeEncoder(alive: alive) })
        hub.submit([Float](repeating: 0, count: 4096))
        usleep(50_000)
        try expect(made.value == 0, "nothing is encoded while nobody listens")

        guard let listener = hub.join() else { throw LiveAudioHarnessFailure(description: "join") }
        hub.submit([Float](repeating: 0, count: 2048))
        try expect(waitFor { listener.queuedCount == 2 }, "a listener hears packets")
        try expect(made.value == 1 && alive.value == 1, "one encoder while someone listens")
        guard case .frame(let first) = listener.next(timeout: 0) else {
            throw LiveAudioHarnessFailure(description: "first frame")
        }
        try expect(first.sequence == 0 && first.payload == Data([0, 0, 0, 0]), "a listener starts live, at sequence 0")

        listener.close()
        try expect(waitFor { alive.value == 0 }, "the encoder is dropped when the last listener leaves")
        hub.submit([Float](repeating: 0, count: 4096))
        usleep(50_000)
        try expect(made.value == 1, "and not made again for nobody")

        guard let again = hub.join() else { throw LiveAudioHarnessFailure(description: "rejoin") }
        hub.submit([Float](repeating: 0, count: 1024))
        try expect(waitFor { again.queuedCount == 1 }, "a new listener hears packets")
        try expect(made.value == 2 && alive.value == 1, "a fresh encoder for the next listener")
        guard case .frame(let fresh) = again.next(timeout: 0) else {
            throw LiveAudioHarnessFailure(description: "fresh frame")
        }
        try expect(fresh.payload == Data([0, 0, 0, 0]), "with no backlog from before")
        hub.endSession()
        try expect(waitFor { alive.value == 0 }, "the session's end drops the encoder")
    }

    private static func hubFansOutToEveryListener() throws {
        let alive = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) })
        guard let first = hub.join() else { throw LiveAudioHarnessFailure(description: "join") }
        hub.submit([Float](repeating: 0, count: 3 * 1024))
        try expect(waitFor { first.queuedCount == 3 }, "the first listener hears three")
        guard let second = hub.join() else { throw LiveAudioHarnessFailure(description: "join") }
        hub.submit([Float](repeating: 0, count: 2 * 1024))
        try expect(waitFor { first.queuedCount == 5 && second.queuedCount == 2 }, "both hear the next two; the late one gets no backlog")
        var secondFrames: [LiveAudioFrame] = []
        while case .frame(let frame) = second.next(timeout: 0) { secondFrames.append(frame) }
        try expect(secondFrames.map(\.sequence) == [0, 1], "each listener counts its own sequence")
        try expect(secondFrames.map(\.payload) == [Data([0, 0, 0, 3]), Data([0, 0, 0, 4])], "the late listener joins the shared stream live")
        hub.endSession()
    }

    private static func submitStaysPromptWhileListenerNeverDrains() throws {
        let alive = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) })
        guard let stuck = hub.join() else { throw LiveAudioHarnessFailure(description: "join") }
        let chunk = [Float](repeating: 0.1, count: 160)
        var slowest: TimeInterval = 0
        let started = Date()
        let submissions = 6_000
        for index in 0..<submissions {
            let before = Date()
            hub.submit(chunk)
            slowest = max(slowest, Date().timeIntervalSince(before))
            if index % 100 == 99 { usleep(1_000) }
        }
        let total = Date().timeIntervalSince(started)
        try expect(slowest < 0.05, "no submit waits on a listener that never reads (slowest \(slowest) s)")
        try expect(total < 5, "a minute of audio in small submits stays fast (\(total) s)")
        try expect(waitFor { stuck.queuedCount == stuck.capacity }, "the stuck listener's queue sits full")
        settle(stuck)
        let heard = stuck.queuedCount + stuck.dropped
        try expect(stuck.dropped > 0 && heard > stuck.capacity, "and it drops the oldest (\(stuck.dropped) dropped of \(heard))")
        guard case .frame(let oldest) = stuck.next(timeout: 0) else {
            throw LiveAudioHarnessFailure(description: "oldest frame")
        }
        try expect(oldest.sequence == UInt32(stuck.dropped), "what is left is the newest packets")
        hub.endSession()
    }

    private static func submitStaysPromptWhileEncoderIsSlow() throws {
        let alive = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive, delay: 20_000) })
        guard let listener = hub.join() else { throw LiveAudioHarnessFailure(description: "join") }
        var slowest: TimeInterval = 0
        for _ in 0..<500 {
            let before = Date()
            hub.submit([Float](repeating: 0, count: 1024))
            slowest = max(slowest, Date().timeIntervalSince(before))
        }
        try expect(slowest < 0.05, "a slow encoder never slows the recorder (slowest \(slowest) s)")
        try expect(waitFor(3) { listener.queuedCount + listener.dropped >= 1 }, "the encoder still gets work")
        hub.endSession()
        try expect(waitFor(15) { alive.value == 0 }, "the backlog drains and the encoder goes")
        let heard = listener.queuedCount + listener.dropped
        try expect(heard < 500, "a backlog past three seconds is shed rather than queued (\(heard) of 500 encoded)")
    }

    private static func endSessionFinishesEveryListener() throws {
        let alive = Counter()
        let changes = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) }, onListenerCountChange: { changes.increment() })
        guard let first = hub.join(), let second = hub.join() else { throw LiveAudioHarnessFailure(description: "join") }
        hub.submit([Float](repeating: 0, count: 1024))
        try expect(waitFor { first.queuedCount == 1 && second.queuedCount == 1 }, "both hear a packet")

        let reader = Counter()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while true {
                switch second.next(timeout: 5) {
                case .frame: reader.increment()
                case .timedOut: continue
                case .ended:
                    done.signal()
                    return
                }
            }
        }
        try expect(waitFor { reader.value == 1 }, "the blocked reader took its packet")
        hub.endSession()
        try expect(done.wait(timeout: .now() + 1) == .success, "a reader blocked on an empty queue ends with the session")
        try expect(hub.listenerCount == 0, "nobody is left")
        try expect(changes.value == 3, "the drop to zero is published once")
        guard case .frame = first.next(timeout: 0) else {
            throw LiveAudioHarnessFailure(description: "the queued packet is still delivered after the session ends")
        }
        try expect(first.next(timeout: 0) == .ended, "then the listener ends")
        hub.submit([Float](repeating: 0, count: 1024))
        usleep(30_000)
        try expect(first.queuedCount == 0, "nothing reaches an ended listener")
        first.close()
        try expect(changes.value == 3, "closing an ended listener changes nothing")

        guard let third = hub.join() else { throw LiveAudioHarnessFailure(description: "join after end") }
        hub.submit([Float](repeating: 0, count: 1024))
        try expect(waitFor { third.queuedCount == 1 }, "a new session can be heard")
        hub.disconnectAll()
        try expect(third.next(timeout: 0) == .ended, "a disconnect drops what was queued")
        hub.endSession()
        try expect(hub.listenerCount == 0, "ending an empty hub is harmless")
    }

    private static func aDeviceRejoiningReplacesItsOwnStream() throws {
        let alive = Counter()
        let changes = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) }, onListenerCountChange: { changes.increment() })
        guard let zombie = hub.join(client: "phone-a") else { throw LiveAudioHarnessFailure(description: "join") }
        hub.submit([Float](repeating: 0, count: 1024))
        try expect(waitFor { zombie.queuedCount == 1 }, "the first stream hears a packet")
        guard let other = hub.join(client: "phone-b") else { throw LiveAudioHarnessFailure(description: "second device") }
        try expect(hub.join(client: "phone-c") == nil, "a third device is refused")
        try expect(hub.join() == nil, "and so is a listener without a client id")
        guard let reconnect = hub.join(client: "phone-a") else {
            throw LiveAudioHarnessFailure(description: "a reconnect from a device that holds a slot is never refused")
        }
        try expect(hub.listenerCount == 2, "the reconnect took its own old slot")
        try expect(zombie.next(timeout: 0) == .ended, "the old stream ends at once, its backlog dropped")
        try expect(!other.hasEnded && !reconnect.hasEnded, "nobody else is touched")
        hub.submit([Float](repeating: 0, count: 1024))
        try expect(waitFor { reconnect.queuedCount == 1 && other.queuedCount == 1 }, "the encoder carries on for the reconnect")
        guard case .frame(let first) = reconnect.next(timeout: 0) else {
            throw LiveAudioHarnessFailure(description: "reconnect frame")
        }
        try expect(first.sequence == 0, "the reconnect starts at sequence 0")
        zombie.close()
        try expect(hub.listenerCount == 2, "the old connection closing late frees nothing it no longer holds")
        try expect(alive.value == 1, "one encoder throughout")

        let anonymous = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) })
        guard let first1 = anonymous.join(), anonymous.join() != nil else { throw LiveAudioHarnessFailure(description: "anonymous joins") }
        try expect(anonymous.join() == nil, "listeners without an owner never replace each other")
        try expect(!first1.hasEnded, "and stay attached")
        anonymous.disconnectAll()

        guard let again = hub.join(client: "phone-a") else { throw LiveAudioHarnessFailure(description: "second rejoin") }
        try expect(reconnect.next(timeout: 0) == .ended, "a second rejoin replaces the first rejoin too")
        try expect(hub.listenerCount == 2 && !again.hasEnded && !other.hasEnded, "the same phone never counts twice")
        hub.disconnectAll()
    }

    private static func validatesClientIDs() throws {
        try expect(LiveAudioHub.isValidClientID("3F2504E0-4F89-11D3-9A0C-0305E82C3301"), "a UUID")
        try expect(LiveAudioHub.isValidClientID("a"), "one character")
        try expect(LiveAudioHub.isValidClientID(String(repeating: "x", count: 64)), "64 characters")
        try expect(!LiveAudioHub.isValidClientID(String(repeating: "x", count: 65)), "65 characters is too long")
        try expect(!LiveAudioHub.isValidClientID(""), "empty")
        try expect(!LiveAudioHub.isValidClientID("a_b"), "an underscore")
        try expect(!LiveAudioHub.isValidClientID("a b"), "a space")
        try expect(!LiveAudioHub.isValidClientID("a%2Db"), "percent-encoding")
        try expect(!LiveAudioHub.isValidClientID("é"), "non-ASCII letters")
    }

    private static func closeFreesTheSlot() throws {
        let alive = Counter()
        let hub = LiveAudioHub(makeEncoder: { FakeEncoder(alive: alive) })
        guard let first = hub.join(), hub.join() != nil else { throw LiveAudioHarnessFailure(description: "join") }
        try expect(hub.join() == nil, "full")
        first.close()
        try expect(first.hasEnded, "a closed listener has ended")
        try expect(first.next(timeout: 0) == .ended, "and says so")
        try expect(hub.join() != nil, "its slot is free again")
        hub.disconnectAll()
        try expect(hub.join() != nil && hub.join() != nil, "a disconnect frees every slot")
        hub.disconnectAll()
    }
}
