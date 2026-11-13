import Foundation

struct ReviewPolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ReviewPolicyHarnessFailure(description: message)
    }
}

private func opens(_ mode: ReviewMode, _ seconds: TimeInterval) -> Bool {
    ReviewPolicy.opensReview(
        mode: mode,
        takeSeconds: seconds,
        longTakeSeconds: ReviewPolicy.defaultLongTakeSeconds
    )
}

@main
struct ReviewPolicyHarness {
    static func main() throws {
        let long = ReviewPolicy.defaultLongTakeSeconds
        try expect(long == 15, "long takes start past 15 seconds")

        // Each mode × short / boundary / long.
        try expect(opens(.always, 3), "Always reviews a short take")
        try expect(opens(.always, long), "Always reviews a take at the boundary")
        try expect(opens(.always, 60), "Always reviews a long take")
        try expect(!opens(.longTakes, 3), "Long takes pastes a short take")
        try expect(!opens(.longTakes, long), "Long takes pastes a take of exactly 15 seconds")
        try expect(opens(.longTakes, long + 0.01), "Long takes reviews a take just past 15 seconds")
        try expect(opens(.longTakes, 60), "Long takes reviews a long take")
        try expect(!opens(.never, 3), "Never pastes a short take")
        try expect(!opens(.never, long), "Never pastes a take at the boundary")
        try expect(!opens(.never, 60), "Never pastes a long take")

        // Migration from the old Bool, on every read while review.mode is absent.
        try expect(ReviewPolicy.mode(storedMode: nil, legacyBeforePaste: true) == .always, "old true → Always")
        try expect(ReviewPolicy.mode(storedMode: nil, legacyBeforePaste: false) == .never, "old false → Never")
        try expect(ReviewPolicy.mode(storedMode: nil, legacyBeforePaste: nil) == .always, "nothing stored → Always")
        try expect(ReviewPolicy.mode(storedMode: "longTakes", legacyBeforePaste: false) == .longTakes, "review.mode wins over the old key")
        try expect(ReviewPolicy.mode(storedMode: "never", legacyBeforePaste: true) == .never, "a stored Never wins over an old true")
        try expect(ReviewPolicy.mode(storedMode: "bogus", legacyBeforePaste: false) == .never, "an unreadable mode falls back to the old key")
        for mode in ReviewMode.allCases {
            try expect(ReviewPolicy.mode(storedMode: mode.rawValue, legacyBeforePaste: nil) == mode, "\(mode) round-trips")
        }

        // Writing a mode keeps the old key meaningful for an older build.
        try expect(ReviewPolicy.values(for: .always) == ("always", true), "Always writes the old key on")
        try expect(ReviewPolicy.values(for: .longTakes) == ("longTakes", true), "Long takes writes the old key on")
        try expect(ReviewPolicy.values(for: .never) == ("never", false), "Never writes the old key off")

        // The threshold override.
        try expect(ReviewPolicy.longTakeSeconds(override: nil) == long, "no override → 15")
        try expect(ReviewPolicy.longTakeSeconds(override: 30) == 30, "a positive override is honoured")
        try expect(ReviewPolicy.longTakeSeconds(override: 0) == long, "a zero override is ignored")
        try expect(ReviewPolicy.longTakeSeconds(override: -5) == long, "a negative override is ignored")
        try expect(ReviewPolicy.longTakeSeconds(override: .nan) == long, "a non-finite override is ignored")

        // Through real defaults: the old key alone, then the new key beside it.
        let suite = "ReviewPolicyHarness.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw ReviewPolicyHarnessFailure(description: "could not open a defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        try expect(ReviewPolicy.mode(in: defaults) == .always, "fresh defaults → Always")
        defaults.set(false, forKey: ReviewPolicy.legacyKey)
        try expect(ReviewPolicy.mode(in: defaults) == .never, "old key off → Never")
        try expect(ReviewPolicy.mode(in: defaults) == .never, "and still Never on the next read")
        try expect(defaults.object(forKey: ReviewPolicy.modeKey) == nil, "reading never writes review.mode")
        try expect(!ReviewPolicy.opensReview(takeSeconds: 60, in: defaults), "Never pastes through defaults")
        defaults.set("longTakes", forKey: ReviewPolicy.modeKey)
        try expect(defaults.object(forKey: ReviewPolicy.legacyKey) as? Bool == false, "the old key is left alone")
        try expect(!ReviewPolicy.opensReview(takeSeconds: 10, in: defaults), "Long takes pastes 10 s")
        try expect(ReviewPolicy.opensReview(takeSeconds: 20, in: defaults), "Long takes reviews 20 s")
        defaults.set(30.0, forKey: ReviewPolicy.longTakeSecondsKey)
        try expect(!ReviewPolicy.opensReview(takeSeconds: 20, in: defaults), "the override raises the threshold")
        defaults.set(30, forKey: ReviewPolicy.longTakeSecondsKey)
        try expect(ReviewPolicy.longTakeSeconds(in: defaults) == 30, "an integer override reads too")

        print("Review policy harness passed")
    }
}
