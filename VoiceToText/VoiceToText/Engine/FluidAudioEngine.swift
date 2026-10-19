import CoreML
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

            // FluidAudio's download fills only 0–0.5 of its range; rescaled
            // so the card and History count it to 100% (`ParakeetProgress`).
            // "0/0 files" is FluidAudio finding the model already on disk —
            // the start of a load, not a download.
            let handler: DownloadUtils.ProgressHandler = { snapshot in
                let message: String
                var isLoading = false
                switch snapshot.phase {
                case .listing:
                    message = "Listing files…"
                case .downloading(_, let total) where total == 0:
                    message = "Loading model…"
                    isLoading = true
                case .downloading(let completed, let total):
                    message = "Downloading \(completed)/\(total) files"
                case .compiling(let name):
                    message = "Compiling \(name)…"
                    isLoading = true
                }
                progress?(ParakeetProgress.fraction(snapshot.fractionCompleted, isLoading: isLoading), message)
            }

            let models = try await AsrModels.downloadAndLoad(
                configuration: Self.modelConfiguration,
                progressHandler: handler
            )
            manager = AsrManager(models: models)

            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// FluidAudio's default places Parakeet on the Neural Engine, which an
    /// Intel Mac doesn't have, so there CoreML ran the whole model on the CPU
    /// alone — many times slower than the GPU it leaves idle. `nil` keeps
    /// FluidAudio's default on Apple Silicon.
    private static var modelConfiguration: MLModelConfiguration? {
        #if arch(x86_64)
        let configuration = AsrModels.defaultConfiguration()
        configuration.computeUnits = .cpuAndGPU
        return configuration
        #else
        return nil
        #endif
    }

    /// Parakeet has no prompt input; `contextPrompt` is ignored.
    nonisolated var usesContextPrompt: Bool { false }

    // Parakeet streams natively over long audio via its TDT decoder state,
    // so the external chunker — and `progress` — are unused.
    func transcribe(
        samples: [Float],
        contextPrompt _: String?,
        progress _: TranscribeProgress?
    ) async throws -> String {
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
