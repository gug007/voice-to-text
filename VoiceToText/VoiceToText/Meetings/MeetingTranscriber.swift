import AVFoundation
import Foundation

/// Transcribes a finished meeting recording off the main actor: walks it in
/// model-sized chunks, transcribes each on the active engine while carrying a
/// little context across boundaries, and joins the pieces. Reports progress as
/// (completedChunks, totalChunks).
///
/// Chunks are streamed off disk via `AudioChunkReader` rather than split out of
/// one big in-memory buffer, so peak memory is a chunk's worth regardless of
/// how long the conversation ran — see that type for the arithmetic.
enum MeetingTranscriber {
    static func transcribe(
        url: URL,
        engine: TranscriptionEngine,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> String {
        // Engines that chunk internally (and carry their own cross-request
        // context or speaker numbering) must see the whole buffer — pre-chunking
        // here would reset that state at every cut. Hand them the full samples
        // and bridge their `@Sendable` progress callback to `onProgress`.
        if engine.chunksInternally {
            let samples = try await Task.detached(priority: .userInitiated) {
                try loadSamples(url: url)
            }.value
            onProgress(0, 1)
            let raw = try await engine.transcribe(
                samples: samples,
                contextPrompt: nil,
                progress: { current, total in
                    Task { @MainActor in onProgress(current, total) }
                }
            )
            return TranscriptPostProcessor.processPreservingLines(raw)
        }

        let reader = try await Task.detached(priority: .userInitiated) {
            try AudioChunkReader(url: url)
        }.value
        let estimate = reader.estimatedChunkCount
        guard estimate > 0 else { return "" }
        onProgress(0, estimate)

        var pieces: [String] = []
        while true {
            // Detached on purpose: reading and scanning a chunk is synchronous
            // work, and under `NonisolatedNonsendingByDefault` an awaited
            // `nonisolated` call would run it on this caller's executor — the
            // main actor — and stall the UI.
            let chunk = try await Task.detached(priority: .userInitiated) {
                try reader.next()
            }.value
            guard let chunk, !chunk.isEmpty else { break }

            // Give Whisper-style engines the tail of the prior chunk so
            // punctuation and proper nouns stay consistent across the cut.
            let context = pieces.last.map { String($0.suffix(200)) }
            let raw = try await engine.transcribe(samples: chunk, contextPrompt: context, progress: nil)
            pieces.append(TranscriptPostProcessor.processPreservingLines(raw))
            // The estimate can land one over when a cut drifts early, so keep
            // the denominator honest rather than letting the bar stall short.
            onProgress(pieces.count, max(estimate, pieces.count))
        }
        guard !pieces.isEmpty else { return "" }
        onProgress(pieces.count, pieces.count)
        return MeetingTranscriptJoiner.join(pieces)
    }

    /// Decodes the recorded WAV into 16 kHz mono Float samples. Downmixes
    /// defensively if the file is ever multi-channel (ours is already mono).
    /// Read in blocks into the destination array: decoding the whole file into
    /// one `AVAudioPCMBuffer` and then copying it out held two full copies at
    /// once, doubling the peak for exactly as long as the copy took.
    nonisolated static func loadSamples(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = Int(file.length)
        guard total > 0 else { return [] }

        let blockFrames = min(total, Int(format.sampleRate) * 60)
        guard blockFrames > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(blockFrames)
              ) else { return [] }

        var samples: [Float] = []
        samples.reserveCapacity(total)
        while samples.count < total {
            let remaining = total - samples.count
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(blockFrames, remaining)))
            // A short read means the file ended early (truncated by a crash, say);
            // keep what decoded rather than spinning on an empty buffer.
            guard buffer.frameLength > 0 else { break }
            samples.append(contentsOf: AudioChunkReader.monoSamples(from: buffer))
        }
        return samples
    }
}
