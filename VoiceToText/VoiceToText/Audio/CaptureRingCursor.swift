import Foundation

/// The bookkeeping half of `PinnedInputUnit`'s capture ring: where each
/// slice of input lands, when a slot is full enough to hand over, and what
/// has to be dropped because the reader fell behind.
///
/// The hardware hands the I/O thread a few hundred frames at a time; the
/// recorder wants the tap-sized chunks AVAudioEngine always gave it. So the
/// I/O thread fills fixed-size slots and publishes each one as it fills,
/// and a reader thread delivers them. Pure and allocation-free: it runs on
/// the real-time thread, and an off-by-one here splices audio silently, so it
/// is a harness case rather than something to hear.
nonisolated struct CaptureRingCursor {
    let chunkFrames: Int
    let slotCount: Int
    /// Frames already written into the slot being filled.
    private(set) var fill = 0

    init(chunkFrames: Int, slotCount: Int) {
        precondition(chunkFrames > 0 && slotCount > 0)
        self.chunkFrames = chunkFrames
        self.slotCount = slotCount
    }

    /// Places `frames` incoming frames. `published` and `consumed` are the
    /// ring's counters as the caller last read them; the slot being written
    /// is always `published % slotCount`, and a new one may only be started
    /// while fewer than `slotCount` are waiting for the reader. A slot already
    /// started stays the writer's — nothing can read it before it is
    /// published — so the free check applies only at a slot's first frame.
    ///
    /// Returns how many frames went into the ring (a partly filled slot
    /// included) and how many were dropped because the reader was a whole
    /// ring behind. `copy` and
    /// `publish` are called synchronously and in order; neither may block.
    mutating func write(
        frames: Int,
        published: UInt64,
        consumed: UInt64,
        copy: (_ slot: Int, _ slotOffset: Int, _ sourceOffset: Int, _ count: Int) -> Void,
        publish: (_ slot: Int) -> Void
    ) -> (accepted: Int, dropped: Int) {
        var published = published
        var offset = 0
        while offset < frames {
            if fill == 0, published &- consumed >= UInt64(slotCount) {
                return (offset, frames - offset)
            }
            let slot = Int(published % UInt64(slotCount))
            let count = min(frames - offset, chunkFrames - fill)
            copy(slot, fill, offset, count)
            fill += count
            offset += count
            if fill == chunkFrames {
                publish(slot)
                published &+= 1
                fill = 0
            }
        }
        return (frames, 0)
    }

    /// Forgets a partly filled slot, as a stop does: the tap path never
    /// delivered a partial buffer either, and `flushAndStop` waits long
    /// enough for the slot in flight to fill.
    mutating func reset() {
        fill = 0
    }
}
