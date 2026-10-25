import Foundation

struct CaptureRingCursorHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CaptureRingCursorHarnessFailure(description: message)
    }
}

private struct Copy: Equatable {
    let slot: Int
    let slotOffset: Int
    let sourceOffset: Int
    let count: Int
}

/// Drives a cursor the way the I/O thread does, recording every call.
private struct Recorder {
    var cursor: CaptureRingCursor
    var published: UInt64 = 0
    var consumed: UInt64 = 0
    var copies: [Copy] = []
    var publishes: [Int] = []

    init(chunk: Int, slots: Int) {
        cursor = CaptureRingCursor(chunkFrames: chunk, slotCount: slots)
    }

    mutating func write(_ frames: Int) -> (accepted: Int, dropped: Int) {
        var copies: [Copy] = []
        var publishes: [Int] = []
        let outcome = cursor.write(
            frames: frames,
            published: published,
            consumed: consumed,
            copy: { copies.append(Copy(slot: $0, slotOffset: $1, sourceOffset: $2, count: $3)) },
            publish: { publishes.append($0) }
        )
        self.copies += copies
        self.publishes += publishes
        published &+= UInt64(publishes.count)
        return outcome
    }
}

@main
struct CaptureRingCursorHarness {
    static func main() throws {
        try anExactChunkIsPublishedAtOnce()
        try aSliceSmallerThanAChunkWaitsForTheRest()
        try aLargeSliceSpansSeveralSlots()
        try slotIndicesWrapAroundTheRing()
        try aFullRingDropsTheWholeSlice()
        try aRingThatFillsMidSliceDropsOnlyTheTail()
        try theReaderCatchingUpFreesSlotsAgain()
        try resetForgetsAPartlyFilledSlot()
        try anEmptySliceDoesNothing()
        try countersSurviveWrapping()
        try everyAcceptedFrameIsCopiedExactlyOnce()
        print("Capture ring cursor harness passed")
    }

    private static func anExactChunkIsPublishedAtOnce() throws {
        var ring = Recorder(chunk: 4, slots: 3)
        let outcome = ring.write(4)
        try expect(outcome.accepted == 4 && outcome.dropped == 0, "a full chunk is accepted whole")
        try expect(ring.copies == [Copy(slot: 0, slotOffset: 0, sourceOffset: 0, count: 4)], "copied into the first slot")
        try expect(ring.publishes == [0], "and published straight away")
        try expect(ring.cursor.fill == 0, "leaving nothing half-filled")
    }

    /// The hardware's 512-frame cycles against a 1024-frame tap: half a slot,
    /// then the other half.
    private static func aSliceSmallerThanAChunkWaitsForTheRest() throws {
        var ring = Recorder(chunk: 4, slots: 3)
        _ = ring.write(3)
        try expect(ring.publishes.isEmpty, "three of four frames publish nothing")
        try expect(ring.cursor.fill == 3, "and are remembered")
        _ = ring.write(3)
        try expect(ring.copies == [
            Copy(slot: 0, slotOffset: 0, sourceOffset: 0, count: 3),
            Copy(slot: 0, slotOffset: 3, sourceOffset: 0, count: 1),
            Copy(slot: 1, slotOffset: 0, sourceOffset: 1, count: 2),
        ], "the next slice tops up the slot and spills into the next one, in order")
        try expect(ring.publishes == [0], "only the completed slot is published")
        try expect(ring.cursor.fill == 2, "the spill is carried")
    }

    private static func aLargeSliceSpansSeveralSlots() throws {
        var ring = Recorder(chunk: 4, slots: 4)
        let outcome = ring.write(10)
        try expect(outcome == (10, 0), "ten frames fit")
        try expect(ring.copies == [
            Copy(slot: 0, slotOffset: 0, sourceOffset: 0, count: 4),
            Copy(slot: 1, slotOffset: 0, sourceOffset: 4, count: 4),
            Copy(slot: 2, slotOffset: 0, sourceOffset: 8, count: 2),
        ], "split at chunk boundaries with source offsets that never overlap")
        try expect(ring.publishes == [0, 1], "two full slots published")
    }

    private static func slotIndicesWrapAroundTheRing() throws {
        var ring = Recorder(chunk: 2, slots: 3)
        ring.published = 5
        ring.consumed = 4
        _ = ring.write(2)
        try expect(ring.publishes == [2], "slot is published % slotCount")
        _ = ring.write(2)
        try expect(ring.publishes == [2, 0], "and wraps back to the first slot")
    }

    private static func aFullRingDropsTheWholeSlice() throws {
        var ring = Recorder(chunk: 4, slots: 2)
        ring.published = 2
        ring.consumed = 0
        let outcome = ring.write(4)
        try expect(outcome == (0, 4), "with every slot waiting for the reader, the slice is dropped")
        try expect(ring.copies.isEmpty && ring.publishes.isEmpty, "without touching a slot the reader still owns")
    }

    private static func aRingThatFillsMidSliceDropsOnlyTheTail() throws {
        var ring = Recorder(chunk: 4, slots: 2)
        let outcome = ring.write(10)
        try expect(outcome == (8, 2), "two slots' worth fits, the tail is dropped")
        try expect(ring.publishes == [0, 1], "both slots are published before the drop")
        try expect(ring.cursor.fill == 0, "nothing is left half-written")
    }

    private static func theReaderCatchingUpFreesSlotsAgain() throws {
        var ring = Recorder(chunk: 4, slots: 2)
        _ = ring.write(8)
        try expect(ring.write(4) == (0, 4), "full ring drops")
        ring.consumed = 1
        try expect(ring.write(4) == (4, 0), "one slot read, one slot writable again")
        try expect(ring.publishes == [0, 1, 0], "into the slot the reader just released")
    }

    private static func resetForgetsAPartlyFilledSlot() throws {
        var ring = Recorder(chunk: 4, slots: 3)
        _ = ring.write(3)
        ring.cursor.reset()
        _ = ring.write(4)
        try expect(ring.copies.last == Copy(slot: 0, slotOffset: 0, sourceOffset: 0, count: 4), "a stopped take's partial slot is not prepended to the next take")
        try expect(ring.publishes == [0], "and the new slot publishes on its own frames")
    }

    private static func anEmptySliceDoesNothing() throws {
        var ring = Recorder(chunk: 4, slots: 3)
        try expect(ring.write(0) == (0, 0), "zero frames, zero work")
        try expect(ring.copies.isEmpty && ring.publishes.isEmpty, "no calls at all")
    }

    private static func countersSurviveWrapping() throws {
        var ring = Recorder(chunk: 2, slots: 3)
        ring.published = UInt64.max
        ring.consumed = UInt64.max - 1
        try expect(ring.write(2) == (2, 0), "a difference of one is one slot in use, even at the top of the range")
        try expect(ring.publishes == [Int(UInt64.max % 3)], "the slot index stays in range")
        ring.consumed = UInt64.max &+ 1
        try expect(ring.write(2) == (2, 0), "and carries on across the wrap")
    }

    private static func everyAcceptedFrameIsCopiedExactlyOnce() throws {
        var ring = Recorder(chunk: 7, slots: 5)
        var generator = SystemRandomNumberGenerator()
        var accepted = 0
        for step in 0..<500 {
            if step % 3 == 0, ring.consumed < ring.published {
                ring.consumed += UInt64.random(in: 1...(ring.published - ring.consumed), using: &generator)
            }
            let outcome = ring.write(Int.random(in: 0...20, using: &generator))
            accepted += outcome.accepted
        }
        let copied = ring.copies.reduce(0) { $0 + $1.count }
        try expect(copied == accepted, "copies account for exactly the accepted frames (\(copied) vs \(accepted))")
        try expect(ring.publishes.count == (accepted - ring.cursor.fill) / 7, "every full chunk was published once, the partial one not yet")
        try expect(ring.copies.allSatisfy { $0.slotOffset + $0.count <= 7 }, "no copy runs past the end of a slot")
        try expect(ring.published &- ring.consumed <= 5, "the writer never got more than a ring ahead")
    }
}
