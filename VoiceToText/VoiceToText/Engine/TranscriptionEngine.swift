import Foundation

typealias PrepareProgress = @Sendable (_ fraction: Double, _ message: String) -> Void

protocol TranscriptionEngine: AnyObject, Sendable {
    var modelId: String { get }
    var isReady: Bool { get async }
    func prepare(progress: PrepareProgress?) async throws
    /// `contextPrompt` is the tail of the already-committed transcript, used by
    /// engines that benefit from rolling context (e.g. Whisper) to keep
    /// punctuation and proper-noun consistency across chunk boundaries.
    func transcribe(samples: [Float], contextPrompt: String?) async throws -> String
}

extension TranscriptionEngine {
    func transcribe(samples: [Float]) async throws -> String {
        try await transcribe(samples: samples, contextPrompt: nil)
    }
}

enum TranscriptionEngineError: LocalizedError {
    case notReady
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Transcription engine is not ready. Call prepare() first."
        case .modelLoadFailed(let reason):
            return "Model load failed: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
