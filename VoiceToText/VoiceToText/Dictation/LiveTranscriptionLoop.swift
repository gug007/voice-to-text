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

    private let vad = EnergyVAD()

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
            let overlap = DictationConfig.overlapSamples

            while !Task.isCancelled {
                try? await Task.sleep(for: DictationConfig.liveTranscriptionInterval)
                guard isActive() else { return }

                iteration += 1
                LiveHUDPanel.shared.setElapsed(Date().timeIntervalSince(recordStart))

                let allSamples = sampleProvider()
                // Need at least one full chunk beyond the already-committed window.
                guard allSamples.count >= committedSampleIndex + chunkSize else { continue }

                // Window = overlap tail already committed + new chunk.
                let windowStart = max(0, committedSampleIndex - overlap)
                let windowEnd   = min(allSamples.count, committedSampleIndex + chunkSize)
                let window = Array(allSamples[windowStart..<windowEnd])

                let sampleRate = Int(AudioConfig.targetSampleRate)
                guard vad.isVoiced(window[...], sampleRate: sampleRate) else {
                    AppLog.dictation.info("Live iter \(iteration): VAD silent, skipping chunk (committedIdx=\(self.committedSampleIndex))")
                    // Advance commit index so we don't stall forever on silence.
                    committedSampleIndex = windowEnd - overlap
                    continue
                }

                guard let engine = await ModelRegistry.shared.prepareModel(id: modelId) else { continue }

                let start = Date()
                do {
                    let chunkText = try await engine.transcribe(samples: window)
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
}
