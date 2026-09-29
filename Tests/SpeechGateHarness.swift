import Foundation

struct SpeechGateHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SpeechGateHarnessFailure(description: message)
    }
}

/// Silero's chunk: 4096 samples at 16 kHz.
private let chunkSeconds = 4096.0 / 16_000.0

/// The app's defaults: p ≥ 0.5 counts toward voiced time, 0.4 s passes, and
/// the old 25%-at-0.85 ratio still passes on its own.
private let sileroRule = SpeechGate.Rule(
    speechThreshold: 0.5,
    minVoicedSeconds: 0.4,
    ratioThreshold: 0.85,
    minVoicedRatio: 0.25
)

private let energyRule = SpeechGate.Rule(
    speechThreshold: -45,
    minVoicedSeconds: 0.4,
    ratioThreshold: -45,
    minVoicedRatio: 0.30
)

/// Probabilities for `seconds` of audio at a steady `p`.
private func chunks(_ seconds: Double, p: Float) -> [Float] {
    Array(repeating: p, count: Int((seconds / chunkSeconds).rounded()))
}

/// Deterministic noise in [-amplitude, amplitude].
private func noise(count: Int, amplitude: Float) -> [Float] {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Float(state >> 40) / Float(1 << 24)
        return (unit * 2 - 1) * amplitude
    }
}

private func tone(count: Int, amplitude: Float) -> [Float] {
    (0..<count).map { amplitude * sin(2 * .pi * 220 * Float($0) / 16_000) }
}

@main
struct SpeechGateHarness {
    static func main() throws {
        try sparseSpeechInALongTakePasses()
        try roomNoiseFails()
        try strayChunkFailsTwoChunksPass()
        try softSpeechBelowTheOldThresholdPasses()
        try oldRatioStillPassesAShortWord()
        try emptyTakeFails()
        try boundaryIsNotLostToRounding()
        try energyFallbackUsesTheSameRule()
        try frameLevelsMeasureDBFS()
        try sileroRetryBacksOffAndCaps()
        print("Speech gate harness passed")
    }

    /// The case the old gate got wrong: ten seconds of speech inside a
    /// minute-long take is 17% voiced — under the 25% ratio — and was thrown
    /// away as "No speech detected".
    private static func sparseSpeechInALongTakePasses() throws {
        let scores = chunks(25, p: 0.03) + chunks(10, p: 0.92) + chunks(25, p: 0.05)
        let verdict = SpeechGate.evaluate(scores: scores, unitSeconds: chunkSeconds, rule: sileroRule)
        try expect(verdict.voicedRatio < 0.25, "the fixture is below the old ratio (\(verdict.voicedRatio))")
        try expect(verdict.isVoiced, "10 s of speech in 60 s passes")
        try expect(abs(verdict.voicedSeconds - 10) < chunkSeconds, "voiced time is the speech (\(verdict.voicedSeconds))")
    }

    private static func roomNoiseFails() throws {
        let pattern: [Float] = [0.02, 0.11, 0.3, 0.07, 0.45, 0.18, 0.01, 0.38]
        let count = Int((50 / chunkSeconds).rounded())
        let scores = (0..<count).map { pattern[$0 % pattern.count] }
        let verdict = SpeechGate.evaluate(scores: scores, unitSeconds: chunkSeconds, rule: sileroRule)
        try expect(!verdict.isVoiced, "50 s of room noise under p 0.5 fails")
        try expect(verdict.voicedSeconds == 0, "no noise chunk counts as speech")
    }

    private static func strayChunkFailsTwoChunksPass() throws {
        let silence = chunks(8, p: 0.02)
        let one = SpeechGate.evaluate(
            scores: silence + [0.7] + silence,
            unitSeconds: chunkSeconds,
            rule: sileroRule
        )
        try expect(!one.isVoiced, "one 256 ms chunk (a click, a cough) fails")
        let two = SpeechGate.evaluate(
            scores: silence + [0.7, 0.9] + silence,
            unitSeconds: chunkSeconds,
            rule: sileroRule
        )
        try expect(two.isVoiced, "two chunks — about one short word — pass")
        let apart = SpeechGate.evaluate(
            scores: silence + [0.7] + silence + [0.6] + silence,
            unitSeconds: chunkSeconds,
            rule: sileroRule
        )
        try expect(apart.isVoiced, "voiced time adds up across pauses")
    }

    /// Soft or distant speech scores between Silero's 0.5 and FluidAudio's
    /// 0.85 — which the old gate counted as silence.
    private static func softSpeechBelowTheOldThresholdPasses() throws {
        let scores = chunks(4, p: 0.1) + chunks(1.5, p: 0.62) + chunks(4, p: 0.1)
        let verdict = SpeechGate.evaluate(scores: scores, unitSeconds: chunkSeconds, rule: sileroRule)
        try expect(verdict.voicedRatio == 0, "nothing clears 0.85")
        try expect(verdict.isVoiced, "1.5 s of soft speech passes")
    }

    /// Nothing the old gate passed may fail now: a sub-second take holding one
    /// clear chunk is 33% voiced, but only 0.26 s of speech.
    private static func oldRatioStillPassesAShortWord() throws {
        let verdict = SpeechGate.evaluate(
            scores: [0.1, 0.95, 0.2],
            unitSeconds: chunkSeconds,
            rule: sileroRule
        )
        try expect(verdict.voicedSeconds < 0.4, "under the voiced-time minimum")
        try expect(verdict.isVoiced, "the old ratio still passes it")
    }

    private static func emptyTakeFails() throws {
        let verdict = SpeechGate.evaluate(scores: [], unitSeconds: chunkSeconds, rule: sileroRule)
        try expect(!verdict.isVoiced, "no audio is no speech")
        try expect(verdict.voicedRatio == 0, "and no ratio, not NaN")
    }

    private static func boundaryIsNotLostToRounding() throws {
        var rule = energyRule
        rule.minVoicedSeconds = 0.3
        rule.minVoicedRatio = 1.1
        let scores: [Float] = Array(repeating: -20, count: 10) + Array(repeating: -70, count: 90)
        try expect(
            SpeechGate.evaluate(scores: scores, unitSeconds: 0.03, rule: rule).isVoiced,
            "ten 30 ms frames are exactly 0.3 s"
        )
        let short: [Float] = Array(repeating: -20, count: 9) + Array(repeating: -70, count: 91)
        try expect(
            !SpeechGate.evaluate(scores: short, unitSeconds: 0.03, rule: rule).isVoiced,
            "nine are not"
        )
    }

    /// The fallback while Silero isn't loaded: frame levels in dBFS through the
    /// same rule. A second of voice-level tone inside half a minute of quiet
    /// room noise passes; the noise alone doesn't.
    private static func energyFallbackUsesTheSameRule() throws {
        let frame = 16_000 * 30 / 1_000
        let quiet = noise(count: 16_000 * 15, amplitude: 0.001)
        let voice = tone(count: 16_000, amplitude: 0.1)
        let take = quiet + voice + quiet
        let levels = SpeechGate.frameLevels(take[...], frameLength: frame)
        let verdict = SpeechGate.evaluate(scores: levels, unitSeconds: 0.03, rule: energyRule)
        try expect(verdict.voicedRatio < 0.30, "the tone is under the old energy ratio")
        try expect(verdict.isVoiced, "1 s of tone in 31 s passes")

        let quietLevels = SpeechGate.frameLevels((quiet + quiet)[...], frameLength: frame)
        try expect(
            !SpeechGate.evaluate(scores: quietLevels, unitSeconds: 0.03, rule: energyRule).isVoiced,
            "room noise at -60 dBFS fails"
        )
    }

    private static func frameLevelsMeasureDBFS() throws {
        let levels = SpeechGate.frameLevels(tone(count: 4_800, amplitude: 0.1)[...], frameLength: 480)
        try expect(levels.count == 10, "one level per frame")
        // A sine's RMS is its amplitude over √2: 0.0707 ≈ -23 dBFS.
        try expect(levels.allSatisfy { abs($0 - -23.01) < 0.2 }, "a 0.1 sine reads -23 dBFS (\(levels))")

        let silent = SpeechGate.frameLevels(Array(repeating: Float(0), count: 960)[...], frameLength: 480)
        try expect(silent == [-.infinity, -.infinity], "digital silence is -infinity")

        let partial = SpeechGate.frameLevels(Array(repeating: Float(0.5), count: 500)[...], frameLength: 480)
        try expect(partial.count == 2, "a trailing partial frame is measured")
        try expect(abs(partial[1] - -6.02) < 0.01, "on the samples it has")
        try expect(SpeechGate.frameLevels([Float]()[...], frameLength: 480).isEmpty, "no samples, no frames")
    }

    private static func sileroRetryBacksOffAndCaps() throws {
        try expect(SpeechGate.sileroRetryDelay(afterFailures: 0) == 30, "defensive zero")
        try expect(SpeechGate.sileroRetryDelay(afterFailures: 1) == 30, "first retry after 30 s")
        try expect(SpeechGate.sileroRetryDelay(afterFailures: 2) == 60, "then doubling")
        try expect(SpeechGate.sileroRetryDelay(afterFailures: 5) == 480, "…to 8 minutes")
        try expect(SpeechGate.sileroRetryDelay(afterFailures: 6) == 600, "capped at 10 minutes")
        try expect(SpeechGate.sileroRetryDelay(afterFailures: 10_000) == 600, "without overflowing")
    }
}
