import Foundation

/// Decides whether a finished take holds enough speech to be worth
/// transcribing.
///
/// The gate used to be a ratio: at least 25% of the take's 256 ms Silero
/// chunks had to clear p ≥ 0.85. That punished exactly the takes that matter —
/// a long toggle-mode dictation full of thinking pauses, soft or distant
/// speech, a Stop pressed late. Ten seconds of speech in a minute-long take is
/// 17% voiced, and the user got "No speech detected" with the words they had
/// just said thrown away. What separates speech from an accidental press is
/// how much speech there is, not what share of the take it fills, so a take
/// now passes on an absolute amount of voiced time, counted at a gentler
/// per-unit threshold. The old ratio stays as a second way through, so nothing
/// it used to accept — one short word in a sub-second take — is rejected now.
///
/// The gate is the only thing between near-silence and the model. The
/// pipeline's empty-output check behind it catches a model that returns
/// nothing, not one that invents text — which is why a take still needs real
/// voiced time to pass, rather than the gate passing everything.
///
/// Foundation-only and `nonisolated` so the harness compiles it standalone: it
/// sees per-unit scores — Silero probabilities, or frame levels in dBFS for the
/// energy fallback — and never the model.
nonisolated enum SpeechGate {
    struct Rule: Equatable, Sendable {
        /// A unit scoring at or above this counts toward the voiced time.
        var speechThreshold: Float
        /// The take passes once its voiced units add up to this much audio.
        var minVoicedSeconds: Double
        /// A unit scoring at or above this counts toward the legacy ratio.
        var ratioThreshold: Float
        /// The take also passes when this share of its units clear
        /// `ratioThreshold` — the old gate, kept so nothing it passed fails.
        var minVoicedRatio: Float
    }

    struct Verdict: Equatable, Sendable {
        let isVoiced: Bool
        /// Audio covered by units at or above `speechThreshold`.
        let voicedSeconds: Double
        /// Share of units at or above `ratioThreshold`.
        let voicedRatio: Float
    }

    /// `unitSeconds` is how much audio one score covers: 0.256 s for a Silero
    /// chunk, one RMS frame for the energy fallback. The last unit of a take is
    /// usually partial and is counted as whole, which overstates the take by
    /// at most one unit.
    static func evaluate(scores: [Float], unitSeconds: Double, rule: Rule) -> Verdict {
        guard !scores.isEmpty else {
            return Verdict(isVoiced: false, voicedSeconds: 0, voicedRatio: 0)
        }
        let speechUnits = scores.reduce(0) { $0 + ($1 >= rule.speechThreshold ? 1 : 0) }
        let ratioUnits = scores.reduce(0) { $0 + ($1 >= rule.ratioThreshold ? 1 : 0) }
        let voicedSeconds = Double(speechUnits) * unitSeconds
        let voicedRatio = Float(ratioUnits) / Float(scores.count)
        // The tolerance absorbs binary rounding in `units × unitSeconds`, so a
        // take exactly at the minimum isn't rejected by the last bit.
        let isVoiced = voicedSeconds + 1e-9 >= rule.minVoicedSeconds
            || voicedRatio >= rule.minVoicedRatio
        return Verdict(isVoiced: isVoiced, voicedSeconds: voicedSeconds, voicedRatio: voicedRatio)
    }

    /// RMS level of each `frameLength`-sample frame, in dBFS. Digital silence
    /// is `-infinity`, which no threshold reaches. A trailing partial frame is
    /// measured on what it has.
    static func frameLevels(_ samples: ArraySlice<Float>, frameLength: Int) -> [Float] {
        let frameLength = max(1, frameLength)
        var levels: [Float] = []
        levels.reserveCapacity(samples.count / frameLength + 1)
        var index = samples.startIndex
        while index < samples.endIndex {
            let end = samples.index(index, offsetBy: frameLength, limitedBy: samples.endIndex) ?? samples.endIndex
            let frame = samples[index..<end]
            let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count))
            levels.append(rms > 0 ? 20 * log10(rms) : -Float.infinity)
            index = end
        }
        return levels
    }

    /// How long to wait before trying to load Silero again after it failed
    /// `failures` times in a row: 30 s, doubling, capped at 10 minutes.
    ///
    /// A failed load used to latch the energy fallback for the rest of the
    /// session, so one launch without a network (the model downloads on first
    /// use) meant the cruder gate until the app was quit. The cap keeps a Mac
    /// that is offline for good from retrying more than a few times an hour.
    static func sileroRetryDelay(afterFailures failures: Int) -> TimeInterval {
        let base: TimeInterval = 30
        let cap: TimeInterval = 600
        guard failures > 1 else { return base }
        return min(cap, base * pow(2, Double(min(failures - 1, 16))))
    }
}
