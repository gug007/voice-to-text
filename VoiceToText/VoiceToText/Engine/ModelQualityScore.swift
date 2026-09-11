import Foundation

/// One published word-error-rate figure for a model on a named benchmark.
///
/// `nonisolated` so the score maths stays usable from anywhere (and from the
/// standalone harness) — the module defaults to MainActor isolation otherwise.
nonisolated struct WERMeasurement: Hashable, Sendable {
    enum Benchmark: String, Hashable, Sendable {
        /// Hugging Face Open ASR Leaderboard — English average across its test
        /// sets. Covers open-weights models only, so no cloud API appears here.
        case openASRLeaderboard
        /// Artificial Analysis AA-WER v2 (batch) and AA-WER Streaming
        /// final-transcript figures. Both run the same three datasets
        /// (AA-AgentTalk 50%, VoxPopuli 25%, Earnings22 25%), so a batch and a
        /// streaming number are directly comparable.
        case artificialAnalysis

        var displayName: String {
            switch self {
            case .openASRLeaderboard: return "Open ASR Leaderboard"
            case .artificialAnalysis: return "Artificial Analysis AA-WER"
            }
        }

        /// Whisper Large v3's WER on this benchmark. It is the one model
        /// measured on every benchmark we cite, so it is the yardstick every
        /// other model is expressed against — which is what lets a score mix
        /// figures from two leaderboards that share no other model.
        var whisperLargeV3Percent: Double {
            switch self {
            case .openASRLeaderboard: return 7.44
            case .artificialAnalysis: return 4.1
            }
        }
    }

    let benchmark: Benchmark
    let percent: Double
    /// True when the figure was not measured for this model but carried over
    /// from a sibling (the row shows "≈").
    let isEstimate: Bool
    /// Provenance or caveat shown in the row tooltip. Optional.
    let note: String?
}

/// Turns published word-error rates into the 1–10 "Quality" number the Models
/// pane prints and sorts by.
///
/// The scale is logarithmic because WER is multiplicative in the user's effort:
/// twice the WER is twice as many words to go back and fix, and the step from
/// 4% to 8% costs the same as the step from 8% to 16%. A linear rating would
/// squash every good model into the top point and spend most of its range on
/// models nobody would pick.
///
/// **Artificial Analysis is the primary scale.** It is the one benchmark that
/// runs local models and cloud APIs over the same harder audio, so its numbers
/// are the only ones that compare the two halves of the catalog on equal terms.
/// A model with its own AA figure is scored on that alone.
///
/// Everything else — the Open ASR Leaderboard, and AA figures carried over from
/// a sibling model — is indirect evidence, pooled only when nothing direct
/// exists. Open ASR runs easier English audio and its rankings do not carry
/// over: Parakeet beats Whisper there, while the Parakeet family trails Whisper
/// badly on AA, which is the ordering users actually experience. Letting an
/// Open ASR figure average against a direct AA figure would let the easier
/// benchmark pull a model above models measured honestly on the harder one, so
/// it no longer can. A pooled score is flagged approximate and the row prefixes
/// it with "≈".
///
/// Whisper Large v3 anchors the scale at `referenceScore` on every benchmark by
/// construction. It is the only model measured on both leaderboards we cite, so
/// expressing each figure as a ratio against it is what makes an Open ASR
/// number mean anything on the AA scale at all.
///
/// `pointsPerDoubling` is 3, which puts the interesting range on screen: half
/// Whisper Large v3's errors rounds to a 10, twice its errors is a 5, and four
/// times its errors is a 2.
nonisolated enum ModelQualityScore {
    /// Whisper Large v3 scores exactly this on every benchmark by construction.
    static let referenceScore = 8.0
    /// Points lost per doubling of errors relative to Whisper Large v3 (and
    /// gained per halving).
    static let pointsPerDoubling = 3.0

    /// The 1–10 score for a set of measurements, or `nil` when there are none.
    ///
    /// Scores from the model's own Artificial Analysis figures when it has any,
    /// and otherwise pools every measurement it does have. Either way each
    /// figure becomes a ratio against its own benchmark's Whisper Large v3
    /// number, and the ratios combine by geometric mean — the right average for
    /// a quantity read on a log scale, and the one that keeps a model measured
    /// twice from being dragged around by whichever run went better. Clamped to
    /// 1...10 and rounded to one decimal.
    static func score(for measurements: [WERMeasurement]) -> Double? {
        let scoring = scoringMeasurements(measurements)
        guard !scoring.isEmpty else { return nil }
        let logSum = scoring.reduce(0.0) { total, measurement in
            total + log2(measurement.percent / measurement.benchmark.whisperLargeV3Percent)
        }
        let meanLogRatio = logSum / Double(scoring.count)
        let raw = referenceScore - pointsPerDoubling * meanLogRatio
        let clamped = min(10.0, max(1.0, raw))
        return (clamped * 10).rounded() / 10
    }

    /// True when the score rests on indirect evidence — no Artificial Analysis
    /// figure of the model's own — so the UI prefixes it with "≈". That covers
    /// both a sibling's AA number carried over and an Open-ASR-only model: the
    /// latter is genuinely measured, just not on the scale the score claims.
    static func isApproximate(_ measurements: [WERMeasurement]) -> Bool {
        !measurements.isEmpty && directMeasurements(measurements).isEmpty
    }

    /// The figures a score is actually built from: the direct ones when they
    /// exist, the whole pool when they don't.
    private static func scoringMeasurements(_ measurements: [WERMeasurement]) -> [WERMeasurement] {
        let direct = directMeasurements(measurements)
        return direct.isEmpty ? measurements : direct
    }

    /// Artificial Analysis figures measured on this model itself — not carried
    /// over from a sibling, and not from the secondary leaderboard.
    private static func directMeasurements(_ measurements: [WERMeasurement]) -> [WERMeasurement] {
        measurements.filter { $0.benchmark == .artificialAnalysis && !$0.isEstimate }
    }
}
