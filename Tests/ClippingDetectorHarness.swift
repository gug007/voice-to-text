import Foundation

struct ClippingDetectorHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ClippingDetectorHarnessFailure(description: message)
    }
}

/// Feeds `seconds` of samples every `step`, clipping or not, from `start`.
/// Returns the time after the last sample and whether the warning was on
/// after each one.
@discardableResult
private func feed(
    _ detector: inout ClippingDetector,
    clipping: Bool,
    from start: TimeInterval,
    for seconds: TimeInterval,
    step: TimeInterval = 0.05
) -> (end: TimeInterval, states: [Bool]) {
    var time = start
    var states: [Bool] = []
    while time < start + seconds - step / 2 {
        states.append(detector.update(isClipping: clipping, at: time))
        time += step
    }
    return (time, states)
}

@main
struct ClippingDetectorHarness {
    static func main() throws {
        // A loud syllable — a quarter second of clipping — says nothing.
        var detector = ClippingDetector()
        var run = feed(&detector, clipping: false, from: 0, for: 1)
        run = feed(&detector, clipping: true, from: run.end, for: 0.25)
        run = feed(&detector, clipping: false, from: run.end, for: 1)
        try expect(!detector.isSustained, "a short burst does not turn the warning on")

        // About a second of clipping turns it on, not much sooner.
        detector = ClippingDetector()
        run = feed(&detector, clipping: true, from: 10, for: 0.8)
        try expect(!detector.isSustained, "0.8 s of clipping is not yet sustained")
        run = feed(&detector, clipping: true, from: run.end, for: 0.4)
        try expect(detector.isSustained, "1.2 s of clipping is sustained")

        // It stays on through short clean gaps, and goes after ~2 s clean.
        run = feed(&detector, clipping: false, from: run.end, for: 1.5)
        try expect(run.states.allSatisfy { $0 }, "1.5 s clean keeps the warning on")
        run = feed(&detector, clipping: false, from: run.end, for: 0.6)
        try expect(!detector.isSustained, "2 s clean turns the warning off")

        // Intermittent clipping that adds up within the window counts.
        detector = ClippingDetector()
        var time: TimeInterval = 20
        for _ in 0..<6 {
            run = feed(&detector, clipping: true, from: time, for: 0.2)
            run = feed(&detector, clipping: false, from: run.end, for: 0.05)
            time = run.end
        }
        try expect(detector.isSustained, "clipping that adds up to a second in the window turns it on")

        // Bursts spread too thinly never add up.
        detector = ClippingDetector()
        time = 40
        for _ in 0..<10 {
            run = feed(&detector, clipping: true, from: time, for: 0.2)
            run = feed(&detector, clipping: false, from: run.end, for: 0.8)
            time = run.end
        }
        try expect(!detector.isSustained, "a burst every second stays under the threshold")

        // No flicker: once on, it doesn't toggle with every syllable.
        detector = ClippingDetector()
        run = feed(&detector, clipping: true, from: 60, for: 1.2)
        var toggles = 0
        var last = detector.isSustained
        time = run.end
        for _ in 0..<8 {
            for clipping in [false, true] {
                run = feed(&detector, clipping: clipping, from: time, for: 0.3)
                for state in run.states where state != last {
                    toggles += 1
                    last = state
                }
                time = run.end
            }
        }
        try expect(toggles == 0, "alternating clean and loud syllables never toggle the warning")

        // A stall in the feed is not a second of clipping.
        detector = ClippingDetector()
        detector.update(isClipping: true, at: 80)
        detector.update(isClipping: false, at: 81.5)
        try expect(!detector.isSustained, "one clipping sample then a long gap is not sustained")

        // Reset forgets everything.
        detector = ClippingDetector()
        feed(&detector, clipping: true, from: 90, for: 1.5)
        try expect(detector.isSustained, "on before reset")
        detector.reset()
        try expect(!detector.isSustained, "reset turns it off")
        detector.update(isClipping: true, at: 91.6)
        try expect(!detector.isSustained, "and the next sample starts from nothing")

        print("Clipping detector harness passed")
    }
}
