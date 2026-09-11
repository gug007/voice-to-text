import Foundation

struct ModelQualityScoreHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ModelQualityScoreHarnessFailure(description: message)
    }
}

private func measurement(
    _ benchmark: WERMeasurement.Benchmark,
    _ percent: Double,
    isEstimate: Bool = false
) -> WERMeasurement {
    WERMeasurement(benchmark: benchmark, percent: percent, isEstimate: isEstimate, note: nil)
}

@main
struct ModelQualityScoreHarness {
    static func main() throws {
        try referenceScoresEightOnEveryBenchmark()
        try halvingErrorsClampsAtTen()
        try doublingErrorsCostsThreePoints()
        try quadrupleErrorsCostsSixPoints()
        try farWorseThanReferenceClampsAtOne()
        try directArtificialAnalysisOverridesOpenASR()
        try indirectEvidencePoolsAcrossBenchmarks()
        try pooledRatiosCombineByGeometricMean()
        try scoreRoundsToOneDecimal()
        try noMeasurementsHasNoScore()
        try approximateTracksDirectMeasurement()
        print("Model quality score harness passed")
    }

    /// Whisper Large v3 is the yardstick, so its own figure must land on the
    /// anchor whichever benchmark it is read from.
    private static func referenceScoresEightOnEveryBenchmark() throws {
        for benchmark in [WERMeasurement.Benchmark.openASRLeaderboard, .artificialAnalysis] {
            let reference = benchmark.whisperLargeV3Percent
            let score = ModelQualityScore.score(for: [measurement(benchmark, reference)])
            try expect(score == 8.0, "\(benchmark.rawValue) reference scores 8.0, got \(score as Any)")
        }
    }

    /// 8 + 3 = 11, which the 1...10 clamp has to pull back to 10.
    private static func halvingErrorsClampsAtTen() throws {
        let half = WERMeasurement.Benchmark.artificialAnalysis.whisperLargeV3Percent / 2
        let score = ModelQualityScore.score(for: [measurement(.artificialAnalysis, half)])
        try expect(score == 10.0, "half the reference errors clamps to 10.0, got \(score as Any)")
    }

    private static func doublingErrorsCostsThreePoints() throws {
        let double = WERMeasurement.Benchmark.openASRLeaderboard.whisperLargeV3Percent * 2
        let score = ModelQualityScore.score(for: [measurement(.openASRLeaderboard, double)])
        try expect(score == 5.0, "twice the reference errors scores 5.0, got \(score as Any)")
    }

    private static func quadrupleErrorsCostsSixPoints() throws {
        let quadruple = WERMeasurement.Benchmark.openASRLeaderboard.whisperLargeV3Percent * 4
        let score = ModelQualityScore.score(for: [measurement(.openASRLeaderboard, quadruple)])
        try expect(score == 2.0, "four times the reference errors scores 2.0, got \(score as Any)")
    }

    /// 8 − 12 = −4, which the clamp has to lift to the 1.0 floor.
    private static func farWorseThanReferenceClampsAtOne() throws {
        let sixteenFold = WERMeasurement.Benchmark.openASRLeaderboard.whisperLargeV3Percent * 16
        let score = ModelQualityScore.score(for: [measurement(.openASRLeaderboard, sixteenFold)])
        try expect(score == 1.0, "sixteen times the reference errors clamps to 1.0, got \(score as Any)")
    }

    /// Whisper Large v3 Turbo, the case that motivates the primary scale: its
    /// own AA figure decides the score outright, and the Open ASR number it also
    /// has — the easier benchmark, where it looks better — cannot pull it up.
    private static func directArtificialAnalysisOverridesOpenASR() throws {
        let both = ModelQualityScore.score(for: [
            measurement(.openASRLeaderboard, 7.75),
            measurement(.artificialAnalysis, 4.6),
        ])
        let aaAlone = ModelQualityScore.score(for: [measurement(.artificialAnalysis, 4.6)])
        try expect(both == 7.5, "Turbo scores 7.5 from AA alone, got \(both as Any)")
        try expect(both == aaAlone, "the Open ASR figure changes nothing, got \(both as Any)")
    }

    /// Parakeet TDT v3, the case that motivates pooling: no AA run of its own,
    /// so its predecessor's AA figure and its own Open ASR figure are averaged,
    /// and the result is flagged approximate.
    private static func indirectEvidencePoolsAcrossBenchmarks() throws {
        let measurements = [
            measurement(.artificialAnalysis, 6.4, isEstimate: true),
            measurement(.openASRLeaderboard, 6.32),
        ]
        let score = ModelQualityScore.score(for: measurements)
        try expect(score == 7.4, "Parakeet pools to 7.4, got \(score as Any)")
        try expect(ModelQualityScore.isApproximate(measurements), "a pooled score is approximate")
    }

    private static func pooledRatiosCombineByGeometricMean() throws {
        // A ratio and its reciprocal cancel, landing back on the anchor. Neither
        // figure is a direct AA measurement, so both are pooled.
        let score = ModelQualityScore.score(for: [
            measurement(.openASRLeaderboard, WERMeasurement.Benchmark.openASRLeaderboard.whisperLargeV3Percent * 2),
            measurement(.artificialAnalysis, WERMeasurement.Benchmark.artificialAnalysis.whisperLargeV3Percent / 2, isEstimate: true),
        ])
        try expect(score == 8.0, "opposite ratios cancel to 8.0, got \(score as Any)")
    }

    private static func scoreRoundsToOneDecimal() throws {
        let score = ModelQualityScore.score(for: [measurement(.openASRLeaderboard, 6.32)])
        try expect(score == 8.7, "6.32% on Open ASR alone rounds to 8.7, got \(score as Any)")
        guard let score else { throw ModelQualityScoreHarnessFailure(description: "expected a score") }
        try expect((score * 10).rounded() == score * 10, "score carries at most one decimal")
    }

    private static func noMeasurementsHasNoScore() throws {
        try expect(ModelQualityScore.score(for: []) == nil, "no measurements means no score")
        try expect(!ModelQualityScore.isApproximate([]), "no measurements is not approximate")
    }

    /// "Approximate" tracks the absence of a direct AA figure, not whether a
    /// number was measured — an Open-ASR-only model is measured, just not on the
    /// scale the score claims.
    private static func approximateTracksDirectMeasurement() throws {
        let direct = measurement(.artificialAnalysis, 4.0)
        let carriedOver = measurement(.artificialAnalysis, 4.0, isEstimate: true)
        let secondary = measurement(.openASRLeaderboard, 8.59)
        try expect(!ModelQualityScore.isApproximate([direct]), "a direct AA figure is not approximate")
        try expect(
            ModelQualityScore.isApproximate([carriedOver]),
            "a sibling's AA figure is approximate"
        )
        try expect(
            ModelQualityScore.isApproximate([secondary]),
            "an Open-ASR-only score is approximate — measured, but on the secondary scale"
        )
        try expect(
            !ModelQualityScore.isApproximate([secondary, direct]),
            "one direct AA figure is enough to stand behind the score"
        )
        try expect(
            !ModelQualityScore.isApproximate([carriedOver, direct]),
            "a direct figure outranks a carried-over one"
        )
    }
}
