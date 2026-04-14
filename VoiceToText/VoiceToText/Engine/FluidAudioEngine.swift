import Foundation
import FluidAudio

actor FluidAudioEngine: TranscriptionEngine {
    let modelId: String
    private var manager: AsrManager?

    init(modelId: String = "parakeet-tdt-v3") {
        self.modelId = modelId
    }

    nonisolated var isReady: Bool {
        get async { await manager != nil }
    }

    func prepare(progress: PrepareProgress?) async throws {
        guard manager == nil else { return }
        do {
            progress?(0.0, "Starting…")

            let handler: DownloadUtils.ProgressHandler = { snapshot in
                let message: String
                switch snapshot.phase {
                case .listing:
                    message = "Listing files…"
                case .downloading(let completed, let total):
                    message = "Downloading \(completed)/\(total) files"
                case .compiling(let name):
                    message = "Compiling \(name)…"
                }
                progress?(snapshot.fractionCompleted, message)
            }

            let models = try await AsrModels.downloadAndLoad(progressHandler: handler)
            manager = AsrManager(models: models)

            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    func transcribe(samples: [Float], contextPrompt _: String?) async throws -> String {
        guard let manager else {
            throw TranscriptionEngineError.notReady
        }
        do {
            var decoderState = try TdtDecoderState()
            let result = try await manager.transcribe(samples, decoderState: &decoderState)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }
}
