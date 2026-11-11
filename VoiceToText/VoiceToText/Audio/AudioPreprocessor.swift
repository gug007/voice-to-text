import Foundation

// 1st-order high-pass IIR biquad coefficients for 80 Hz at 16 kHz.
// H(z) = (1 - z^-1) / (1 - R*z^-1), R = exp(-2π·f/fs)
// Exact: R = exp(-2π·80/16000) ≈ 0.96908
nonisolated private let kHPAlpha: Float = 0.96908   // pole
nonisolated private let kDCAlpha: Float = 0.999     // EMA alpha for DC tracking
nonisolated private let kAGCRelease: Float = 0.99995 // peak decay per sample, ~1.25 s at 16 kHz
nonisolated private let kAGCTarget: Float = 0.70    // ~-3 dBFS
nonisolated private let kAGCMin: Float = 0.5
nonisolated private let kAGCMax: Float = 8.0
nonisolated private let kAGCEpsilon: Float = 1e-5

nonisolated struct AudioPreprocessor {
    static var isEnabled: Bool {
        if let val = UserDefaults.standard.object(forKey: "audio.preprocess.enabled") as? Bool {
            return val
        }
        return DictationConfig.enableAudioPreprocessing
    }

    // DC removal state
    private var dcMean: Float = 0
    // High-pass filter state (stores previous input and output)
    private var hpPrevIn: Float = 0
    private var hpPrevOut: Float = 0
    // AGC state
    private var agcPeak: Float = 0

    mutating func reset() {
        dcMean = 0
        hpPrevIn = 0
        hpPrevOut = 0
        agcPeak = 0
    }

    mutating func process(_ buffer: inout [Float]) {
        guard !buffer.isEmpty else { return }
        removeDC(&buffer)
        highPass(&buffer)
        applyAGC(&buffer)
    }

    /// Holds samples to [-1, 1]. The History WAV and cloud uploads clamp on
    /// their way to Int16, but local engines take these floats as they are,
    /// so an overshoot upstream reached the model and nothing else.
    static func clampToFullScale(_ buffer: inout [Float]) {
        for i in buffer.indices {
            buffer[i] = min(max(buffer[i], -1), 1)
        }
    }

    // MARK: - DSP stages

    private mutating func removeDC(_ buffer: inout [Float]) {
        for i in buffer.indices {
            dcMean = kDCAlpha * dcMean + (1 - kDCAlpha) * buffer[i]
            buffer[i] -= dcMean
        }
    }

    private mutating func highPass(_ buffer: inout [Float]) {
        // y[n] = R·y[n-1] + x[n] - x[n-1]
        for i in buffer.indices {
            let x = buffer[i]
            let y = kHPAlpha * hpPrevOut + x - hpPrevIn
            hpPrevIn = x
            hpPrevOut = y
            buffer[i] = y
        }
    }

    // Gain follows a peak envelope that jumps to each louder sample at once,
    // so a sample within full scale never leaves above the target. An
    // average of |x| lagged: through a pause the gain climbed to its cap, and
    // the next onset came through at 8×, far past full scale, which Whisper
    // heard as junk in the wrong language. The slow release keeps the gain
    // steady across a word.
    private mutating func applyAGC(_ buffer: inout [Float]) {
        for i in buffer.indices {
            let s = buffer[i]
            let absSample = s < 0 ? -s : s
            agcPeak = max(absSample, kAGCRelease * agcPeak)
            let rawGain = kAGCTarget / max(agcPeak, kAGCEpsilon)
            let gain = min(max(rawGain, kAGCMin), kAGCMax)
            buffer[i] = s * gain
        }
    }
}
