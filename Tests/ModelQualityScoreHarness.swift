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
        try twoBenchmarksCombineByGeometricMean()
        try scoreRoundsToOneDecimal()
        try noMeasurementsHasNoScore()
        try isEstimateOnlyWhenEveryMeasurementIsOne()
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

    /// Whisper Large v3 Turbo, the real case that motivates the geometric mean:
    /// 7.75% on Open ASR and 4.6% on AA-WER, each against its own reference.
    private static func twoBenchmarksCombineByGeometricMean() throws {
        let score = ModelQualityScore.score(for: [
            measurement(.openASRLeaderboard, 7.75),
            measurement(.artificialAnalysis, 4.6),
        ])
        try expect(score == 7.7, "Turbo's two benchmarks combine to 7.7, got \(score as Any)")

        // A ratio and its reciprocal cancel, landing back on the anchor.
        let cancelling = ModelQualityScore.score(for: [
            measurement(.openASRLeaderboard, WERMeasurement.Benchmark.openASRLeaderboard.whisperLargeV3Percent * 2),
            measurement(.artificialAnalysis, WERMeasurement.Benchmark.artificialAnalysis.whisperLargeV3Percent / 2),
        ])
        try expect(cancelling == 8.0, "opposite ratios cancel to 8.0, got \(cancelling as Any)")
    }

    private static func scoreRoundsToOneDecimal() throws {
        let score = ModelQualityScore.score(for: [measurement(.openASRLeaderboard, 6.32)])
        try expect(score == 8.7, "Parakeet's 6.32% rounds to 8.7, got \(score as Any)")
        guard let score else { throw ModelQualityScoreHarnessFailure(description: "expected a score") }
        try expect((score * 10).rounded() == score * 10, "score carries at most one decimal")
    }

    private static func noMeasurementsHasNoScore() throws {
        try expect(ModelQualityScore.score(for: []) == nil, "no measurements means no score")
        try expect(!ModelQualityScore.isEstimate([]), "no measurements is not an estimate")
    }

    private static func isEstimateOnlyWhenEveryMeasurementIsOne() throws {
        let measured = measurement(.artificialAnalysis, 4.0)
        let estimated = measurement(.artificialAnalysis, 4.0, isEstimate: true)
        try expect(!ModelQualityScore.isEstimate([measured]), "a measured figure is not an estimate")
        try expect(ModelQualityScore.isEstimate([estimated]), "a lone carried-over figure is an estimate")
        try expect(
            !ModelQualityScore.isEstimate([measured, estimated]),
            "one measured figure is enough to stand behind the score"
        )
        try expect(
            ModelQualityScore.isEstimate([estimated, estimated]),
            "all-estimated measurements make an estimated score"
        )
    }
}
