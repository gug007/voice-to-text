import Foundation

/// Encodes mono Float32 PCM samples (range -1…1) into a 16-bit little-endian
/// PCM WAV blob. Used to upload buffered recordings to HTTP transcription
/// APIs that expect a standard `.wav` file.
nonisolated enum WAVEncoder {
    static func encode(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bytesPerSample)
        let blockAlign = numChannels * UInt16(bytesPerSample)
        let dataSize = UInt32(samples.count * bytesPerSample)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.reserveCapacity(44 + samples.count * bytesPerSample)

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])              // "RIFF"
        data.appendLE(chunkSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])              // "WAVE"

        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])              // "fmt "
        data.appendLE(UInt32(16))                                       // PCM fmt chunk size
        data.appendLE(UInt16(1))                                        // AudioFormat = PCM
        data.appendLE(numChannels)
        data.appendLE(UInt32(sampleRate))
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)

        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])              // "data"
        data.appendLE(dataSize)

        // Convert Float32 [-1,1] → Int16 LE directly into `data` so we don't
        // hold a separate `[Int16]` buffer alongside the WAV blob. macOS is
        // little-endian, so the raw Int16 byte layout matches WAV's on-disk
        // order without per-sample byte-swapping.
        let byteCount = samples.count * bytesPerSample
        let payloadStart = data.count
        data.count += byteCount
        data.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.baseAddress!
                .advanced(by: payloadStart)
                .assumingMemoryBound(to: Int16.self)
            for index in 0..<samples.count {
                let clamped = max(-1.0, min(1.0, samples[index]))
                int16Buffer[index] = Int16((clamped * 32_767.0).rounded())
            }
        }
        return data
    }
}

nonisolated private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
