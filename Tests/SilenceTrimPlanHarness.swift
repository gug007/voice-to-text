import Foundation

struct SilenceTrimPlanHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SilenceTrimPlanHarnessFailure(description: message)
    }
}

private let rate = 16_000
/// Silero's chunk: 4096 samples, 256 ms.
private let unit = 4_096
private let pad = rate / 2

/// `count` units of speech (true) or silence (false).
private func units(_ count: Int, _ speech: Bool) -> [Bool] {
    Array(repeating: speech, count: count)
}

/// Units covering about `seconds` of audio.
private func unitsFor(_ seconds: Double) -> Int {
    Int((seconds * Double(rate) / Double(unit)).rounded())
}

private func plan(_ speech: [Bool], total: Int? = nil) -> [Range<Int>] {
    SilenceTrimPlan.keepRanges(
        speech: speech,
        unitSamples: unit,
        totalSamples: total ?? speech.count * unit,
        sampleRate: rate
    )
}

private func keptSamples(_ ranges: [Range<Int>]) -> Int {
    ranges.reduce(0) { $0 + $1.count }
}

/// Sorted, non-empty, non-overlapping and non-touching (touching ranges are merged).
private func isWellFormed(_ ranges: [Range<Int>], total: Int) -> Bool {
    for (index, range) in ranges.enumerated() {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= total else { return false }
        if index > 0, ranges[index - 1].upperBound >= range.lowerBound { return false }
    }
    return true
}

@main
struct SilenceTrimPlanHarness {
    static func main() throws {
        try allSilenceKeepsNothing()
        try allSpeechKeepsEverything()
        try longMiddleGapIsCutToThePads()
        try shortGapsArePreserved()
        try gapBoundaryAtTheMinimum()
        try padsClampAtFileEdges()
        try leadingAndTrailingSilenceTrimToThePad()
        try adjacentRangesMerge()
        try partialLastUnitIsClamped()
        try unscoredUnitsAreKept()
        try singleUnitBlipIsKept()
        try worthApplyingThresholds()
        try degenerateInputs()
        print("Silence trim plan harness passed")
    }

    private static func allSilenceKeepsNothing() throws {
        let speech = units(unitsFor(60), false)
        let ranges = plan(speech)
        try expect(ranges.isEmpty, "all silence keeps nothing (\(ranges))")
        try expect(
            !SilenceTrimPlan.isWorthApplying(ranges, totalSamples: speech.count * unit, sampleRate: rate),
            "a plan keeping nothing is never applied"
        )
    }

    private static func allSpeechKeepsEverything() throws {
        let speech = units(unitsFor(60), true)
        let total = speech.count * unit
        let ranges = plan(speech)
        try expect(ranges == [0..<total], "all speech is one whole range (\(ranges))")
        try expect(
            !SilenceTrimPlan.isWorthApplying(ranges, totalSamples: total, sampleRate: rate),
            "a plan that cuts nothing is not applied"
        )
    }

    /// The motivating case: half an hour nobody spoke.
    private static func longMiddleGapIsCutToThePads() throws {
        let first = unitsFor(10)
        let gap = unitsFor(30 * 60)
        let second = unitsFor(10)
        let speech = units(first, true) + units(gap, false) + units(second, true)
        let total = speech.count * unit
        let ranges = plan(speech)
        let secondStart = (first + gap) * unit
        try expect(ranges == [0..<(first * unit + pad), (secondStart - pad)..<total], "the gap's middle goes (\(ranges))")
        try expect(keptSamples(ranges) == (first + second) * unit + 2 * pad, "speech plus one pad each side of the cut")
        try expect(SilenceTrimPlan.isWorthApplying(ranges, totalSamples: total, sampleRate: rate), "and it is applied")
    }

    private static func shortGapsArePreserved() throws {
        var speech: [Bool] = []
        for _ in 0..<10 {
            speech += units(unitsFor(4), true) + units(unitsFor(1.5), false)
        }
        speech += units(unitsFor(4), true)
        let total = speech.count * unit
        let ranges = plan(speech)
        try expect(ranges == [0..<total], "1.5 s pauses all stay (\(ranges))")
    }

    /// 7 units = 1.792 s stays; 8 units = 2.048 s is cut.
    private static func gapBoundaryAtTheMinimum() throws {
        let speak = unitsFor(3)
        let under = units(speak, true) + units(7, false) + units(speak, true)
        try expect(plan(under) == [0..<(under.count * unit)], "a gap just under the minimum stays")

        let over = units(speak, true) + units(8, false) + units(speak, true)
        let ranges = plan(over)
        try expect(ranges.count == 2, "a gap just over the minimum is cut (\(ranges))")
        try expect(
            ranges[1].lowerBound - ranges[0].upperBound == 8 * unit - 2 * pad,
            "losing only what lies between the pads"
        )
    }

    private static func padsClampAtFileEdges() throws {
        let gap = unitsFor(60)
        let speech = units(1, true) + units(gap, false) + units(1, true)
        let total = speech.count * unit
        let ranges = plan(speech)
        try expect(ranges.count == 2, "two islands (\(ranges))")
        try expect(ranges[0].lowerBound == 0, "the leading pad clamps at the start")
        try expect(ranges[1].upperBound == total, "the trailing pad clamps at the end")
        try expect(isWellFormed(ranges, total: total), "well formed")
    }

    private static func leadingAndTrailingSilenceTrimToThePad() throws {
        let lead = unitsFor(20)
        let body = unitsFor(10)
        let speech = units(lead, false) + units(body, true) + units(unitsFor(20), false)
        let ranges = plan(speech)
        try expect(
            ranges == [(lead * unit - pad)..<((lead + body) * unit + pad)],
            "silence at either end trims to the pad (\(ranges))"
        )
    }

    private static func adjacentRangesMerge() throws {
        // Speech, a short pause, speech, a short pause, speech: one range,
        // never one per unit or per run.
        let speech = units(10, false) + units(5, true) + units(3, false) + units(5, true)
            + units(1, false) + units(5, true) + units(10, false)
        let ranges = plan(speech)
        try expect(ranges.count == 1, "runs bridged by short pauses merge into one range (\(ranges))")
        try expect(ranges[0] == (10 * unit - pad)..<(29 * unit + pad), "spanning first to last speech plus pads")

        // A long pseudo-random pattern stays sorted, disjoint and never drops a speech unit.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var random: [Bool] = []
        for _ in 0..<5_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            random.append((state >> 33) % 23 == 0)
        }
        let total = random.count * unit - 1_234
        let mixed = plan(random, total: total)
        try expect(isWellFormed(mixed, total: total), "random plan is well formed")
        for (index, isSpeech) in random.enumerated() where isSpeech {
            let start = index * unit
            let end = min(start + unit, total)
            try expect(
                mixed.contains { $0.lowerBound <= start && $0.upperBound >= end },
                "speech unit \(index) is kept whole"
            )
        }
    }

    private static func partialLastUnitIsClamped() throws {
        let total = 100 * unit + 1_000
        let speech = units(100, false) + units(1, true)
        let ranges = plan(speech, total: total)
        try expect(ranges == [(100 * unit - pad)..<total], "a partial last unit ends at the file's end (\(ranges))")
    }

    private static func unscoredUnitsAreKept() throws {
        let total = 200 * unit
        let ranges = plan(units(100, false), total: total)
        try expect(ranges == [(100 * unit - pad)..<total], "units with no verdict count as speech (\(ranges))")
        let extra = plan(units(5, true) + units(50, false) + units(10, true), total: 20 * unit)
        try expect(extra == [0..<(5 * unit + pad)], "verdicts past the end are ignored (\(extra))")
    }

    private static func singleUnitBlipIsKept() throws {
        let speech = units(unitsFor(60), false) + units(1, true) + units(unitsFor(60), false)
        let ranges = plan(speech)
        let start = unitsFor(60) * unit
        try expect(ranges == [(start - pad)..<(start + unit + pad)], "a lone 256 ms unit is kept (\(ranges))")
    }

    private static func worthApplyingThresholds() throws {
        let total = 60 * rate
        try expect(!SilenceTrimPlan.isWorthApplying([0..<(rate - 1)], totalSamples: total, sampleRate: rate), "under 1 s kept is not applied")
        try expect(SilenceTrimPlan.isWorthApplying([0..<rate], totalSamples: total, sampleRate: rate), "1 s kept is applied")
        try expect(!SilenceTrimPlan.isWorthApplying([0..<(total - rate + 1)], totalSamples: total, sampleRate: rate), "under 1 s saved is not applied")
        try expect(SilenceTrimPlan.isWorthApplying([0..<(total - rate)], totalSamples: total, sampleRate: rate), "1 s saved is applied")
    }

    private static func degenerateInputs() throws {
        try expect(plan([], total: 0).isEmpty, "an empty file plans nothing")
        try expect(
            SilenceTrimPlan.keepRanges(speech: [true], unitSamples: 0, totalSamples: 100, sampleRate: rate).isEmpty,
            "a zero unit plans nothing"
        )
        try expect(!SilenceTrimPlan.isWorthApplying([], totalSamples: 0, sampleRate: 0), "no rate, not applied")
    }
}
