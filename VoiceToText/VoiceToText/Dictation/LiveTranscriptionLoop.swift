import Foundation
import OSLog

@MainActor
final class LiveTranscriptionLoop {
    private var task: Task<Void, Never>?

    func start(
        modelId: String,
        recordStart: Date,
        sampleProvider: @escaping @MainActor () -> [Float],
        isActive: @escaping @MainActor () -> Bool
    ) {
        stop()
        task = Task { @MainActor in
            var iteration = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: DictationConfig.liveTranscriptionInterval)
                guard isActive() else { return }

                iteration += 1
                LiveHUDPanel.shared.setElapsed(Date().timeIntervalSince(recordStart))

                let samples = sampleProvider()
                guard samples.count > DictationConfig.minLiveSamples else { continue }

                guard let engine = await ModelRegistry.shared.prepareModel(id: modelId) else { continue }

                let start = Date()
                do {
                    let text = try await engine.transcribe(samples: samples)
                    let elapsed = Date().timeIntervalSince(start)
                    AppLog.dictation.debug("Live iter \(iteration) transcribed in \(elapsed, format: .fixed(precision: 2))s, \(samples.count) samples")
                    guard isActive() else { return }
                    LiveHUDPanel.shared.update(text: text)
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
