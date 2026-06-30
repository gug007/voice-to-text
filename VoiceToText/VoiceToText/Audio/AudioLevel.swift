import Foundation

/// Maps an audio sample window's RMS to a perceptual 0…1 level for the live
/// mic / recording indicators. Noise-gated under -50 dBFS and mapped from -50
/// (silent) to -22 dBFS (normal speech) with a gamma curve that pushes
/// mid-range values up so the meter swings dramatically for typical speech.
/// Shared by `AudioRecorder` (dictation) and `MeetingRecorder` (conversations).
nonisolated enum AudioLevel {
    static func perceptual(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for s in samples { sumSquares += s * s }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        if db < -50 { return 0 }
        let norm = (Double(db) + 50) / 28
        return pow(max(0, min(1, norm)), 0.7)
    }
}
