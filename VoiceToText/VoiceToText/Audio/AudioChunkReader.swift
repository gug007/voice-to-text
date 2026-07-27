import AVFoundation
import Foundation

/// Streams a recorded WAV off disk in transcription-sized chunks, cutting at
/// the same quiet points `AudioChunker` picks for an in-memory buffer.
///
/// The difference is where the audio lives. `AudioChunker.split` needs the
/// whole recording as `[Float]` **and** allocates a second copy for the chunks
/// — at 16 kHz mono Float32 that's ~230 MB per hour, twice, so a long
/// conversation's peak memory scaled straight with its length (a three-hour
/// meeting reached well over a gigabyte before the model was even consulted,
/// which rather defeated `MeetingRecorder` streaming it to disk in the first
/// place). Here only the current chunk and its search tail are ever resident,
/// so peak is flat no matter how long the recording runs.
///
/// `@unchecked Sendable` in the `AudioRecorder` style: it's driven from one
/// task at a time (each `next()` is awaited before the following call), and it
/// exists to be hopped onto a background executor via `Task.detached`.
nonisolated final class AudioChunkReader: @unchecked Sendable {
    let sampleRate: Int
    let totalFrames: Int

    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let chunkFrames: Int
    private let searchFrames: Int
    private let silenceWindowFrames: Int
    /// False for recordings short enough that `AudioChunker` would hand back a
    /// single buffer — chunking them would only fragment the transcript.
    private let splitsIntoChunks: Bool
    /// Frames already handed out.
    private var cursor = 0

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
        totalFrames = Int(file.length)

        let rate = format.sampleRate
        guard rate > 0 else { throw AudioChunkReaderError.unreadable }
        sampleRate = Int(rate.rounded())

        chunkFrames = Int(AudioChunker.targetChunkSeconds * rate)
        searchFrames = Int(AudioChunker.silenceSearchWindowSeconds * rate)
        silenceWindowFrames = max(1, Int(AudioChunker.silenceWindowSeconds * rate))
        splitsIntoChunks = Double(totalFrames) / rate > AudioChunker.minSplitThresholdSeconds
    }

    /// How many chunks `next()` will produce, near enough to drive a progress
    /// readout. Cuts drift by up to `silenceSearchWindowSeconds` either way, so
    /// the true count can come in one under — callers should report the final
    /// tally once the loop ends rather than trusting this to the last unit.
    var estimatedChunkCount: Int {
        guard splitsIntoChunks else { return totalFrames > 0 ? 1 : 0 }
        let seconds = Double(totalFrames) / Double(sampleRate)
        return max(1, Int((seconds / AudioChunker.targetChunkSeconds).rounded(.up)))
    }

    /// The next chunk of mono samples, or nil once the file is exhausted.
    func next() throws -> [Float]? {
        guard cursor < totalFrames else { return nil }

        let targetEnd = cursor + chunkFrames
        // Whole remainder fits (or we never split at all): take it as-is,
        // matching `AudioChunker.split`'s handling of the trailing piece.
        guard splitsIntoChunks, targetEnd < totalFrames else {
            let chunk = try read(from: cursor, count: totalFrames - cursor)
            cursor = totalFrames
            return chunk
        }

        // Read the chunk plus the tail the cut may reach into, then pick the
        // quietest window inside that tail — the same bounds `split` uses,
        // rebased onto this window.
        let start = cursor
        let windowEnd = min(totalFrames, targetEnd + searchFrames)
        let window = try read(from: start, count: windowEnd - start)

        let searchStart = max(start + silenceWindowFrames, targetEnd - searchFrames) - start
        let searchEnd = min(totalFrames - silenceWindowFrames, targetEnd + searchFrames) - start
        let relativeSplit = AudioChunker.quietestWindowEnd(
            in: window,
            start: searchStart,
            end: min(searchEnd, window.count),
            windowSize: silenceWindowFrames
        ) ?? (targetEnd - start)

        cursor = start + relativeSplit
        return Array(window[0..<relativeSplit])
    }

    // MARK: - Private

    private func read(from start: Int, count: Int) throws -> [Float] {
        guard count > 0 else { return [] }
        file.framePosition = AVAudioFramePosition(start)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(count)
        ) else {
            throw AudioChunkReaderError.unreadable
        }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
        return Self.monoSamples(from: buffer)
    }

    /// Our recordings are mono, but downmix defensively so an imported or
    /// hand-placed multi-channel file still transcribes (mirrors
    /// `MeetingTranscriber.loadSamples`).
    static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return [] }
        let channels = Int(buffer.format.channelCount)
        if channels <= 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: count))
        }
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channels {
            let pointer = channelData[channel]
            for index in 0..<count { mono[index] += pointer[index] }
        }
        let scale = 1.0 / Float(channels)
        for index in 0..<count { mono[index] *= scale }
        return mono
    }
}

enum AudioChunkReaderError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The recording couldn't be read for transcription."
        }
    }
}
