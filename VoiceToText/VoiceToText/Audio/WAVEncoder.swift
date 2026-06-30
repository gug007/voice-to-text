import Foundation

/// Mono 16-bit little-endian PCM WAV format. Single-sources the on-disk byte
/// layout so the in-memory `encode` (HTTP uploads) and the incremental
/// `StreamingWAVWriter` (disk) stay in lockstep.
nonisolated enum WAVEncoder {
    /// Size of the RIFF/WAVE/fmt/data header that precedes the samples.
    static let headerSize = 44

    /// Full WAV blob: 44-byte header followed by 16-bit PCM samples. Used to
    /// upload buffered recordings to HTTP transcription APIs.
    static func encode(samples: [Float], sampleRate: Int) -> Data {
        var data = header(sampleRate: sampleRate, dataSize: samples.count * 2)
        data.append(int16LEData(from: samples))
        return data
    }

    /// The 44-byte header for a mono 16-bit PCM stream of `dataSize` audio bytes.
    static func header(sampleRate: Int, dataSize: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt16(bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bytesPerSample)
        let blockAlign = numChannels * bytesPerSample

        var data = Data()
        data.reserveCapacity(headerSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(uint32LE(UInt32(headerSize - 8 + dataSize)))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(uint32LE(16))                       // PCM fmt chunk size
        data.append(uint16LE(1))                        // AudioFormat = PCM
        data.append(uint16LE(numChannels))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(byteRate))
        data.append(uint16LE(blockAlign))
        data.append(uint16LE(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.append(uint32LE(UInt32(dataSize)))
        return data
    }

    /// Converts mono Float32 samples (range -1…1) to 16-bit little-endian PCM.
    /// macOS is little-endian, so the raw Int16 byte layout matches WAV's
    /// on-disk order without per-sample byte-swapping.
    static func int16LEData(from samples: [Float]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { raw in
            let int16Buffer = raw.baseAddress!.assumingMemoryBound(to: Int16.self)
            for index in 0..<samples.count {
                let clamped = max(-1.0, min(1.0, samples[index]))
                int16Buffer[index] = Int16((clamped * 32_767.0).rounded())
            }
        }
        return data
    }

    static func uint16LE(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Swift.withUnsafeBytes(of: &v) { Data($0) }
    }

    static func uint32LE(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Swift.withUnsafeBytes(of: &v) { Data($0) }
    }
}
