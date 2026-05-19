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

        // Float32 [-1,1] -> Int16 little-endian. macOS is little-endian so a
        // raw memcpy of the Int16 buffer matches the on-disk byte order.
        var pcm = [Int16](repeating: 0, count: samples.count)
        for index in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[index]))
            pcm[index] = Int16((clamped * 32_767.0).rounded())
        }
        pcm.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            let byteCount = buffer.count * MemoryLayout<Int16>.size
            base.withMemoryRebound(to: UInt8.self, capacity: byteCount) { bytes in
                data.append(bytes, count: byteCount)
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
