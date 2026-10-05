import Foundation
import Observation

/// Re-transcribes a saved recording's stored audio with a chosen model and
/// writes the new transcript back into History. One regeneration at a time; the
/// active id and chunk progress drive the inline UI on the recording row.
///
/// A recording saved without a transcript (a failed dictation) is the
/// replace-mode case: its placeholder is replaced outright and its status
/// cleared, rather than kept as an alternate beside the real text. When that
/// attempt fails too, the row's stored reason is replaced with this one, so
/// what it says is about the model the user just tried — not the one that
/// failed days ago.
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
    /// The model on this Mac being fetched before the active regeneration can
    /// start, or nil once it is here (or when nothing needed fetching). A
    /// first download runs for minutes, so the row reads the registry's
    /// progress for it rather than spin with nothing to show.
    private(set) var downloadingModelID: String?

    /// True while a regeneration is mid-flight — used to disable the menu on
    /// other rows so two can't run on the same engine at once.
    var isRunning: Bool { activeID != nil }

    private init() {}

    /// True while a conversation is recording, transcribing or importing.
    /// Conversations and regeneration share `ModelRegistry`'s background
    /// engines — one instance per model — and running both on one instance
    /// would race its internal state. Dictation has its own pool, so a
    /// dictation in progress doesn't block a regeneration.
    private static var otherTranscriptionActive: Bool {
        MeetingController.shared.isBusy
    }

    func dismissFailure() { failure = nil }

    func regenerate(entry: RecordingHistoryEntry, modelId: String) async {
        guard activeID == nil else { return }
        guard let descriptor = ModelCatalog.model(for: modelId) else { return }
        let store = RecordingHistoryStore.shared

        // The dictation that saved this row is still transcribing it; a second
        // request would race it for the same transcript.
        guard !store.inFlightIDs.contains(entry.id) else {
            failure = (entry.id, "This recording is still being transcribed.")
            return
        }

        // The dictation card (or a failed Resume's banner) holds this row for
        // its Retry; both running would bill twice for one take and race to
        // fill the row, and the card would go on offering a Retry for audio
        // already transcribed here.
        guard DictationController.shared.heldTakeRowID != entry.id else {
            failure = (entry.id, "The dictation card is holding this recording. Use the card, or close it first.")
            return
        }

        guard !Self.otherTranscriptionActive else {
            failure = (entry.id, "A conversation is in progress. Try again once it finishes.")
            return
        }

        let url = store.audioURL(for: entry)
        guard FileManager.default.fileExists(atPath: url.path) else {
            failure = (entry.id, "The audio for this recording is missing.")
            return
        }

        failure = nil
        transcribedChunks = 0
        totalChunks = 0
        activeID = entry.id
        defer { activeID = nil }

        // Asked of the disk, as the model menu asks it: a model whose folder
        // a download is still filling isn't here yet either.
        let registry = ModelRegistry.shared
        let needsDownload = !descriptor.isCloud
            && !ModelStorage.isDownloaded(descriptor, readiness: registry.readiness(for: modelId))
        if needsDownload { downloadingModelID = modelId }
        let prepared = await registry.prepareBackgroundEngine(id: modelId)
        downloadingModelID = nil
        guard let engine = prepared else {
            failure = (entry.id, Self.notReadyMessage(for: descriptor, afterDownload: needsDownload))
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
            // The provider answered, so its balance isn't empty — even when
            // what it heard was silence.
            CloudCreditStatus.shared.noteSuccess(provider: descriptor.backend.cloudProvider)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                failure = (entry.id, "No speech was detected with \(descriptor.displayName).")
                return
            }
            // Decided by the store's current copy, not this snapshot of it: a
            // retry from the dictation card may have filled the transcript
            // in while this one ran, and then this is an ordinary regeneration.
            if !store.resolveFailedTranscript(id: entry.id, transcript: trimmed, model: descriptor) {
                store.addRegeneratedTranscript(id: entry.id, transcript: trimmed, model: descriptor)
            }
        } catch {
            recordFailure(error, entry: entry, model: descriptor)
        }
    }

    /// A row that already has a transcript keeps it and only hears why the
    /// regeneration didn't land. A row still waiting for one gets its stored
    /// reason replaced — classified the way the dictation card classifies a
    /// failure, so an empty balance says so rather than echoing the
    /// provider's raw error. "Waiting for one" includes an older build's
    /// conversation saved with only a placeholder and no status
    /// (`transcriptIsPlaceholder`), which then gets the reason it never had.
    /// `updateFailedStatus` is a no-op when the transcript was filled in
    /// meanwhile, which is then the case it tells.
    ///
    /// An empty balance also flags the provider, as a refused dictation does,
    /// so every row it failed leads with the model on this Mac.
    private func recordFailure(_ error: Error, entry: RecordingHistoryEntry, model: ModelDescriptor) {
        let classified = TranscriptionFailure.classify(error)
        CloudCreditStatus.shared.noteFailure(classified, provider: model.backend.cloudProvider)
        let provider = model.backend.cloudProvider?.displayName
        let status = RecordingHistoryEntry.Status(
            kind: .failed,
            message: classified.message(provider: provider, fallback: Self.statusFallback(for: error))
        )
        if entry.transcriptIsPlaceholder, RecordingHistoryStore.shared.updateFailedStatus(id: entry.id, status: status) {
            let detail = classified.message(provider: provider, fallback: Self.detail(of: error))
            failure = (entry.id, "Couldn't transcribe: \(detail)")
        } else {
            failure = (entry.id, "Couldn't regenerate: \(error.localizedDescription)")
        }
    }

    /// The reason stored on the row, in the shape a failed dictation stores
    /// it, so a row reads the same whichever path last failed it.
    private static func statusFallback(for error: Error) -> String {
        if error is TranscriptionEngineError || error is CloudTranscriptionError {
            return error.localizedDescription
        }
        return "Transcription failed: \(error.localizedDescription)"
    }

    /// The engine's message without its "Transcription failed: " lead, which
    /// would only repeat the note's own "Couldn't transcribe".
    private static func detail(of error: Error) -> String {
        let description = error.localizedDescription
        let lead = "Transcription failed: "
        return description.hasPrefix(lead) ? String(description.dropFirst(lead.count)) : description
    }

    /// A cloud model is ready exactly when its provider has a key, so a
    /// missing key is named as one. A model this regeneration had to fetch
    /// failed in its download if it still isn't on disk, and otherwise in
    /// the load after it — told apart by asking the disk again, so a load
    /// that failed doesn't blame the connection. Either says why when the
    /// registry knows.
    private static func notReadyMessage(for model: ModelDescriptor, afterDownload: Bool) -> String {
        if let provider = model.backend.cloudProvider, !provider.hasAPIKey {
            return "Add your \(provider.displayName) API key in Cloud to use \(model.displayName)."
        }
        if afterDownload {
            let readiness = ModelRegistry.shared.readiness(for: model.id)
            var reason: String?
            if case .failed(let message) = readiness { reason = message }
            guard ModelStorage.isDownloaded(model, readiness: readiness) else {
                return FailureCardCopy.downloadFailed(modelName: model.displayName, reason: reason)
            }
            return FailureCardCopy.loadFailed(modelName: model.displayName, reason: reason)
        }
        return "\(model.displayName) isn't ready. Check the model in Models, or add an API key in Cloud."
    }
}
