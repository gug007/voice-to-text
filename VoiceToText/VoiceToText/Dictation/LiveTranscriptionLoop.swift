import Foundation
import OSLog

/// Streams audio in fixed chunks with 1-second overlap.
/// Maintains a growing merged transcript that DictationController can read
/// to avoid re-transcribing the whole buffer on stop.
@MainActor
final class LiveTranscriptionLoop {
    private var task: Task<Void, Never>?

    /// Number of samples already consumed into `committedTranscript`.
    private(set) var committedSampleIndex: Int = 0
    /// Merged transcript built up from all committed chunks.
    private(set) var committedTranscript: String = ""

    func start(
        modelId: String,
        recordStart: Date,
        sampleProvider: @escaping @MainActor () -> [Float],
        isActive: @escaping @MainActor () -> Bool
    ) {
        stop()
        committedSampleIndex = 0
        committedTranscript = ""

        task = Task { @MainActor in
            var iteration = 0
            let chunkSize = DictationConfig.chunkSamples
            let firstChunk = DictationConfig.firstChunkSamples
            let overlap = DictationConfig.overlapSamples

            while !Task.isCancelled {
                try? await Task.sleep(for: DictationConfig.liveTranscriptionInterval)
                guard isActive() else { return }

                iteration += 1
                LiveHUDPanel.shared.setElapsed(Date().timeIntervalSince(recordStart))

                let allSamples = sampleProvider()
                // First tick uses a small chunk for fast feedback; steady state uses the full chunkSize.
                let samplesNeeded = committedSampleIndex == 0
                    ? firstChunk
                    : committedSampleIndex + chunkSize
                guard allSamples.count >= samplesNeeded else { continue }

                // Window = overlap tail already committed + new chunk.
                let windowStart = max(0, committedSampleIndex - overlap)
                let windowEnd   = min(allSamples.count, committedSampleIndex + chunkSize)
                let window = Array(allSamples[windowStart..<windowEnd])

                if await !VoiceActivityGate.shared.isVoiced(window) {
                    AppLog.dictation.info("Live iter \(iteration): VAD silent, skipping chunk (committedIdx=\(self.committedSampleIndex))")
                    // Advance commit index so we don't stall forever on silence.
                    committedSampleIndex = windowEnd - overlap
                    continue
                }

                guard let engine = await ModelRegistry.shared.prepareModel(id: modelId) else { continue }

                let start = Date()
                do {
                    let context = Self.rollingContext(from: committedTranscript)
                    let chunkText = try await engine.transcribe(samples: window, contextPrompt: context)
                    let elapsed = Date().timeIntervalSince(start)
                    AppLog.dictation.info("Live iter \(iteration): \(window.count) samples → \"\(chunkText.prefix(60))\" in \(elapsed, format: .fixed(precision: 2))s")

                    guard isActive() else { return }
                    committedTranscript = TranscriptMerge.merge(
                        existing: committedTranscript,
                        newChunk: chunkText,
                        overlapWords: DictationConfig.overlapWords
                    )
                    committedSampleIndex = windowEnd - overlap
                    LiveHUDPanel.shared.update(text: committedTranscript)
                } catch {
                    AppLog.dictation.error("Live transcribe error: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Tail of the committed transcript, used as rolling context for the next chunk.
    /// Whisper caps prompt tokens around 224, so keep this short — roughly the last
    /// sentence or two is plenty for punctuation / proper-noun continuity.
    static func rollingContext(from transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let maxChars = 240
        if trimmed.count <= maxChars { return trimmed }
        let startIdx = trimmed.index(trimmed.endIndex, offsetBy: -maxChars)
        let slice = trimmed[startIdx...]
        // Start at the first word boundary so we don't feed a token mid-word.
        if let space = slice.firstIndex(of: " ") {
            return String(slice[slice.index(after: space)...])
        }
        return String(slice)
    }
}
