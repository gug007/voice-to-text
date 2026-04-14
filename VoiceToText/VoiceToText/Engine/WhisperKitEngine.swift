import Foundation
import WhisperKit

actor WhisperKitEngine: TranscriptionEngine {
    let modelId: String
    private var pipe: WhisperKit?

    init(modelId: String) {
        self.modelId = modelId
    }

    nonisolated var isReady: Bool {
        get async { await pipe != nil }
    }

    func prepare(progress: PrepareProgress?) async throws {
        guard pipe == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: ModelStorage.whisperKitBaseURL,
                withIntermediateDirectories: true
            )

            progress?(0.0, "Connecting to HuggingFace…")

            let modelFolder = try await WhisperKit.download(
                variant: modelId,
                downloadBase: ModelStorage.whisperKitBaseURL,
                progressCallback: { foundationProgress in
                    let fraction = foundationProgress.fractionCompleted
                    let done = foundationProgress.completedUnitCount
                    let total = max(foundationProgress.totalUnitCount, 1)
                    let message = "Downloading \(done)/\(total) files"
                    progress?(fraction, message)
                }
            )

            progress?(0.95, "Loading model into memory…")

            let config = WhisperKitConfig(
                model: modelId,
                downloadBase: ModelStorage.whisperKitBaseURL,
                modelFolder: modelFolder.path,
                verbose: false,
                download: false
            )
            pipe = try await WhisperKit(config)

            progress?(1.0, "Ready")
        } catch {
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let pipe else {
            throw TranscriptionEngineError.notReady
        }
        do {
            let results = try await pipe.transcribe(audioArray: samples)
            return results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }
}
