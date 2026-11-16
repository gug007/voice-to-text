import Foundation

/// Decides which stretches of a conversation survive "Remove silence": given
/// one speech verdict per unit of audio (a 256 ms Silero chunk, or the same
/// span judged by the energy fallback), the sample ranges to keep, in order
/// and non-overlapping.
///
/// Errs toward keeping audio — a clipped word is far worse than a pause left
/// in. A pause shorter than `minGapSeconds` stays exactly as it was, so speech
/// keeps its rhythm; a longer one keeps `padSeconds` against the speech on
/// either side and loses only its middle. No speech is dropped for being
/// short: one 256 ms unit can be a whole "yes".
///
/// Foundation-only and `nonisolated` so the harness compiles it standalone.
nonisolated enum SilenceTrimPlan {
    /// Pauses shorter than this are natural speech and are never cut.
    static let minGapSeconds = 2.0
    /// Audio kept against speech where a longer stretch is cut, so the cut
    /// never lands on a word's soft onset or tail.
    static let padSeconds = 0.5
    /// A plan keeping less than this is treated as "no speech found" and not
    /// applied — the transcriber's own empty check handles that recording.
    static let minKeptSeconds = 1.0
    /// A plan saving less than this isn't worth rewriting the file for.
    static let minSavedSeconds = 1.0

    /// `speech[i]` covers samples `i * unitSamples ..< (i + 1) * unitSamples`;
    /// the last unit is usually partial. A unit `speech` doesn't reach is kept,
    /// since nothing says it is silent.
    static func keepRanges(
        speech: [Bool],
        unitSamples: Int,
        totalSamples: Int,
        sampleRate: Int
    ) -> [Range<Int>] {
        guard unitSamples > 0, totalSamples > 0, sampleRate > 0 else { return [] }
        let unitCount = (totalSamples + unitSamples - 1) / unitSamples
        let minGap = Int((minGapSeconds * Double(sampleRate)).rounded())
        let pad = Int((padSeconds * Double(sampleRate)).rounded())
        let isSpeech = { (unit: Int) in unit >= speech.count || speech[unit] }

        var runs: [Range<Int>] = []
        var unit = 0
        while unit < unitCount {
            guard isSpeech(unit) else {
                unit += 1
                continue
            }
            let first = unit
            while unit < unitCount, isSpeech(unit) { unit += 1 }
            let run = (first * unitSamples)..<min(unit * unitSamples, totalSamples)
            if let last = runs.last, run.lowerBound - last.upperBound < minGap {
                runs[runs.count - 1] = last.lowerBound..<run.upperBound
            } else {
                runs.append(run)
            }
        }

        var kept: [Range<Int>] = []
        for run in runs {
            let padded = max(0, run.lowerBound - pad)..<min(totalSamples, run.upperBound + pad)
            if let last = kept.last, padded.lowerBound <= last.upperBound {
                kept[kept.count - 1] = last.lowerBound..<max(last.upperBound, padded.upperBound)
            } else {
                kept.append(padded)
            }
        }
        return kept
    }

    /// Whether `ranges` keeps enough to be speech and cuts enough to matter.
    static func isWorthApplying(_ ranges: [Range<Int>], totalSamples: Int, sampleRate: Int) -> Bool {
        guard sampleRate > 0 else { return false }
        let kept = ranges.reduce(0) { $0 + $1.count }
        let rate = Double(sampleRate)
        return Double(kept) >= minKeptSeconds * rate
            && Double(totalSamples - kept) >= minSavedSeconds * rate
    }
}
