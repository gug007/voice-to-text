import Foundation

// 1st-order high-pass IIR biquad coefficients for 80 Hz at 16 kHz.
// H(z) = (1 - z^-1) / (1 - R*z^-1), R = exp(-2π·f/fs)
// Exact: R = exp(-2π·80/16000) ≈ 0.96908
private let kHPAlpha: Float = 0.96908   // pole
private let kDCAlpha: Float = 0.999     // EMA alpha for DC tracking
private let kAGCAlpha: Float = 0.9995   // EMA alpha for peak tracking
private let kAGCTarget: Float = 0.70    // ~-3 dBFS
private let kAGCMin: Float = 0.5
private let kAGCMax: Float = 8.0
private let kAGCEpsilon: Float = 1e-5

struct AudioPreprocessor {
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

    private mutating func applyAGC(_ buffer: inout [Float]) {
        for i in buffer.indices {
            let s = buffer[i]
            let absSample = s < 0 ? -s : s
            agcPeak = kAGCAlpha * agcPeak + (1 - kAGCAlpha) * absSample
            let rawGain = kAGCTarget / max(agcPeak, kAGCEpsilon)
            let gain = min(max(rawGain, kAGCMin), kAGCMax)
            buffer[i] = s * gain
        }
    }
}
