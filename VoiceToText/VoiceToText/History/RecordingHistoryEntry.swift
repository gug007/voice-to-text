import Foundation

/// A previous transcript kept alongside the active one after a regeneration, so
/// the user can compare both and drop the one they don't want. The active
/// transcript lives in `RecordingHistoryEntry`'s own fields; these are the
/// older alternates, newest first.
///
/// `nonisolated` for the same cross-actor reasons as `RecordingHistoryEntry`.
nonisolated struct TranscriptVariant: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    /// Catalog id / human name of the model that produced this version (either
    /// may be nil for very old entries that predate model metadata).
    let modelId: String?
    let modelName: String?
}

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
    /// Whether the user starred this recording. Optional so indexes written
    /// before favorites existed still decode (absent ⇒ not favorited).
    let isFavorite: Bool?

    /// Previous transcripts kept after a regeneration, newest first. Optional so
    /// indexes written before regenerate-keep existed still decode (absent ⇒ no
    /// alternates). The active transcript is always this entry's own `transcript`.
    let alternates: [TranscriptVariant]?

    /// User-assigned display names per canonical speaker label
    /// ("Speaker 1" → "Kara"). Optional so older indexes decode (absent ⇒ none).
    let speakerNames: [String: String]?

    /// Non-optional view of `isFavorite` for call sites.
    var isFavorited: Bool { isFavorite ?? false }

    /// True when this recording has more than one transcript to show.
    var hasAlternateTranscripts: Bool { !(alternates ?? []).isEmpty }

    /// Every transcript for this recording, newest (active) first. The active one
    /// reuses the entry's own id so the UI can target it for removal; alternates
    /// carry their own ids.
    var transcriptVariants: [TranscriptVariant] {
        let active = TranscriptVariant(id: id, text: transcript, modelId: modelId, modelName: modelName)
        return [active] + (alternates ?? [])
    }

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
        source: Source? = nil,
        isFavorite: Bool? = nil,
        alternates: [TranscriptVariant]? = nil,
        speakerNames: [String: String]? = nil
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
        self.isFavorite = isFavorite
        self.alternates = alternates
        self.speakerNames = speakerNames
    }

    /// Returns a copy with the active transcript/model and the alternates list
    /// replaced; all other fields (id, audio, timing, favorite, source,
    /// speaker names) are kept. Speaker names survive a regeneration because the
    /// canonical numbering is first-appearance order, so it usually matches.
    func updatingTranscripts(
        transcript: String,
        modelId: String?,
        modelName: String?,
        alternates: [TranscriptVariant]?
    ) -> RecordingHistoryEntry {
        RecordingHistoryEntry(
            id: id,
            createdAt: createdAt,
            transcript: transcript,
            audioFileName: audioFileName,
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            modelId: modelId,
            modelName: modelName,
            source: source,
            isFavorite: isFavorite,
            alternates: alternates,
            speakerNames: speakerNames
        )
    }

    /// Returns a copy with the speaker-name mapping replaced; everything else is
    /// kept. `nil` clears all assigned names (speakers revert to "Speaker N").
    func updatingSpeakerNames(_ speakerNames: [String: String]?) -> RecordingHistoryEntry {
        RecordingHistoryEntry(
            id: id,
            createdAt: createdAt,
            transcript: transcript,
            audioFileName: audioFileName,
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            modelId: modelId,
            modelName: modelName,
            source: source,
            isFavorite: isFavorite,
            alternates: alternates,
            speakerNames: speakerNames
        )
    }
}

/// Pure transcript-versioning logic for an entry — kept separate from the store
/// so it can be unit-tested without the filesystem or the main actor.
nonisolated enum TranscriptEditor {
    /// Result of regenerating: `transcript` becomes the active version and the
    /// previously active one is preserved as the newest alternate. `newAlternateID`
    /// is the id assigned to the demoted version (passed in so this stays pure).
    static func addingRegeneration(
        to entry: RecordingHistoryEntry,
        transcript: String,
        modelId: String?,
        modelName: String?,
        newAlternateID: UUID
    ) -> RecordingHistoryEntry {
        let demoted = TranscriptVariant(
            id: newAlternateID,
            text: entry.transcript,
            modelId: entry.modelId,
            modelName: entry.modelName
        )
        return entry.updatingTranscripts(
            transcript: transcript,
            modelId: modelId ?? entry.modelId,
            modelName: modelName ?? entry.modelName,
            alternates: [demoted] + (entry.alternates ?? [])
        )
    }

    /// Removes one transcript version. Removing the active one promotes the newest
    /// alternate into its place. Returns the entry unchanged when `variantID` isn't
    /// found, or when it's the only transcript left (a recording keeps at least one).
    static func removing(variantID: UUID, from entry: RecordingHistoryEntry) -> RecordingHistoryEntry {
        let alternates = entry.alternates ?? []
        if variantID == entry.id {
            guard let promoted = alternates.first else { return entry }
            let rest = Array(alternates.dropFirst())
            return entry.updatingTranscripts(
                transcript: promoted.text,
                modelId: promoted.modelId,
                modelName: promoted.modelName,
                alternates: rest.isEmpty ? nil : rest
            )
        }
        let filtered = alternates.filter { $0.id != variantID }
        guard filtered.count != alternates.count else { return entry }
        return entry.updatingTranscripts(
            transcript: entry.transcript,
            modelId: entry.modelId,
            modelName: entry.modelName,
            alternates: filtered.isEmpty ? nil : filtered
        )
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
