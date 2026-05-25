import Foundation

/// Splits a sample buffer into chunks that fit the OpenAI Transcriptions
/// limit (25 MB ≈ ~13 min of our WAV encoding), snapping each cut to the
/// quietest window in a search range so we don't slice through a word.
/// Acts as a safety net for unusually long recordings, not the common path.
nonisolated enum AudioChunker {
    /// 600 s ≈ 19 MB WAV — safely under 25 MB with slack for the silence
    /// search to extend a boundary by up to `silenceSearchWindowSeconds`.
    static let targetChunkSeconds: Double = 600

    /// Below this, the single-shot upload fits every API limit and avoids
    /// chunking's latency and context-fragmentation cost.
    static let minSplitThresholdSeconds: Double = 720

    static let silenceSearchWindowSeconds: Double = 15
    static let silenceWindowSeconds: Double = 0.3

    static func split(samples: [Float], sampleRate: Int) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        let sr = Double(sampleRate)
        guard Double(samples.count) / sr > minSplitThresholdSeconds else {
            return [samples]
        }

        let chunkSamples = Int(targetChunkSeconds * sr)
        let windowSamples = max(1, Int(silenceWindowSeconds * sr))
        let searchSamples = Int(silenceSearchWindowSeconds * sr)

        var chunks: [[Float]] = []
        var cursor = 0
        while cursor < samples.count {
            let targetEnd = cursor + chunkSamples
            if targetEnd >= samples.count {
                chunks.append(Array(samples[cursor..<samples.count]))
                break
            }
            let searchStart = max(cursor + windowSamples, targetEnd - searchSamples)
            let searchEnd = min(samples.count - windowSamples, targetEnd + searchSamples)
            let splitPoint = quietestWindowEnd(
                in: samples,
                start: searchStart,
                end: searchEnd,
                windowSize: windowSamples
            ) ?? targetEnd
            chunks.append(Array(samples[cursor..<splitPoint]))
            cursor = splitPoint
        }
        return chunks
    }

    private static func quietestWindowEnd(
        in samples: [Float],
        start: Int,
        end: Int,
        windowSize: Int
    ) -> Int? {
        guard start + windowSize <= end else { return nil }
        // Stride at 1/4 window so adjacent quiet regions are sampled finely
        // without recomputing fully overlapping RMS values.
        let stride = max(1, windowSize / 4)
        var bestRms: Float = .infinity
        var bestEnd: Int?
        var pos = start
        while pos + windowSize <= end {
            let rms = computeRMS(samples: samples, start: pos, count: windowSize)
            if rms < bestRms {
                bestRms = rms
                bestEnd = pos + windowSize
            }
            pos += stride
        }
        return bestEnd
    }

    private static func computeRMS(samples: [Float], start: Int, count: Int) -> Float {
        var sumSquares: Float = 0
        for i in start..<(start + count) {
            let s = samples[i]
            sumSquares += s * s
        }
        return (sumSquares / Float(count)).squareRoot()
    }
}
