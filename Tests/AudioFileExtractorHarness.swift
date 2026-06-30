import AVFoundation
import Foundation

// Self-contained runtime harness for `AudioFileExtractor`. Synthesizes a stereo
// 44.1 kHz WAV in code (no ffmpeg / external media), extracts it, and asserts the
// output is 16 kHz mono 16-bit PCM with the right duration and real (non-silent)
// signal — exercising the reader's resample + downmix + the WAV writer. Also
// checks the failure paths (missing file, garbage bytes) throw rather than crash.
//
// Run via Tests/run-hotkey-harnesses.sh.

/// `@unchecked Sendable` box so the `@Sendable` progress closure can record into
/// it without a capture-mutation warning.
private final class ProgressBox: @unchecked Sendable {
    var value = -1.0
}

@main
struct AudioFileExtractorHarness {
    static func main() async {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if condition { print("  ok: \(message)") }
            else { print("  FAIL: \(message)"); failures += 1 }
        }

        let tmp = FileManager.default.temporaryDirectory
        let src = tmp.appendingPathComponent("vtt-extract-src-\(UUID().uuidString).wav")
        let dst = tmp.appendingPathComponent("vtt-extract-dst-\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        // 2 s, 44.1 kHz, stereo, 440 Hz sine.
        writeStereoSineWAV(to: src, sampleRate: 44_100, seconds: 2, frequency: 440)

        print("extract stereo 44.1k -> mono 16k:")
        do {
            let progress = ProgressBox()
            try await AudioFileExtractor.extractToWAV(source: src, destination: dst,
                                                      onProgress: { progress.value = $0 })
            let header = readHeader(dst)
            check(header.sampleRate == 16_000, "output sampleRate is 16000 (got \(header.sampleRate))")
            check(header.channels == 1, "output is mono (got \(header.channels) ch)")
            check(header.bits == 16, "output is 16-bit (got \(header.bits))")
            let duration = Double(header.dataBytes / 2) / 16_000.0
            check(abs(duration - 2.0) < 0.3, "duration ~2s (got \(String(format: "%.2f", duration)))")
            check(rms(dst) > 0.01, "output has real signal (not silence)")
            check(progress.value >= 0.0, "progress was reported")
        } catch {
            check(false, "extraction threw: \(error)")
        }

        print("missing file throws (no crash):")
        do {
            let missing = tmp.appendingPathComponent("vtt-missing-\(UUID().uuidString).mov")
            try await AudioFileExtractor.extractToWAV(source: missing, destination: dst)
            check(false, "expected a throw for a missing file")
        } catch {
            check(true, "threw \(type(of: error))")
        }

        print("garbage file throws (no crash):")
        let junk = tmp.appendingPathComponent("vtt-junk-\(UUID().uuidString).mp4")
        let junkBytes = Data(repeating: 0x7A, count: 8_192)
        try? junkBytes.write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        do {
            try await AudioFileExtractor.extractToWAV(source: junk, destination: dst)
            check(false, "expected a throw for a non-media file")
        } catch {
            check(true, "threw \(type(of: error))")
        }

        if failures == 0 {
            print("AudioFileExtractorHarness: ALL PASSED")
        } else {
            print("AudioFileExtractorHarness: \(failures) FAILURE(S)")
            exit(1)
        }
    }

    // MARK: - Helpers

    /// Writes a valid interleaved 16-bit PCM stereo WAV of a sine tone.
    private static func writeStereoSineWAV(to url: URL, sampleRate: Int, seconds: Int, frequency: Double) {
        let channels = 2
        let frames = sampleRate * seconds
        let dataBytes = frames * channels * 2

        var data = Data()
        func appendU32(_ v: UInt32) { var le = v.littleEndian; data.append(Swift.withUnsafeBytes(of: &le) { Data($0) }) }
        func appendU16(_ v: UInt16) { var le = v.littleEndian; data.append(Swift.withUnsafeBytes(of: &le) { Data($0) }) }

        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1) // PCM
        appendU16(UInt16(channels))
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * channels * 2)) // byte rate
        appendU16(UInt16(channels * 2))              // block align
        appendU16(16)                                // bits
        data.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataBytes))

        var samples = Data(count: dataBytes)
        samples.withUnsafeMutableBytes { raw in
            let buffer = raw.baseAddress!.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frames {
                let t = Double(frame) / Double(sampleRate)
                let value = Int16(sin(2 * Double.pi * frequency * t) * 30_000)
                buffer[frame * channels] = value
                buffer[frame * channels + 1] = value
            }
        }
        data.append(samples)
        try? data.write(to: url)
    }

    private static func readHeader(_ url: URL) -> (sampleRate: Int, channels: Int, bits: Int, dataBytes: Int) {
        guard let data = try? Data(contentsOf: url), data.count >= 44 else { return (0, 0, 0, 0) }
        func u16(_ o: Int) -> Int { Int(data[o]) | (Int(data[o + 1]) << 8) }
        func u32(_ o: Int) -> Int { Int(data[o]) | (Int(data[o + 1]) << 8) | (Int(data[o + 2]) << 16) | (Int(data[o + 3]) << 24) }
        return (u32(24), u16(22), u16(34), u32(40))
    }

    private static func rms(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil, let channel = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        var sum = 0.0
        for i in 0..<count { let s = Double(channel[0][i]); sum += s * s }
        return (sum / Double(max(1, count))).squareRoot()
    }
}
