import Foundation

/// Where in a stretch of audio the energy VAD hears speech — used to tell a
/// transcription that came back empty over real speech from one that was
/// empty because the audio was.
///
/// `EnergyVAD.isVoiced` asks whether enough of a buffer is loud, which a long
/// buffer with a single short remark fails. So the audio is judged in short
/// windows, and the span runs from the first voiced window to the end of the
/// last one.
nonisolated enum SpeechEnergy {
    /// Short enough that one sentence fills enough of a window to count.
    static let windowSeconds: Double = 5

    /// Seconds from the start of `samples`; nil when no window is voiced.
    static func voicedSpan(
        in samples: [Float],
        sampleRate: Int,
        isVoiced: (ArraySlice<Float>) -> Bool
    ) -> ClosedRange<Double>? {
        guard sampleRate > 0, !samples.isEmpty else { return nil }
        let windowLength = max(1, Int(windowSeconds * Double(sampleRate)))
        var first: Int?
        var lastEnd = 0
        var start = 0
        while start < samples.count {
            let end = min(start + windowLength, samples.count)
            if isVoiced(samples[start..<end]) {
                if first == nil { first = start }
                lastEnd = end
            }
            start = end
        }
        guard let first else { return nil }
        return Double(first) / Double(sampleRate)...Double(lastEnd) / Double(sampleRate)
    }

    /// `voicedSpan` judged by the app's `EnergyVAD` at its current tuning.
    static func voicedSpan(in samples: [Float], sampleRate: Int) -> ClosedRange<Double>? {
        let vad = EnergyVAD()
        return voicedSpan(in: samples, sampleRate: sampleRate) { vad.isVoiced($0, sampleRate: sampleRate) }
    }
}
