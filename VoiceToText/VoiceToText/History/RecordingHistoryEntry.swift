import Foundation

/// One saved dictation: the recorded audio (a WAV on disk) plus the transcript
/// it produced. Persisted as JSON in the history index; the audio lives beside
/// the index keyed by `audioFileName`.
///
/// `nonisolated` so its synthesized conformances (Equatable/Hashable/Codable)
/// stay usable from the nonisolated pruner, the off-main IO queue, and the test
/// harness — the module defaults to MainActor isolation otherwise.
nonisolated struct RecordingHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    /// The post-processed transcript shown to the user for this recording.
    let transcript: String
    /// File name (not a full path) of the WAV inside the history directory, so
    /// the store can move the directory without rewriting every entry.
    let audioFileName: String
    let durationSeconds: Double
    let sampleRate: Int
    /// Catalog id of the model that produced the transcript (e.g. "parakeet").
    /// Optional so older indexes without it still decode.
    let modelId: String?
    /// Human-readable model name captured at record time, kept verbatim so the
    /// row label stays correct even if the catalog entry is later renamed.
    let modelName: String?
    /// How the recording was made — `.dictation` (the hotkey flow) or
    /// `.meeting` (long background capture). Optional so indexes written before
    /// meetings existed still decode as dictations.
    let source: Source?

    /// `meeting` is the long mic+system-audio capture (shown to users as
    /// "Conversation"); the rawValue is kept stable for stored indexes.
    enum Source: String, Codable, Sendable {
        case dictation
        case meeting

        /// User-facing type label for the History badge.
        var displayName: String {
            switch self {
            case .dictation: return "Dictation"
            case .meeting: return "Conversation"
            }
        }

        var symbolName: String {
            switch self {
            case .dictation: return "mic.fill"
            case .meeting: return "person.2.wave.2.fill"
            }
        }
    }

    init(
        id: UUID,
        createdAt: Date,
        transcript: String,
        audioFileName: String,
        durationSeconds: Double,
        sampleRate: Int,
        modelId: String?,
        modelName: String?,
        source: Source? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.modelId = modelId
        self.modelName = modelName
        self.source = source
    }
}

/// Pure, side-effect-free retention policy for the history list. Kept separate
/// from the store so it can be unit-tested without touching the filesystem or
/// the main actor (see `Tests/RecordingHistoryHarness.swift`).
nonisolated enum RecordingHistoryPruner {
    struct Outcome: Equatable {
        /// The newest entries to retain, ordered newest-first.
        let kept: [RecordingHistoryEntry]
        /// The overflow entries to delete (audio files included).
        let removed: [RecordingHistoryEntry]
    }

    /// Retains the newest `maxCount` entries by `createdAt`, returning the rest
    /// as `removed`. Input order is irrelevant — entries are sorted newest-first
    /// here so the result is deterministic. `maxCount <= 0` removes everything.
    static func prune(_ entries: [RecordingHistoryEntry], maxCount: Int) -> Outcome {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            // Stable tie-break for equal timestamps so the policy is total.
            return lhs.id.uuidString > rhs.id.uuidString
        }
        guard maxCount > 0 else { return Outcome(kept: [], removed: sorted) }
        guard sorted.count > maxCount else { return Outcome(kept: sorted, removed: []) }
        return Outcome(
            kept: Array(sorted.prefix(maxCount)),
            removed: Array(sorted.suffix(from: maxCount))
        )
    }
}
