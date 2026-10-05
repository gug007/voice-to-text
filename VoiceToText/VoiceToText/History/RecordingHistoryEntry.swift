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

    /// The generated summary, or nil when none has been asked for. Optional so
    /// indexes written before insights existed still decode — a synthesized
    /// `Codable` decodes an absent key into an optional `let` as nil.
    let summary: TranscriptSummary?

    /// The generated checklist, same back-compat rule as `summary`.
    let actionItems: TranscriptActionItems?

    /// Results of the user's own instructions, newest first. Optional for the
    /// same index.json back-compat reason as the two above (absent ⇒ none).
    let customInsights: [CustomInsight]?

    /// Set when the recording was saved without a real transcript — its
    /// transcription failed — so the audio would outlive the failure card;
    /// `transcript` then holds a placeholder. Nil, and
    /// absent from every index written before this existed, means the
    /// transcript is the model's output.
    let status: Status?

    /// Why a recording has no transcript yet. A struct rather than a bare
    /// enum so the row can say what went wrong in the card's own words.
    struct Status: Codable, Hashable, Sendable {
        /// One kind today. Kept as a field so a later kind decodes as a row
        /// this build passes through rather than one it misreads.
        enum Kind: String, Codable, Sendable {
            /// The transcription itself failed — network, API key, engine.
            case failed
        }

        let kind: Kind
        /// The failure as the card put it ("OpenAI didn't accept your API key.").
        let message: String
    }

    /// When the recording last lost its protection from the History cap —
    /// unstarred, its speaker names cleared, its last insight removed — so the
    /// cap ranks it from then rather than from `createdAt` (see
    /// `RecordingHistoryPruner.retainedSince`). Nil when it never lost any;
    /// optional, like the fields above, so older indexes decode (absent ⇒ nil).
    let unprotectedAt: Date?

    /// How many custom results one recording may hold at once. The cap exists
    /// for the tab bar, not for storage: four or five model-named tabs beside
    /// Transcript, Summary and Action Items stop being scannable and start
    /// wrapping. Adding one past this is refused with a message telling the
    /// user to remove one, rather than silently evicting the oldest — these
    /// cost the user's API budget, so the app does not throw one away.
    nonisolated static let maxCustomInsights = 3

    /// Non-optional view of `isFavorite` for call sites.
    var isFavorited: Bool { isFavorite ?? false }

    /// Non-optional view of `customInsights`, newest first.
    var customInsightList: [CustomInsight] { customInsights ?? [] }

    /// One stored custom result by id, or nil once it has been removed — which
    /// a tab or an in-flight job can outlive.
    func customInsight(id: UUID) -> CustomInsight? {
        customInsightList.first { $0.id == id }
    }

    /// True when the row has anything to show beyond the transcript — the tab
    /// bar only appears once this is true (or a generation is in flight).
    var hasInsights: Bool {
        summary != nil || actionItems != nil || !customInsightList.isEmpty
    }

    func hasInsight(_ kind: InsightKind) -> Bool {
        switch kind {
        case .summary: return summary != nil
        case .actionItems: return actionItems != nil
        case .custom(let id): return customInsight(id: id) != nil
        }
    }

    /// True when the transcript changed after the insight was generated — a
    /// regeneration, or a variant being promoted or removed. Insights are kept
    /// rather than deleted in that case (the old reading is usually still
    /// mostly right), so the UI marks them stale and offers a re-run instead of
    /// silently throwing the user's generated text away. No insight is never
    /// stale: there is nothing to be out of date.
    func isStale(_ kind: InsightKind) -> Bool {
        let stored: String?
        switch kind {
        case .summary: stored = summary?.sourceDigest
        case .actionItems: stored = actionItems?.sourceDigest
        case .custom(let id): stored = customInsight(id: id)?.sourceDigest
        }
        guard let stored else { return false }
        return stored != TranscriptDigest.of(transcript)
    }

    /// True when this recording has more than one transcript to show.
    var hasAlternateTranscripts: Bool { !(alternates ?? []).isEmpty }

    /// True while the recording is waiting for a transcript (see `status`).
    var needsTranscript: Bool { status != nil }

    /// Stands in for the transcript of a recording saved without one — a
    /// failed dictation, a conversation whose transcription failed or never
    /// ran. Lives here, not with the store or the controllers that write it,
    /// because recognizing it is part of reading an entry (see
    /// `transcriptIsPlaceholder`).
    nonisolated static let placeholderTranscript = "⚠︎ Audio saved without a transcript."

    /// What launch recovery wrote for a conversation the app quit before
    /// transcribing, in builds before `status`.
    nonisolated static let legacyRecoveredTranscript = "⚠︎ Recovered recording — the app quit before transcription finished. Audio saved without a transcript."

    /// Every placeholder any build has written in place of a transcript.
    /// Conversations archived before `status` existed carry one of these with
    /// no status at all, and they are just as untranscribed.
    nonisolated static let knownPlaceholderTranscripts: Set<String> = [
        placeholderTranscript,
        legacyRecoveredTranscript,
    ]

    /// True when `transcript` only stands in for one: the entry is waiting for
    /// a transcript (`status`), or it is an older build's row whose only text
    /// is one of the known placeholders. A row with alternates has had a real transcript at
    /// some point, so its active text is taken as chosen, whatever it says.
    /// This is what keeps a placeholder out of a summary request and out of a
    /// regeneration's list of versions.
    var transcriptIsPlaceholder: Bool {
        if needsTranscript { return true }
        guard !hasAlternateTranscripts else { return false }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.knownPlaceholderTranscripts.contains(text)
    }

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
        speakerNames: [String: String]? = nil,
        summary: TranscriptSummary? = nil,
        actionItems: TranscriptActionItems? = nil,
        customInsights: [CustomInsight]? = nil,
        status: Status? = nil,
        unprotectedAt: Date? = nil
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
        self.summary = summary
        self.actionItems = actionItems
        self.customInsights = customInsights
        self.status = status
        self.unprotectedAt = unprotectedAt
    }

    // MARK: - Copies
    //
    // Every mutation of a stored entry goes through one of the `updating…`
    // helpers below, and all of them funnel through `replacing`. That funnel is
    // the point: each call site spelling out the full initializer is how a newly
    // added field gets silently dropped by an unrelated mutation (a star click
    // erasing a summary, say). The identity fields — id, createdAt,
    // audioFileName, durationSeconds, sampleRate, source — are never copied
    // through because nothing may ever change them.

    /// The single place an entry is re-assembled from its mutable fields.
    /// Deliberately has no defaults: adding a field here forces every caller to
    /// say what happens to it.
    private func replacing(
        transcript: String,
        modelId: String?,
        modelName: String?,
        alternates: [TranscriptVariant]?,
        speakerNames: [String: String]?,
        isFavorite: Bool?,
        summary: TranscriptSummary?,
        actionItems: TranscriptActionItems?,
        customInsights: [CustomInsight]?,
        status: Status?,
        unprotectedAt: Date?
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
            speakerNames: speakerNames,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy with the active transcript/model and the alternates list
    /// replaced; all other fields (id, audio, timing, favorite, source,
    /// speaker names) are kept. Speaker names survive a regeneration because the
    /// canonical numbering is first-appearance order, so it usually matches.
    /// Insights survive too — they become *stale*, not wrong-headed, and
    /// deleting the user's generated summary behind a regenerate would be a
    /// nasty surprise. `isStale(_:)` is what surfaces the difference.
    func updatingTranscripts(
        transcript: String,
        modelId: String?,
        modelName: String?,
        alternates: [TranscriptVariant]?
    ) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy with the speaker-name mapping replaced; everything else is
    /// kept. `nil` clears all assigned names (speakers revert to "Speaker N").
    func updatingSpeakerNames(_ speakerNames: [String: String]?) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy with the starred state replaced; everything else is kept.
    func updatingFavorite(_ isFavorite: Bool?) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy with the summary replaced (`nil` removes it). Generating
    /// over an existing summary replaces it — there is no history of summaries.
    func updatingSummary(_ summary: TranscriptSummary?) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy with the custom results replaced (`nil`, or an empty
    /// array normalized to `nil` by the store, removes them all). The list is
    /// newest first, and the caller — `RecordingHistoryStore.setCustomInsight`
    /// — is what enforces `maxCustomInsights`; this helper stores what it is
    /// given, so a re-run replacing an existing result is never refused.
    func updatingCustomInsights(_ customInsights: [CustomInsight]?) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy whose placeholder is replaced by a real transcript and
    /// whose status is cleared — the take has been transcribed at last. The
    /// placeholder is not kept as an alternate: it was never a transcript, and
    /// a "version" reading "Audio saved without a transcript" beside the real
    /// one would only be clutter. Nil when the entry isn't waiting for one —
    /// which includes an older build's untranscribed conversation, saved with
    /// a placeholder but no status (see `transcriptIsPlaceholder`).
    func resolvingPlaceholder(
        transcript: String,
        modelId: String?,
        modelName: String?
    ) -> RecordingHistoryEntry? {
        guard transcriptIsPlaceholder else { return nil }
        return replacing(
            transcript: transcript,
            modelId: modelId ?? self.modelId,
            modelName: modelName ?? self.modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: nil,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy reporting a different failure (a retry that failed
    /// differently); nil when the entry isn't waiting for a transcript. An
    /// older build's untranscribed conversation — a placeholder and no
    /// status (see `transcriptIsPlaceholder`) — is waiting for one too, so
    /// its first failed attempt gets the status it never had.
    func updatingStatus(_ status: Status) -> RecordingHistoryEntry? {
        guard transcriptIsPlaceholder else { return nil }
        return replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy with the action items replaced (`nil` removes them).
    func updatingActionItems(_ actionItems: TranscriptActionItems?) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
        )
    }

    /// Returns a copy recording when it lost its protection from the cap;
    /// everything else is kept. Set only through
    /// `RecordingHistoryPruner.stampingLostProtection`, which decides whether
    /// an edit lost it.
    func updatingUnprotectedAt(_ unprotectedAt: Date?) -> RecordingHistoryEntry {
        replacing(
            transcript: transcript,
            modelId: modelId,
            modelName: modelName,
            alternates: alternates,
            speakerNames: speakerNames,
            isFavorite: isFavorite,
            summary: summary,
            actionItems: actionItems,
            customInsights: customInsights,
            status: status,
            unprotectedAt: unprotectedAt
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
///
/// The cap is there to stop routine dictations piling up, not to throw away
/// recordings the user has shown they care about: pruning deletes the audio
/// and everything attached to it, with no undo. So a protected entry (see
/// `isProtected`) is never pruned and doesn't count toward the cap; only the
/// unprotected entries are ranked, oldest out first.
///
/// Protected entries are kept even when they alone outnumber the cap. Every
/// way into that state is deliberate (a star, a conversation, a paid insight,
/// a named speaker) and the user can delete those rows themselves; deleting
/// one behind their back is the failure this policy exists to prevent. The
/// price is that disk use is bounded only for plain dictations, which is why
/// the History pane shows how much space the audio takes.
nonisolated enum RecordingHistoryPruner {
    struct Outcome: Equatable {
        /// Every entry to retain, ordered newest-first.
        let kept: [RecordingHistoryEntry]
        /// The unprotected overflow to delete (audio files included).
        let removed: [RecordingHistoryEntry]
    }

    /// Whether the cap must leave `entry` alone: a favorite (the user's own
    /// "keep this"), a conversation (often an hour of audio nobody can record
    /// again), a recording with insights (paid for from the user's OpenAI
    /// budget) or speaker names (typed in by hand), or one still waiting for
    /// its transcript — a take whose transcription failed or never finished,
    /// kept so it can be transcribed once the user tops up or picks another
    /// model, which may be days and hundreds of dictations later.
    ///
    /// Checked afresh on every prune, so a recording that loses its star or its
    /// last insight is an ordinary dictation again — but ranked from the moment
    /// it lost protection (see `retainedSince`), not from when it was made.
    /// Otherwise unstarring a year-old dictation would delete it at the next
    /// insert, and a stray click would be a deletion.
    static func isProtected(_ entry: RecordingHistoryEntry) -> Bool {
        entry.isFavorited
            || entry.source == .meeting
            || entry.hasInsights
            || !(entry.speakerNames ?? [:]).isEmpty
            || entry.needsTranscript
    }

    /// Where an unprotected entry stands in the cap: when it was recorded, or
    /// when it last lost protection if that's later. An unstarred dictation
    /// queues behind every newer one as if just recorded, and rolls off only
    /// after `maxUnprotected` more.
    static func retainedSince(_ entry: RecordingHistoryEntry) -> Date {
        max(entry.createdAt, entry.unprotectedAt ?? entry.createdAt)
    }

    /// `updated` as it should be stored after an edit of `original`: stamped
    /// with `now` as the moment it lost protection when `original` had it and
    /// `updated` doesn't, otherwise unchanged. The store runs every edit that
    /// can change protection through here.
    static func stampingLostProtection(
        from original: RecordingHistoryEntry,
        to updated: RecordingHistoryEntry,
        at now: Date
    ) -> RecordingHistoryEntry {
        guard isProtected(original), !isProtected(updated) else { return updated }
        return updated.updatingUnprotectedAt(now)
    }

    /// Retains every protected entry plus the `maxUnprotected` unprotected ones
    /// ranked newest by `retainedSince`, returning the rest as `removed`.
    /// `pinned` names entries a job is working on right now — an insight or a
    /// regeneration whose paid result would otherwise land on a deleted row —
    /// and those are kept even past the cap, which the next prune after the
    /// job ends enforces again. They still take their place in the ranking, so
    /// pinning one never pushes another out early. Input order is irrelevant —
    /// both lists come back newest-first by `createdAt`, the order History
    /// shows. `maxUnprotected <= 0` removes every unprotected, unpinned entry.
    static func prune(
        _ entries: [RecordingHistoryEntry],
        maxUnprotected: Int,
        pinned: Set<UUID>
    ) -> Outcome {
        var kept: [RecordingHistoryEntry] = []
        var removed: [RecordingHistoryEntry] = []
        var ranked = 0
        for entry in byRetention(entries) {
            if isProtected(entry) {
                kept.append(entry)
                continue
            }
            ranked += 1
            if ranked <= maxUnprotected || pinned.contains(entry.id) {
                kept.append(entry)
            } else {
                removed.append(entry)
            }
        }
        return Outcome(kept: newestFirst(kept), removed: newestFirst(removed))
    }

    /// Clear All: every entry leaves for the undo window (`removed`) except
    /// those in `busy` — dictation takes still being transcribed (`kept`).
    /// Their rows read "Transcribing…" and offer no trash of their own:
    /// parking one would leave the transcript about to land with no row to
    /// fill, the take would file itself as a second row, and Undo would
    /// bring the first back beside it, still saying the app closed before
    /// the take was transcribed.
    static func clearingAll(
        _ entries: [RecordingHistoryEntry],
        sparing busy: Set<UUID>
    ) -> Outcome {
        Outcome(
            kept: entries.filter { busy.contains($0.id) },
            removed: entries.filter { !busy.contains($0.id) }
        )
    }

    /// Takes the entry `id` back out of a deletion still in its undo window
    /// (`parked`) and into `current`, newest-first, leaving the rest of the
    /// batch parked. Nil when `parked` doesn't hold it. Together the two
    /// lists hold exactly what they held before — the set the on-disk index
    /// lists — so a quit right after loses nothing and restores nothing twice.
    static func reclaiming(
        _ id: UUID,
        from parked: [RecordingHistoryEntry],
        into current: [RecordingHistoryEntry]
    ) -> (entries: [RecordingHistoryEntry], parked: [RecordingHistoryEntry])? {
        guard let entry = parked.first(where: { $0.id == id }) else { return nil }
        return (restoring([entry], into: current), parked.filter { $0.id != id })
    }

    /// Undo of a deletion: puts `restored` back into `current` (the visible
    /// list, which may have gained recordings during the undo window),
    /// newest-first, and removes nothing — even if that leaves more unprotected
    /// entries than the cap.
    ///
    /// Trimming here could only take one of three things: a recording made
    /// since the deletion began (after Clear All and a new dictation, Undo used
    /// to delete the new one), the very entry the user just asked to keep, or an
    /// unrelated old dictation whose audio would vanish behind an Undo. The
    /// overflow is at most what was recorded during those few seconds, and the
    /// next insert or launch prunes it by the usual rule, which lands exactly
    /// where the cap would have without the deletion.
    static func restoring(
        _ restored: [RecordingHistoryEntry],
        into current: [RecordingHistoryEntry]
    ) -> [RecordingHistoryEntry] {
        newestFirst(current + restored)
    }

    /// Best-kept first: latest `retainedSince`, then the display order.
    private static func byRetention(_ entries: [RecordingHistoryEntry]) -> [RecordingHistoryEntry] {
        entries.sorted { lhs, rhs in
            let left = retainedSince(lhs), right = retainedSince(rhs)
            if left != right { return left > right }
            return isNewer(lhs, than: rhs)
        }
    }

    private static func newestFirst(_ entries: [RecordingHistoryEntry]) -> [RecordingHistoryEntry] {
        entries.sorted { isNewer($0, than: $1) }
    }

    private static func isNewer(_ lhs: RecordingHistoryEntry, than rhs: RecordingHistoryEntry) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        // Stable tie-break for equal timestamps so the policy is total.
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
