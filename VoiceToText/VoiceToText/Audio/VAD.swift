import Foundation

/// Simple energy-based voice activity detector.
/// No external dependencies — pure arithmetic over 30 ms RMS frames.
struct EnergyVAD {
    /// Returns true when enough energy frames exceed the dBFS threshold.
    func isVoiced(_ samples: ArraySlice<Float>, sampleRate: Int) -> Bool {
        let frameLength = max(1, sampleRate * DictationConfig.vadFrameMs / 1_000)
        let threshold = DictationConfig.vadThresholdDBFS
        let requiredRatio = DictationConfig.vadVoicedRatio

        var totalFrames = 0
        var voicedFrames = 0
        var index = samples.startIndex

        while index < samples.endIndex {
            let end = samples.index(index, offsetBy: frameLength, limitedBy: samples.endIndex) ?? samples.endIndex
            let frame = samples[index..<end]
            let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count))
            let dbfs = rms > 0 ? 20 * log10(rms) : -Float.infinity
            if dbfs > threshold { voicedFrames += 1 }
            totalFrames += 1
            index = end
        }

        guard totalFrames > 0 else { return false }
        return Float(voicedFrames) / Float(totalFrames) >= requiredRatio
    }
}
