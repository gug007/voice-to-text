import AVFoundation
import Foundation

/// Transcribes a finished meeting recording. Loads the WAV off the main actor,
/// splits it into model-sized chunks (`AudioChunker`), transcribes each on the
/// active engine while carrying a little context across boundaries, and joins
/// the pieces. Reports progress as (completedChunks, totalChunks).
enum MeetingTranscriber {
    static func transcribe(
        url: URL,
        engine: TranscriptionEngine,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> String {
        let sampleRate = Int(AudioConfig.targetSampleRate)
        let samples = try await Task.detached(priority: .userInitiated) {
            try loadSamples(url: url)
        }.value

        // Engines that chunk internally (and carry their own cross-request
        // context or speaker numbering) must see the whole buffer — pre-chunking
        // here would reset that state at every cut. Hand them the full samples
        // and bridge their `@Sendable` progress callback to `onProgress`.
        if engine.chunksInternally {
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

        let chunks = AudioChunker.split(samples: samples, sampleRate: sampleRate)
        guard !chunks.isEmpty else { return "" }
        onProgress(0, chunks.count)

        var pieces: [String] = []
        for (index, chunk) in chunks.enumerated() {
            // Give Whisper-style engines the tail of the prior chunk so
            // punctuation and proper nouns stay consistent across the cut.
            let context = pieces.last.map { String($0.suffix(200)) }
            let raw = try await engine.transcribe(samples: chunk, contextPrompt: context, progress: nil)
            pieces.append(TranscriptPostProcessor.processPreservingLines(raw))
            onProgress(index + 1, chunks.count)
        }
        return MeetingTranscriptJoiner.join(pieces)
    }

    /// Decodes the recorded WAV into 16 kHz mono Float samples. Downmixes
    /// defensively if the file is ever multi-channel (ours is already mono).
    nonisolated static func loadSamples(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return [] }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { return [] }

        let count = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
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
