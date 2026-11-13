import Foundation

struct UndoCountdownHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw UndoCountdownHarnessFailure(description: message)
    }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@main
struct UndoCountdownHarness {
    static func main() throws {
        var timeline = UndoCountdownTimeline(duration: 5, startedAt: 100)
        try expect(near(timeline.fraction(at: 100), 1), "full when the window opens")
        try expect(near(timeline.remaining(at: 102), 3), "3 s left after 2 s")
        try expect(near(timeline.fraction(at: 102.5), 0.5), "half drained at 2.5 s")
        try expect(!timeline.isExpired(at: 104.9), "not expired before the deadline")
        try expect(timeline.isExpired(at: 105), "expired at the deadline")
        try expect(near(timeline.fraction(at: 200), 0), "never below empty")
        try expect(near(timeline.fraction(at: 50), 1), "never above full")

        // A pause holds the ring and pushes the deadline back by its length.
        timeline = UndoCountdownTimeline(duration: 5, startedAt: 0)
        timeline.pause(at: 2)
        try expect(timeline.isPaused, "paused")
        try expect(near(timeline.remaining(at: 30), 3), "time stands still while paused")
        try expect(!timeline.isExpired(at: 30), "a paused window never expires")
        timeline.resume(at: 30)
        try expect(near(timeline.deadline, 33), "the deadline moved by the 28 s paused")
        try expect(near(timeline.remaining(at: 31), 2), "and counts on from where it stopped")
        try expect(timeline.isExpired(at: 33), "expires 3 s after resuming")

        // Pausing twice, or resuming twice, changes nothing.
        timeline = UndoCountdownTimeline(duration: 5, startedAt: 0)
        timeline.pause(at: 1)
        timeline.pause(at: 3)
        timeline.resume(at: 4)
        timeline.resume(at: 9)
        try expect(near(timeline.deadline, 8), "only the first pause and resume count")

        // A pause that lands after the deadline can't bring time back.
        timeline = UndoCountdownTimeline(duration: 5, startedAt: 0)
        timeline.pause(at: 7)
        try expect(near(timeline.remaining(at: 7), 0), "nothing left when paused late")
        timeline.resume(at: 10)
        try expect(timeline.isExpired(at: 10), "expires as soon as it resumes")

        // One pause holds the window for 30 s at most, however late the resume.
        timeline = UndoCountdownTimeline(duration: 5, startedAt: 0)
        timeline.pause(at: 2)
        timeline.resume(at: 2 + UndoCountdownTimeline.maxPause)
        try expect(near(timeline.deadline, 35), "a full-length pause still counts in full")
        timeline = UndoCountdownTimeline(duration: 5, startedAt: 0)
        timeline.pause(at: 2)
        timeline.resume(at: 500)
        try expect(near(timeline.deadline, 35), "a longer one counts only its first 30 s")
        try expect(timeline.isExpired(at: 500), "so a window left paused long past that is already over")
        timeline.pause(at: 501)
        try expect(near(timeline.remaining(at: 501), 0), "and a fresh pause can't bring it back")

        // Reduce Motion: whole seconds, stepping once a second.
        timeline = UndoCountdownTimeline(duration: 5, startedAt: 0)
        try expect(near(timeline.steppedFraction(at: 0), 1), "5 of 5 at the start")
        try expect(near(timeline.steppedFraction(at: 0.4), 1), "still 5 of 5 until a second has gone")
        try expect(near(timeline.steppedFraction(at: 1.0), 0.8), "4 of 5 after one second")
        try expect(near(timeline.steppedFraction(at: 3.7), 0.4), "2 of 5 with 1.3 s left")
        try expect(near(timeline.steppedFraction(at: 5), 0), "empty at the deadline")

        print("Undo countdown harness passed")
    }
}
