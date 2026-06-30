import Foundation
import Observation

/// Re-transcribes a saved recording's stored audio with a chosen model and
/// writes the new transcript back into History. One regeneration at a time; the
/// active id and chunk progress drive the inline UI on the recording row.
@Observable
@MainActor
final class TranscriptRegenerator {
    static let shared = TranscriptRegenerator()

    /// The entry currently being re-transcribed, or nil when idle.
    private(set) var activeID: UUID?
    private(set) var transcribedChunks = 0
    private(set) var totalChunks = 0
    /// The last failure, tagged with the entry it belongs to, for an inline note.
    private(set) var failure: (id: UUID, message: String)?

    /// True while a regeneration is mid-flight — used to disable the menu on
    /// other rows so two can't run on the same engine at once.
    var isRunning: Bool { activeID != nil }

    private init() {}

    /// True while a dictation or meeting is using the (shared, per-model) engine.
    private static var otherTranscriptionActive: Bool {
        if MeetingController.shared.isBusy { return true }
        switch DictationController.shared.state {
        case .preparing, .recording, .transcribing: return true
        case .idle, .reviewing, .error: return false
        }
    }

    func dismissFailure() { failure = nil }

    func regenerate(entry: RecordingHistoryEntry, modelId: String) async {
        guard activeID == nil else { return }
        guard let descriptor = ModelCatalog.model(for: modelId) else { return }

        // Dictation and meeting transcription share the same cached engine
        // instance per model id; running a regeneration on top of one would race
        // the engine's internal state. Refuse until the other flow finishes.
        guard !Self.otherTranscriptionActive else {
            failure = (entry.id, "Another transcription is in progress. Try again once it finishes.")
            return
        }

        let url = RecordingHistoryStore.shared.audioURL(for: entry)
        guard FileManager.default.fileExists(atPath: url.path) else {
            failure = (entry.id, "The audio for this recording is missing.")
            return
        }

        failure = nil
        transcribedChunks = 0
        totalChunks = 0
        activeID = entry.id
        defer { activeID = nil }

        guard let engine = await ModelRegistry.shared.prepareModel(id: modelId) else {
            failure = (entry.id, "\(descriptor.displayName) isn't ready. Check the model in Models, or add an API key in Cloud.")
            return
        }

        do {
            let text = try await MeetingTranscriber.transcribe(
                url: url,
                engine: engine,
                onProgress: { [weak self] done, total in
                    self?.transcribedChunks = done
                    self?.totalChunks = total
                }
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                failure = (entry.id, "No speech was detected with \(descriptor.displayName).")
                return
            }
            RecordingHistoryStore.shared.updateTranscript(id: entry.id, transcript: trimmed, model: descriptor)
        } catch {
            failure = (entry.id, "Couldn't regenerate: \(error.localizedDescription)")
        }
    }
}
