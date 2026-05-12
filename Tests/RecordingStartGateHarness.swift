import Foundation

struct RecordingStartGateHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RecordingStartGateHarnessFailure(description: message)
    }
}

@main
struct RecordingStartGateHarness {
    static func main() throws {
        try quickReleaseCancelsOnlyTheFirstStart()
        try releaseDuringPreparationInvalidatesTheActiveStart()
        print("Recording start gate harness passed")
    }

    private static func quickReleaseCancelsOnlyTheFirstStart() throws {
        var gate = RecordingStartGate()

        let first = gate.beginStart(pendingHold: true)
        try expect(gate.hasPendingHoldStart, "first hold start is pending")
        gate.cancelPendingHoldStart()
        try expect(!gate.accepts(first), "released first start is stale")

        let second = gate.beginStart(pendingHold: true)
        try expect(gate.accepts(second), "second hold start remains current")
        try expect(!gate.accepts(first), "first start cannot become current again")
    }

    private static func releaseDuringPreparationInvalidatesTheActiveStart() throws {
        var gate = RecordingStartGate()

        let start = gate.beginStart(pendingHold: true)
        gate.cancelPendingHoldStart()
        try expect(!gate.hasPendingHoldStart, "release clears pending hold state")
        try expect(!gate.accepts(start), "cancelled preparation cannot continue")
    }
}
