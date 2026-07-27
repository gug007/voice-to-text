import AVFoundation
import Foundation

/// Verifies that streaming a recording off disk in chunks partitions it
/// exactly the way `AudioChunker.split` partitions the same audio in memory —
/// the invariant that lets `MeetingTranscriber` stop holding a whole
/// conversation (and a second copy of it) in RAM.

struct AudioChunkReaderHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw AudioChunkReaderHarnessFailure(description: message)
    }
}

private let sampleRate = 16_000

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vtt-chunk-\(UUID().uuidString).wav")
}

/// Speech-ish tone broken by a short silence every few seconds, so the split
/// search has real quiet windows to snap onto rather than picking arbitrarily
/// out of a flat signal.
private func makeSamples(seconds: Double) -> [Float] {
    let count = Int(seconds * Double(sampleRate))
    var samples = [Float](repeating: 0, count: count)
    for index in 0..<count {
        let t = Double(index) / Double(sampleRate)
        let inSilence = t.truncatingRemainder(dividingBy: 3.7) < 0.5
        samples[index] = inSilence ? 0 : Float(sin(2 * Double.pi * 220 * t)) * 0.6
    }
    return samples
}

private func writeWAV(_ samples: [Float], to url: URL) throws {
    try WAVEncoder.encode(samples: samples, sampleRate: sampleRate).write(to: url)
}

/// Whole-file decode, mirroring what the old in-memory path did — the
/// reference the streamed chunks are compared against.
private func decodeAll(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let frames = AVAudioFrameCount(file.length)
    guard frames > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
        return []
    }
    try file.read(into: buffer)
    return AudioChunkReader.monoSamples(from: buffer)
}

private func drain(_ reader: AudioChunkReader) throws -> [[Float]] {
    var chunks: [[Float]] = []
    while let chunk = try reader.next() {
        try expect(!chunk.isEmpty, "reader never yields an empty chunk")
        chunks.append(chunk)
    }
    return chunks
}

@main
struct AudioChunkReaderHarness {
    static func main() throws {
        try shortRecordingStaysOneChunk()
        try longRecordingMatchesInMemorySplit()
        try reportedChunkCountIsUsableAsProgressTotal()
        print("Audio chunk reader harness passed")
    }

    /// Under the split threshold the reader must behave like `split`, which
    /// hands back the buffer whole — chunking a short conversation would only
    /// fragment the transcript for nothing.
    private static func shortRecordingStaysOneChunk() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeWAV(makeSamples(seconds: 60), to: url)

        let chunks = try drain(AudioChunkReader(url: url))
        try expect(chunks.count == 1, "a 60s recording yields exactly one chunk, got \(chunks.count)")
        try expect(chunks[0].count == 60 * sampleRate, "the single chunk holds every frame")
    }

    /// The load-bearing test: same cuts, same order, nothing dropped or
    /// duplicated at the boundaries.
    private static func longRecordingMatchesInMemorySplit() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Past `minSplitThresholdSeconds` (720) by enough to force three cuts,
        // so an interior boundary — not just the trailing one — is exercised.
        try writeWAV(makeSamples(seconds: 1_500), to: url)

        let decoded = try decodeAll(url)
        let expected = AudioChunker.split(samples: decoded, sampleRate: sampleRate)
        let streamed = try drain(AudioChunkReader(url: url))

        try expect(
            streamed.count == expected.count,
            "chunk count matches split (streamed \(streamed.count), split \(expected.count))"
        )
        try expect(
            streamed.map(\.count) == expected.map(\.count),
            "cut points match split (streamed \(streamed.map(\.count)), split \(expected.map(\.count)))"
        )
        try expect(streamed.count >= 3, "the fixture actually splits more than once")

        let rejoined = streamed.flatMap { $0 }
        try expect(rejoined.count == decoded.count, "chunks cover the recording exactly once")
        try expect(rejoined == decoded, "chunks rejoin to the original samples in order")
    }

    /// The estimate drives the "n / total" readout, so it must never undershoot
    /// what the loop actually produces by more than the documented one chunk.
    private static func reportedChunkCountIsUsableAsProgressTotal() throws {
        for seconds in [30.0, 800.0, 1_210.0, 1_500.0] {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try writeWAV(makeSamples(seconds: seconds), to: url)

            let reader = try AudioChunkReader(url: url)
            let estimate = reader.estimatedChunkCount
            let actual = try drain(reader).count
            try expect(estimate >= 1, "estimate is at least one for \(seconds)s")
            try expect(
                abs(estimate - actual) <= 1,
                "estimate \(estimate) is within one of actual \(actual) for \(seconds)s"
            )
        }
    }
}
