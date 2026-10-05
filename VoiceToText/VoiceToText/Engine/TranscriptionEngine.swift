import Foundation

typealias PrepareProgress = @Sendable (_ fraction: Double, _ message: String) -> Void

/// Per-chunk progress for engines that split the input into multiple
/// requests. `current` is 1-based.
typealias TranscribeProgress = @Sendable (_ current: Int, _ total: Int) -> Void

protocol TranscriptionEngine: AnyObject, Sendable {
    var modelId: String { get }
    var isReady: Bool { get async }
    func prepare(progress: PrepareProgress?) async throws
    /// `contextPrompt` is the tail of the already-committed transcript, used by
    /// engines that benefit from rolling context (e.g. Whisper) to keep
    /// punctuation and proper-noun consistency across chunk boundaries.
    /// `progress` is invoked once per internal chunk as it completes.
    func transcribe(
        samples: [Float],
        contextPrompt: String?,
        progress: TranscribeProgress?
    ) async throws -> String
    /// True when the engine splits an over-long input into model-sized requests
    /// itself (and carries its own cross-request context). Callers that would
    /// otherwise pre-chunk — like `MeetingTranscriber` — must hand such engines
    /// the whole buffer so per-request state (rolling prompt, speaker numbering)
    /// isn't reset at every local cut.
    var chunksInternally: Bool { get }
    /// Whether `contextPrompt` can change what the engine produces. A caller
    /// that would retry "without the prompt" must skip engines where it
    /// can't — the retry would only run the identical decode again.
    var usesContextPrompt: Bool { get }
}

extension TranscriptionEngine {
    var chunksInternally: Bool { false }
    var usesContextPrompt: Bool { true }

    func transcribe(samples: [Float]) async throws -> String {
        try await transcribe(samples: samples, contextPrompt: nil, progress: nil)
    }

    func transcribe(samples: [Float], contextPrompt: String?) async throws -> String {
        try await transcribe(samples: samples, contextPrompt: contextPrompt, progress: nil)
    }
}

/// A `TranscriptionEngine` that can also transcribe a *live* audio stream:
/// audio is pushed in as it is captured and partial/committed text comes back
/// before recording stops. Engines opt in by conforming; `DictationController`
/// detects conformance at runtime and drives the live path, falling back to the
/// buffered `transcribe(samples:)` for engines that don't (and for retries).
protocol StreamingTranscriptionEngine: TranscriptionEngine {
    /// Opens a streaming session. `onLiveText` is invoked on each update with
    /// the best current transcript (committed text plus the in-progress
    /// partial) for live display in the HUD. Throws if the session can't be
    /// established (e.g. auth/network), so the caller can fall back to buffered.
    func startStream(
        contextPrompt: String?,
        onLiveText: @escaping @Sendable (String) -> Void
    ) async throws

    /// Pushes a chunk of 16 kHz mono Float32 samples into the open session.
    /// Synchronous and `nonisolated` so it can be called directly from the
    /// audio thread in capture order — the engine buffers internally and sends
    /// in order, which avoids the frame reordering that per-chunk `Task`s would
    /// risk (actors give no FIFO guarantee across unstructured tasks).
    nonisolated func feedAudio(_ samples: [Float])

    /// Flushes buffered audio, closes the session, and returns the final
    /// committed transcript. Never returns part of a take: a session that
    /// lost text either re-sends the whole take itself or throws, and one the
    /// provider refused — a bad key, a rate limit, an empty balance — throws
    /// at once as a `CloudTranscriptionError` the failure card can name,
    /// since a re-send would only be refused again.
    func finishStream() async throws -> String

    /// Tears the session down without producing a result (e.g. user cancel).
    func cancelStream() async
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
