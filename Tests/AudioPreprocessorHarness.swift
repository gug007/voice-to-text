import Foundation

struct AudioPreprocessorHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw AudioPreprocessorHarnessFailure(description: message)
    }
}

private let sampleRate = 16_000
private let target: Float = 0.70
/// Float rounding in the gain multiply, nothing more.
private let tolerance: Float = 1e-4

/// Deterministic generator, so a failure reproduces.
private struct Generator {
    var state: UInt64

    mutating func unit() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24)
    }

    mutating func signed() -> Float { unit() * 2 - 1 }
}

private func silence(seconds: Double, floor: Float = 0, generator: inout Generator) -> [Float] {
    (0..<Int(seconds * Double(sampleRate))).map { _ in generator.signed() * floor }
}

private func tone(seconds: Double, frequency: Float, amplitude: Float) -> [Float] {
    (0..<Int(seconds * Double(sampleRate))).map {
        amplitude * sin(2 * .pi * frequency * Float($0) / Float(sampleRate))
    }
}

/// A syllable: a few harmonics plus breath noise under a rise-and-fall
/// envelope, peaking near `amplitude`.
private func syllable(seconds: Double, amplitude: Float, generator: inout Generator) -> [Float] {
    let count = Int(seconds * Double(sampleRate))
    let pitch = 90 + generator.unit() * 200
    return (0..<count).map { n in
        let t = Float(n) / Float(sampleRate)
        let envelope = sin(.pi * Float(n) / Float(count))
        let voiced = 0.6 * sin(2 * .pi * pitch * t) + 0.25 * sin(2 * .pi * 2 * pitch * t) + 0.1 * sin(2 * .pi * 3 * pitch * t)
        let value = amplitude * envelope * (voiced + 0.05 * generator.signed())
        return min(max(value, -1), 1)
    }
}

/// Bursts of syllables at random loudness up to full scale, with pauses
/// between phrases.
private func speechLike(seconds: Double, generator: inout Generator) -> [Float] {
    var samples: [Float] = []
    let total = Int(seconds * Double(sampleRate))
    while samples.count < total {
        let loudness = 0.02 + generator.unit() * 0.98
        for _ in 0..<(1 + Int(generator.unit() * 6)) {
            samples += syllable(seconds: 0.08 + Double(generator.unit()) * 0.25, amplitude: loudness, generator: &generator)
        }
        samples += silence(seconds: Double(generator.unit()) * 1.5, floor: 0.001, generator: &generator)
    }
    return samples
}

/// Runs `input` through one preprocessor in tap-sized buffers, the way
/// `AudioRecorder.handle` feeds it.
private func processed(_ input: [Float], buffer: Int = 1_600, preprocessor: inout AudioPreprocessor) -> [Float] {
    var output: [Float] = []
    output.reserveCapacity(input.count)
    var start = 0
    while start < input.count {
        var piece = Array(input[start..<min(start + buffer, input.count)])
        preprocessor.process(&piece)
        output += piece
        start += buffer
    }
    return output
}

private func processed(_ input: [Float], buffer: Int = 1_600) -> [Float] {
    var preprocessor = AudioPreprocessor()
    return processed(input, buffer: buffer, preprocessor: &preprocessor)
}

private func peak(_ samples: ArraySlice<Float>) -> Float {
    samples.reduce(0) { max($0, abs($1)) }
}

private func seconds(_ value: Double) -> Int { Int(value * Double(sampleRate)) }

@main
struct AudioPreprocessorHarness {
    static func main() throws {
        try speechNeverExceedsTarget()
        try onsetAfterSilenceDoesNotOvershoot()
        try quietSignalStillGetsFullGain()
        try steadySignalReachesTarget()
        try bufferSizeDoesNotChangeOutput()
        try resetClearsState()
        try clampHoldsFullScale()
        print("Audio preprocessor harness passed")
    }

    private static func speechNeverExceedsTarget() throws {
        for seed in 1...20 {
            var generator = Generator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15)
            let input = speechLike(seconds: 20, generator: &generator)
            let output = processed(input, buffer: 256 + Int(generator.unit() * 4_000))
            let loudest = peak(output[...])
            try expect(loudest <= target + tolerance,
                       "speech within full scale never leaves above the target (seed \(seed): peak \(loudest))")
        }

        var generator = Generator(state: 7)
        let noise = (0..<seconds(5)).map { _ in generator.signed() }
        try expect(peak(processed(noise)[...]) <= target + tolerance, "nor does full-scale noise")
    }

    private static func onsetAfterSilenceDoesNotOvershoot() throws {
        for floor in [Float(0), 0.0005, 0.005] {
            var generator = Generator(state: 11)
            let pause = silence(seconds: 3, floor: floor, generator: &generator)
            let input = pause + syllable(seconds: 0.3, amplitude: 0.9, generator: &generator)
                + tone(seconds: 0.5, frequency: 220, amplitude: 0.5)
            let output = processed(input)
            let onset = output[pause.count...]
            try expect(peak(onset) <= target + tolerance,
                       "a loud onset after 3 s at a \(floor) noise floor stays under the target (peak \(peak(onset)))")
            try expect(peak(onset.prefix(seconds(0.15))) >= 0.6,
                       "and still comes through at full level, not ducked")
            try expect(peak(output[..<pause.count]) <= floor * 8 * 1.2 + tolerance,
                       "the pause itself is lifted by no more than the 8× cap")
        }
    }

    private static func quietSignalStillGetsFullGain() throws {
        let input = tone(seconds: 3, frequency: 1_000, amplitude: 0.01)
        let output = processed(input)
        let gain = peak(output[seconds(2)...]) / peak(input[seconds(2)...])
        try expect(abs(gain - 8) < 0.1, "a steady quiet signal is lifted by the full 8× (got \(gain)×)")
    }

    private static func steadySignalReachesTarget() throws {
        let output = processed(tone(seconds: 3, frequency: 1_000, amplitude: 0.2))
        let level = peak(output[seconds(2)...])
        try expect(abs(level - target) < 0.01, "a steady mid-level signal peaks at the target (got \(level))")

        let loud = processed(tone(seconds: 3, frequency: 1_000, amplitude: 1))
        try expect(abs(peak(loud[seconds(2)...]) - target) < 0.01, "a full-scale one is brought down to it")
    }

    private static func bufferSizeDoesNotChangeOutput() throws {
        var generator = Generator(state: 3)
        let input = speechLike(seconds: 5, generator: &generator)
        try expect(processed(input, buffer: 160) == processed(input, buffer: input.count),
                   "state carries across buffers: tap-sized pieces give the same samples as one pass")
    }

    private static func resetClearsState() throws {
        let loud = tone(seconds: 1, frequency: 300, amplitude: 0.9)
        let quiet = tone(seconds: 0.5, frequency: 1_000, amplitude: 0.01)
        let fresh = processed(quiet)

        var preprocessor = AudioPreprocessor()
        _ = processed(loud, preprocessor: &preprocessor)
        var carried = preprocessor
        try expect(processed(quiet, preprocessor: &carried) != fresh,
                   "without a reset the loud take's envelope still holds the gain down")

        preprocessor.reset()
        try expect(processed(quiet, preprocessor: &preprocessor) == fresh,
                   "after reset() the next take is processed as if by a new preprocessor")
    }

    private static func clampHoldsFullScale() throws {
        var samples: [Float] = [-50, -1.0001, -1, -0.5, 0, 0.7, 1, 1.5, 12]
        AudioPreprocessor.clampToFullScale(&samples)
        try expect(samples == [-1, -1, -1, -0.5, 0, 0.7, 1, 1, 1], "out-of-range samples are clamped, the rest untouched")
    }
}
