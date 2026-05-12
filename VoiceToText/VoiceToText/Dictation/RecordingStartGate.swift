import Foundation

struct RecordingStartGate {
    typealias StartID = UInt64

    private var nextID: StartID = 0
    private var activeStartID: StartID?
    private var pendingHoldStartID: StartID?

    var hasPendingHoldStart: Bool {
        pendingHoldStartID != nil
    }

    mutating func beginStart(pendingHold: Bool) -> StartID {
        nextID += 1
        activeStartID = nextID
        pendingHoldStartID = pendingHold ? nextID : nil
        return nextID
    }

    mutating func cancelPendingHoldStart() {
        guard let id = pendingHoldStartID else { return }
        if activeStartID == id {
            activeStartID = nil
        }
        pendingHoldStartID = nil
    }

    func accepts(_ id: StartID) -> Bool {
        activeStartID == id
    }

    mutating func finish(_ id: StartID) {
        if activeStartID == id {
            activeStartID = nil
        }
        if pendingHoldStartID == id {
            pendingHoldStartID = nil
        }
    }

    mutating func reset() {
        activeStartID = nil
        pendingHoldStartID = nil
    }
}
