import Foundation
import Observation
import OSLog

/// Saves every completed dictation — the recorded audio plus its transcript —
/// and exposes the list to the History pane. Audio is written as a WAV beside
/// a JSON index in Application Support. Stored history stays on this Mac;
/// transcription-provider handling happens before this store receives a result.
/// All filesystem work runs on a private serial queue so the main actor never
/// blocks on disk and writes stay strictly ordered.
@Observable
@MainActor
final class RecordingHistoryStore {
    static let shared = RecordingHistoryStore()

    /// Most recent first. The source of truth at runtime; the on-disk index is
    /// a cache rebuilt from this on every change.
    private(set) var entries: [RecordingHistoryEntry] = []

    /// Index rows this build couldn't decode — typically written by a newer
    /// build before a downgrade. Never shown, never capped and their WAVs never
    /// reaped; they're only written back so those recordings survive until a
    /// build that understands them runs again.
    private let passthroughRows: [HistoryIndexCodec.PassthroughRow]

    /// Total size of saved audio on disk, refreshed after each change. Shown in
    /// the pane header the same way the Models pane shows model disk usage.
    private(set) var totalDiskUsageBytes: Int64 = 0

    /// When off, new dictations aren't saved — except one whose transcription
    /// fails or is cancelled, whose audio exists nowhere else (`recordFailed`).
    /// Existing history is kept until the user clears it. Persisted so the
    /// choice survives relaunch.
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
        }
    }

    /// Cap on retained *unprotected* recordings: plain dictations nobody
    /// starred, ran an insight on or named speakers in. Older ones are pruned
    /// (audio deleted too) so routine dictations can't pile up without bound;
    /// protected recordings don't count and are never pruned (see
    /// `RecordingHistoryPruner`). `nonisolated` so the off-main index loader
    /// can read it.
    nonisolated static let maxEntries = 200

    /// How long a deleted recording stays recoverable before the deletion is
    /// committed and its audio removed from disk. The Undo toast is shown for
    /// this long; 5s mirrors Gmail's "Undo Send" default — long enough to catch
    /// a misclick, short enough not to overstay.
    nonisolated static let undoGraceSeconds: Double = 5

    /// A just-deleted recording (or a batch, for Clear All) held in a brief
    /// recoverable state. The entry and its audio are kept fully intact until the
    /// grace window elapses; `undoPendingDeletion()` restores it, the window's
    /// timer commits it. At most one is ever active — starting a new deletion
    /// flushes the previous one, matching the one-toast-at-a-time Undo affordance.
    struct PendingDeletion: Sendable {
        let entries: [RecordingHistoryEntry]
    }

    /// The recording(s) currently inside the undo window, or nil. Observed by the
    /// Undo toast in the History / Conversations panes.
    private(set) var pendingDeletion: PendingDeletion?

    /// Fires after `undoGraceSeconds` to commit the pending deletion. Kept out of
    /// observation (and off `PendingDeletion`) so the toast re-renders on the
    /// shown value, not when the timer handle is stored.
    @ObservationIgnored private var pendingDeletionTask: Task<Void, Never>?

    private enum Keys {
        static let enabled = "history.saveEnabled"
    }

    /// Serial so WAV writes, the index write, deletions, and size scans never
    /// race or reorder relative to one another.
    private static let ioQueue = DispatchQueue(label: "voice-to-text-ai.VoiceToText.history.io", qos: .utility)

    private init() {
        // Defaults to on: the user asked for history, so capture by default.
        if UserDefaults.standard.object(forKey: Keys.enabled) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        }
        let loaded = Self.loadIndex()
        entries = loaded.entries
        passthroughRows = loaded.passthrough
        // One launch-time directory scan both totals disk usage and sweeps orphan
        // WAVs no surviving row references (see `computeDiskUsage`) — but only
        // after a clean load with no quarantined index beside it. Otherwise the
        // WAVs' owners are unknown, and reaping would delete the very audio a
        // recovered index points at.
        let mayReap = HistoryIndexCodec.mayReapOrphans(
            loadWasClean: loaded.isClean,
            directoryFileNames: (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)) ?? []
        )
        refreshDiskUsage(
            reapingUnreferenced: mayReap
                ? HistoryIndexCodec.referencedAudio(entries: entries, passthrough: passthroughRows)
                : nil
        )
    }

    // MARK: - Locations

    nonisolated static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceToText/History", isDirectory: true)
    }

    private nonisolated static var indexURL: URL {
        directory.appendingPathComponent("index.json", isDirectory: false)
    }

    func audioURL(for entry: RecordingHistoryEntry) -> URL {
        Self.directory.appendingPathComponent(entry.audioFileName, isDirectory: false)
    }

    // MARK: - Recording

    /// Saves one finished dictation. `samples` is the mono 16 kHz Float buffer
    /// the transcript was produced from; `transcript` is the post-processed
    /// text. Returns the new entry's id (so a caller can retract it on cancel),
    /// or nil when saving is disabled or the transcript is blank.
    @discardableResult
    func record(samples: [Float], transcript: String, model: ModelDescriptor?) -> UUID? {
        guard isEnabled else { return nil }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sampleRate = Int(AudioConfig.targetSampleRate)
        let duration = sampleRate > 0 ? Double(samples.count) / Double(sampleRate) : 0
        let entry = makeEntry(
            transcript: trimmed,
            durationSeconds: duration,
            sampleRate: sampleRate,
            model: model,
            source: .dictation
        )
        return insert(entry) { dest in
            let data = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)
            try? data.write(to: dest, options: .atomic)
        }
    }

    /// Stands in for the transcript of a dictation saved without one. Same
    /// words as a conversation archived without a transcript.
    nonisolated static let placeholderTranscript = RecordingHistoryEntry.placeholderTranscript

    /// What a dictation saved ahead of its transcription says went wrong, if
    /// the app never comes back to it. The row is written with this already
    /// in place, so a quit, a crash or an update relaunch mid-request leaves
    /// a row that is correct as it stands — nothing has to sweep it at launch.
    nonisolated static let writeAheadStatus = RecordingHistoryEntry.Status(
        kind: .failed,
        message: "VoiceToText closed before this dictation was transcribed."
    )

    /// Saves a dictation the moment recording stops, before anything can fail
    /// it — the speech gate, the engine, the network, the app itself. It is
    /// an untranscribed row (`writeAheadStatus`) until the transcript fills it
    /// in (`resolveFailedTranscript`), the failure that ends the attempt
    /// replaces its status, or the caller takes it back (`retract`). Returns
    /// the new entry's id, or nil when saving is disabled: with History off a
    /// dictation that transcribes is never written at all.
    @discardableResult
    func recordPending(samples: [Float], model: ModelDescriptor?) -> UUID? {
        guard isEnabled else { return nil }
        return recordFailed(samples: samples, model: model, status: Self.writeAheadStatus)
    }

    /// Saves a dictation whose transcription failed, so
    /// its audio outlives the failure card: closing it, starting another
    /// dictation, quitting or a crash no longer lose the take. The row carries
    /// `status` and a placeholder transcript until `resolveFailedTranscript`
    /// fills it in. Returns the new entry's id, or nil when there is no audio.
    ///
    /// Saves whatever the History toggle says, like `ingest`: the toggle
    /// means "don't keep my dictations", and a take that never became text
    /// can't be dictated again — dropping it would lose the user's words, not
    /// a copy of them.
    @discardableResult
    func recordFailed(
        samples: [Float],
        model: ModelDescriptor?,
        status: RecordingHistoryEntry.Status
    ) -> UUID? {
        guard !samples.isEmpty else { return nil }
        let sampleRate = Int(AudioConfig.targetSampleRate)
        let entry = makeEntry(
            transcript: Self.placeholderTranscript,
            durationSeconds: Double(samples.count) / Double(sampleRate),
            sampleRate: sampleRate,
            model: model,
            source: .dictation,
            status: status
        )
        return insert(entry) { dest in
            let data = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)
            try? data.write(to: dest, options: .atomic)
        }
    }

    /// Builds a new entry with a fresh id and matching `<id>.wav` file name.
    private func makeEntry(
        transcript: String,
        durationSeconds: Double,
        sampleRate: Int,
        model: ModelDescriptor?,
        source: RecordingHistoryEntry.Source,
        createdAt: Date = Date(),
        status: RecordingHistoryEntry.Status? = nil
    ) -> RecordingHistoryEntry {
        let id = UUID()
        return RecordingHistoryEntry(
            id: id,
            createdAt: createdAt,
            transcript: transcript,
            audioFileName: "\(id.uuidString).wav",
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            modelId: model?.id,
            modelName: model?.displayName,
            source: source,
            status: status
        )
    }

    /// Shared insert pipeline: prune + publish the list, then (off the main
    /// actor) land the audio and delete the pruned files, then persist + refresh.
    /// `landAudio` writes the entry's audio into `dest` — encode-and-write for
    /// `record`, move-with-fallback for `ingest`.
    private func insert(
        _ entry: RecordingHistoryEntry,
        landAudio: @escaping @Sendable (_ dest: URL) -> Void
    ) -> UUID {
        let outcome = RecordingHistoryPruner.prune(
            [entry] + entries,
            maxUnprotected: Self.maxEntries,
            pinned: entriesInUse
        )
        entries = outcome.kept
        let prunedFiles = outcome.removed.map(\.audioFileName)
        let fileName = entry.audioFileName
        enqueueIO { dir in
            Self.ensureDirectoryExists(dir)
            landAudio(dir.appendingPathComponent(fileName, isDirectory: false))
        }
        // Serial IO queue: this lands after the write above, preserving order.
        removeAudioFiles(prunedFiles)
        persistIndex()
        refreshDiskUsage()
        return entry.id
    }

    /// Dictation takes saved the moment recording stopped whose transcription
    /// is still running. Each row's stored status already says what to do if
    /// the app never comes back to it (it quit or crashed mid-request), so
    /// this set only changes how the row reads in this session: "Transcribing…"
    /// instead of that failure, and no "Transcribe Again" racing the request
    /// in flight. Owned by `DictationController`; never persisted.
    private(set) var inFlightIDs: Set<UUID> = []

    func markInFlight(_ id: UUID) {
        inFlightIDs.insert(id)
    }

    func endInFlight(_ id: UUID) {
        inFlightIDs.remove(id)
    }

    /// Recordings a job is working on right now: an insight being generated or
    /// a transcript being regenerated. Pruning one mid-request would delete the
    /// row its paid result is about to land on, and `mutateEntry` would drop
    /// the result, so the cap leaves them alone until the job ends.
    private var entriesInUse: Set<UUID> {
        var ids = Set(TranscriptInsightGenerator.shared.running.map(\.entryID))
        if let regenerating = TranscriptRegenerator.shared.activeID {
            ids.insert(regenerating)
        }
        return ids.union(inFlightIDs)
    }

    // MARK: - Mutation

    /// Removes one recording, *deferred*: the row disappears immediately but the
    /// audio stays on disk for `undoGraceSeconds` so the user can undo from the
    /// toast; only then is the file removed and the index rewritten.
    func delete(id: UUID) {
        guard let removed = removeEntry(id: id) else { return }
        beginPendingDeletion([removed])
    }

    /// Removes one recording at once, with no undo window — used to retract an
    /// uncommitted dictation review take on Cancel, which is its own explicit
    /// discard and shouldn't raise a confusing "undo the cancel" toast, and a
    /// take saved ahead of transcription (`recordPending`) that turned out to
    /// hold no speech.
    func retract(id: UUID) {
        guard let removed = removeEntry(id: id) else { return }
        commitRemoval([removed])
    }

    /// Pulls one entry out of the visible list, returning it, or nil if unknown.
    private func removeEntry(id: UUID) -> RecordingHistoryEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    // MARK: - Deferred (undoable) deletion

    /// Moves `removed` into the brief recoverable state and starts the commit
    /// timer. Any deletion still in its window is superseded (committed now) so
    /// only one undo toast is ever live — deleting B finalizes A. The new pending
    /// is established *before* the superseded one's index write, so the index
    /// never momentarily drops B (which would lose it on a crash mid-window).
    private func beginPendingDeletion(_ removed: [RecordingHistoryEntry]) {
        guard !removed.isEmpty else { return }
        let superseded = pendingDeletion?.entries ?? []
        pendingDeletionTask?.cancel()
        pendingDeletion = PendingDeletion(entries: removed)
        // Commit the superseded deletion now that the new pending is in place (a
        // no-op when nothing was superseded — the on-disk index already lists
        // these entries, since persistIndex writes the union of visible + pending,
        // so a quit inside the window just restores them on the next launch).
        commitRemoval(superseded)
        let ids = removed.map(\.id)
        pendingDeletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoGraceSeconds))
            guard !Task.isCancelled else { return }
            self?.finalizePendingDeletion(expecting: ids)
        }
    }

    /// Timer hand-off: commit the pending deletion once the window elapses, but
    /// only if it's still the same one (a later delete may have replaced it; that
    /// also cancels this task, so the id check is a backstop). The same one may
    /// have lost an entry to `reclaimFromPendingDeletion` meanwhile, so what is
    /// left only has to be among the ids it started with.
    private func finalizePendingDeletion(expecting ids: [UUID]) {
        guard let pending = pendingDeletion,
              Set(pending.entries.map(\.id)).isSubset(of: ids) else { return }
        pendingDeletion = nil
        pendingDeletionTask = nil
        commitRemoval(pending.entries)
    }

    /// Restores the recording(s) inside the undo window, back in their original
    /// order; no audio was ever removed, so this is a pure re-insert. No-op once
    /// the window has already committed.
    ///
    /// Nothing is pruned here, even when recordings made during the window push
    /// the list past the cap; the next insert or launch trims the overflow. See
    /// `RecordingHistoryPruner.restoring` for why.
    func undoPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        pendingDeletion = nil
        entries = RecordingHistoryPruner.restoring(pending.entries, into: entries)
        persistIndex()
    }

    /// Takes one recording back out of the undo window into the visible list,
    /// as if its deletion alone had been undone; the rest of a Clear All's
    /// batch keeps its window and its toast. Returns whether it was there.
    ///
    /// For a dictation take whose row the user deleted while a card held it
    /// for Retry: whatever settles the take — a transcript, a failure, a
    /// cancel, silence — settles it in this row, instead of filing a second
    /// row that History's Undo would then bring the first back beside.
    ///
    /// No index write: the index lists visible and parked entries alike
    /// (`indexSnapshot`), so moving one between them changes nothing on disk.
    @discardableResult
    func reclaimFromPendingDeletion(id: UUID) -> Bool {
        guard let pending = pendingDeletion,
              let reclaimed = RecordingHistoryPruner.reclaiming(id, from: pending.entries, into: entries)
        else { return false }
        entries = reclaimed.entries
        if reclaimed.parked.isEmpty {
            pendingDeletionTask?.cancel()
            pendingDeletionTask = nil
            pendingDeletion = nil
        } else {
            pendingDeletion = PendingDeletion(entries: reclaimed.parked)
        }
        return true
    }

    /// Finalizes a deletion: removes the audio from disk and rewrites the index
    /// without these entries. Idempotent — an already-missing file is success.
    private func commitRemoval(_ removed: [RecordingHistoryEntry]) {
        guard !removed.isEmpty else { return }
        removeAudioFiles(removed.map(\.audioFileName))
        // Nothing can be written back to a recording that is gone for good, so
        // whatever the insight generator is still holding for it — half-finished
        // chunk results, failure notes, progress — is dead weight that would
        // otherwise live until the app quits. A long meeting's checkpoint is a
        // few hundred kilobytes of part text.
        for entry in removed {
            TranscriptInsightGenerator.shared.forgetRecording(entryID: entry.id)
        }
        persistIndex()
        refreshDiskUsage()
    }

    /// Best-effort delete of history WAVs by file name, on the serial IO queue.
    private func removeAudioFiles(_ fileNames: [String]) {
        guard !fileNames.isEmpty else { return }
        enqueueIO { dir in
            for file in fileNames {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file, isDirectory: false))
            }
        }
    }

    /// Flips the starred state of one entry in place (order preserved) and
    /// persists the index. No audio is touched. Survives relaunch via index.json.
    func toggleFavorite(id: UUID) {
        mutateEntry(id) { $0.updatingFavorite(!$0.isFavorited) }
    }

    /// Assigns display names to an entry's canonical speaker labels (persisted, no
    /// audio touched). Names are trimmed and empty ones dropped; an all-empty map
    /// is stored as `nil` so the speakers revert to "Speaker N". No-op on an
    /// unknown id. Giving two labels the same name merges them in the displayed
    /// transcript — see `SpeakerRelabeler.apply`.
    func setSpeakerNames(entryID: UUID, names: [String: String]) {
        var normalized: [String: String] = [:]
        for (label, name) in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { normalized[label] = trimmed }
        }
        mutateEntry(entryID) { $0.updatingSpeakerNames(normalized.isEmpty ? nil : normalized) }
    }

    /// Records a re-transcription: the freshly generated text becomes the active
    /// transcript and the previously active one is kept as the newest alternate,
    /// so the user can compare both and drop the one they don't want. Order
    /// preserved, audio untouched; no-op on a blank transcript or unknown id.
    func addRegeneratedTranscript(id: UUID, transcript: String, model: ModelDescriptor?) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index] = TranscriptEditor.addingRegeneration(
            to: entries[index],
            transcript: trimmed,
            modelId: model?.id,
            modelName: model?.displayName,
            newAlternateID: UUID()
        )
        persistIndex()
    }

    /// Fills in the transcript of a recording saved without one (see
    /// `recordFailed`): the text replaces the placeholder outright — no
    /// alternate is kept for it — and the status clears. Returns false,
    /// changing nothing, when the entry is gone or already has a transcript;
    /// the caller then files the text some other way.
    @discardableResult
    func resolveFailedTranscript(id: UUID, transcript: String, model: ModelDescriptor?) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var resolved = false
        mutateEntry(id) { entry in
            let updated = entry.resolvingPlaceholder(
                transcript: trimmed,
                modelId: model?.id,
                modelName: model?.displayName
            )
            resolved = updated != nil
            return updated
        }
        return resolved
    }

    /// Replaces the failure a recording without a transcript reports — a
    /// retry that failed differently. Returns false when the entry is gone or
    /// already has a transcript.
    @discardableResult
    func updateFailedStatus(id: UUID, status: RecordingHistoryEntry.Status) -> Bool {
        var updated = false
        mutateEntry(id) { entry in
            guard entry.status != status else {
                updated = entry.status != nil
                return nil
            }
            let next = entry.updatingStatus(status)
            updated = next != nil
            return next
        }
        return updated
    }

    /// Removes one transcript version from an entry. Removing the active one
    /// promotes the newest alternate into its place; a recording always keeps at
    /// least one transcript. No-op if nothing changed (only one left, or no match).
    func removeTranscriptVariant(entryID: UUID, variantID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let updated = TranscriptEditor.removing(variantID: variantID, from: entries[index])
        guard updated != entries[index] else { return }
        entries[index] = updated
        persistIndex()
    }

    // MARK: - Insights
    //
    // Generated summaries, action items and the results of the user's own
    // instructions are persisted with the recording, so they survive relaunch
    // and cost the user's API budget only once. Every one of these setters is a
    // no-op on an id this store has never heard of, or on one whose deletion has
    // already been *committed*: a generation that finishes after its recording
    // is gone for good must not resurrect the row.
    //
    // A recording still inside its undo window is the opposite case — it is on
    // disk, and one tap away from coming back — so `mutateEntry` looks in
    // `pendingDeletion` as well. Writing there is what stops a long generation
    // that lands during those five seconds from being dropped on the floor, paid
    // for and unrecoverable, while Undo restores the transcript without it.

    /// Applies `transform` to one entry wherever it currently lives — the visible
    /// list, or the batch parked in the undo window — and rewrites the index.
    /// A `nil` from `transform` means "nothing actually changed", which skips the
    /// write; an id in neither place is ignored entirely.
    ///
    /// Every edit that can change whether the cap protects an entry — the star,
    /// speaker names, insights — comes through here, so an entry that loses its
    /// protection is stamped with when (`stampingLostProtection`) in one place.
    ///
    /// Rebuilding `PendingDeletion` here is safe for the commit timer:
    /// `finalizePendingDeletion(expecting:)` matches on ids, which an in-place
    /// replacement leaves untouched.
    private func mutateEntry(
        _ entryID: UUID,
        _ transform: (RecordingHistoryEntry) -> RecordingHistoryEntry?
    ) {
        let now = Date()
        func settled(_ original: RecordingHistoryEntry) -> RecordingHistoryEntry? {
            transform(original).map {
                RecordingHistoryPruner.stampingLostProtection(from: original, to: $0, at: now)
            }
        }
        if let index = entries.firstIndex(where: { $0.id == entryID }) {
            guard let updated = settled(entries[index]) else { return }
            entries[index] = updated
        } else if let pending = pendingDeletion,
                  let index = pending.entries.firstIndex(where: { $0.id == entryID }) {
            guard let updated = settled(pending.entries[index]) else { return }
            var kept = pending.entries
            kept[index] = updated
            pendingDeletion = PendingDeletion(entries: kept)
        } else {
            return
        }
        persistIndex()
    }

    /// Stores (or replaces) the generated summary for one recording.
    func setSummary(entryID: UUID, summary: TranscriptSummary) {
        mutateEntry(entryID) { $0.updatingSummary(summary) }
    }

    /// Stores (or replaces) the generated action items for one recording, keeping
    /// whatever the user had already checked off.
    ///
    /// The done flags are the only user-entered data the insights layer holds, and
    /// they exist nowhere else — so a regeneration, which the stale banner
    /// actively recommends and the sparkles menu offers in one click, must not
    /// silently throw away a week of ticking items off. Carried across here rather
    /// than in the generator because this is the moment the current list is
    /// authoritative: a tick made while the request was in flight still survives.
    func setActionItems(entryID: UUID, actionItems: TranscriptActionItems) {
        mutateEntry(entryID) { entry in
            entry.updatingActionItems(
                TranscriptInsightRequest.carryingDoneFlags(from: entry.actionItems, onto: actionItems)
            )
        }
    }

    /// Checks or unchecks one action item. The user's own tick, kept alongside
    /// the generated list; an unknown item id changes nothing and skips the write.
    func toggleActionItem(entryID: UUID, itemID: UUID) {
        mutateEntry(entryID) { entry in
            guard let current = entry.actionItems else { return nil }
            let updated = current.toggling(itemID: itemID)
            guard updated != current else { return nil }
            return entry.updatingActionItems(updated)
        }
    }

    /// Stores the result of one of the user's own instructions: replaces the
    /// result with the same id when there is one, otherwise inserts it at the
    /// front (newest first, like the tab order).
    ///
    /// `replacingExisting` is the caller's *intent*, not a hint — and it is
    /// deliberately not inferred from whether the id happens to be here. A
    /// re-run holds its target's id across a request that takes minutes, and the
    /// user is one click away from deleting that tab while it runs; inferring
    /// would turn a result they threw away into a brand-new one at the front of
    /// the bar, and inferring in the other direction would refuse a plain re-run
    /// with the cap message the moment the freed slot had been filled. So a
    /// replace whose target is gone writes nothing and returns false.
    ///
    /// Returns false when a *new* result would push the recording past
    /// `maxCustomInsights` — the generator turns that into the "remove one
    /// first" message. Replacing an existing result is never refused at the cap,
    /// because a re-run of a tab that already exists adds no tabs.
    ///
    /// Also returns false for an id this store no longer knows (a recording
    /// whose deletion has already committed), which is the same silent no-op
    /// every other setter here performs; the caller has no row left to show a
    /// message on either way.
    @discardableResult
    func setCustomInsight(
        entryID: UUID,
        insight: CustomInsight,
        replacingExisting: Bool
    ) -> Bool {
        var stored = false
        mutateEntry(entryID) { entry in
            var list = entry.customInsightList
            if let index = list.firstIndex(where: { $0.id == insight.id }) {
                list[index] = insight
            } else {
                // The tab this was re-running went away while the request was in
                // flight. Nothing to replace, and resurrecting it would undo a
                // deletion the user asked for.
                guard !replacingExisting else { return nil }
                guard list.count < RecordingHistoryEntry.maxCustomInsights else { return nil }
                list.insert(insight, at: 0)
            }
            stored = true
            return entry.updatingCustomInsights(list)
        }
        return stored
    }

    /// Discards one generated insight, taking the row back to transcript-only.
    /// The audio and the transcript are untouched — this is the "I don't want
    /// this summary" escape hatch, not a delete.
    func removeInsight(entryID: UUID, kind: InsightKind) {
        mutateEntry(entryID) { entry in
            guard entry.hasInsight(kind) else { return nil }
            switch kind {
            case .summary: return entry.updatingSummary(nil)
            case .actionItems: return entry.updatingActionItems(nil)
            case .custom(let id):
                // Emptied back to nil rather than to `[]`, so a recording that
                // never had a custom result and one whose last was removed
                // encode identically — and an entry stays byte-comparable with
                // the `[CustomInsight]?` back-compat shape on disk.
                let list = entry.customInsightList.filter { $0.id != id }
                return entry.updatingCustomInsights(list.isEmpty ? nil : list)
            }
        }
    }

    /// Removes every saved recording, deferred behind the undo window like a
    /// single delete (the pane still confirms first). Audio is removed from disk
    /// only when the window commits, so an accidental Clear All is recoverable.
    /// A dictation still being transcribed stays (`inFlightIDs`), as it has no
    /// trash button of its own; see `RecordingHistoryPruner.clearingAll`.
    func clearAll() {
        let outcome = RecordingHistoryPruner.clearingAll(entries, sparing: inFlightIDs)
        guard !outcome.removed.isEmpty else { return }
        entries = outcome.kept
        beginPendingDeletion(outcome.removed)
    }

    /// Saves an already-recorded audio file (e.g. a meeting captured to disk by
    /// `MeetingRecorder`) into History by moving it into the history directory.
    /// Always saves — unlike `record`, this is an explicit user action, so it
    /// isn't gated by the auto-save toggle. Returns the new entry's id, or nil
    /// when the transcript is blank or the source file is missing. `createdAt`
    /// defaults to now; launch recovery passes when the recording was made.
    /// `status` marks a recording saved without a real transcript — its
    /// transcription failed — exactly as `recordFailed` does for a dictation.
    @discardableResult
    func ingest(
        fileURL: URL,
        transcript: String,
        durationSeconds: Double,
        model: ModelDescriptor?,
        source: RecordingHistoryEntry.Source,
        createdAt: Date = Date(),
        status: RecordingHistoryEntry.Status? = nil
    ) -> UUID? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let entry = makeEntry(
            transcript: trimmed,
            durationSeconds: durationSeconds,
            sampleRate: Int(AudioConfig.targetSampleRate),
            model: model,
            source: source,
            createdAt: createdAt,
            status: status
        )
        return insert(entry) { dest in
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: fileURL, to: dest)
            } catch {
                // Cross-volume or busy source: fall back to copy-then-remove.
                // The source goes only once the copy has landed: on a full disk
                // the copy fails too, and the file left in MeetingsTemp is what
                // launch recovery re-ingests. A partial copy is removed so that
                // recovery doesn't leave a truncated duplicate beside it.
                do {
                    try FileManager.default.copyItem(at: fileURL, to: dest)
                    try? FileManager.default.removeItem(at: fileURL)
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    AppLog.history.error("Couldn't move recording into History: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Persistence

    private func persistIndex() {
        // Persist the visible entries plus anything inside the undo window, so a
        // recording that's mid-undo stays in the on-disk index and reappears
        // (rather than being lost) if the app is quit before the window commits.
        // Committing clears `pendingDeletion`, which drops the entries here and
        // makes the deletion permanent. No need to sort/cap here — `entries` is
        // already newest-first and pruned (bar a brief overflow after an Undo or
        // an unstar), and `loadIndex` re-sorts and re-caps on launch, so the
        // on-disk order is just a cache. Rows this build couldn't decode go back
        // out unchanged after them.
        let snapshot = indexSnapshot
        let passthrough = passthroughRows
        enqueueIO { dir in
            Self.writeIndex(entries: snapshot, passthrough: passthrough, in: dir)
        }
    }

    /// Every entry the on-disk index should list: visible plus undo-window.
    private var indexSnapshot: [RecordingHistoryEntry] {
        entries + (pendingDeletion?.entries ?? [])
    }

    /// Blocks until every queued disk write has landed. Called at quit so the
    /// last index write isn't lost when the process exits — including the
    /// updater's relaunch, which quits moments after a change can be made.
    /// If that last write failed (typically a full disk), it's tried once more
    /// with the current state: space may have been freed since, and a recording
    /// whose WAV landed but whose row never reached the index otherwise leaves
    /// only an unreferenced file behind.
    func flush() {
        let snapshot = indexSnapshot
        let passthrough = passthroughRows
        let dir = Self.directory
        Self.ioQueue.sync {
            if Self.lastIndexWriteFailed {
                Self.writeIndex(entries: snapshot, passthrough: passthrough, in: dir)
            }
        }
    }

    /// Whether the most recent index write failed. Read and written only on
    /// `ioQueue`, which is what makes the unchecked access safe.
    private nonisolated(unsafe) static var lastIndexWriteFailed = false

    /// The one index write, shared by `persistIndex` and `flush` so both log a
    /// failure the same way and keep `lastIndexWriteFailed` current. Must run
    /// on `ioQueue`.
    private nonisolated static func writeIndex(
        entries: [RecordingHistoryEntry],
        passthrough: [HistoryIndexCodec.PassthroughRow],
        in dir: URL
    ) {
        ensureDirectoryExists(dir)
        do {
            let data = try HistoryIndexCodec.encode(entries: entries, passthrough: passthrough)
            try data.write(to: indexURL, options: .atomic)
            lastIndexWriteFailed = false
        } catch {
            lastIndexWriteFailed = true
            AppLog.history.error("History index write failed: \(error.localizedDescription)")
        }
    }

    private nonisolated struct LoadedIndex {
        let entries: [RecordingHistoryEntry]
        let passthrough: [HistoryIndexCodec.PassthroughRow]
        /// False when index.json existed but couldn't be read or parsed. A
        /// missing index (a fresh install) is clean.
        let isClean: Bool
    }

    private nonisolated static func loadIndex() -> LoadedIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return LoadedIndex(entries: [], passthrough: [], isClean: true)
        }
        let decoded: HistoryIndexCodec.Decoded
        do {
            decoded = try HistoryIndexCodec.decode(Data(contentsOf: indexURL))
        } catch {
            // Starting empty is the only option, but the next write would
            // replace the file — so it's moved aside first, keeping the user's
            // transcripts recoverable.
            AppLog.history.error("History index unreadable, starting empty: \(error.localizedDescription)")
            quarantineIndex()
            return LoadedIndex(entries: [], passthrough: [], isClean: false)
        }
        if !decoded.passthrough.isEmpty {
            AppLog.history.notice("History index: kept \(decoded.passthrough.count) row(s) this build can't decode")
        }
        // Drop entries whose WAV never landed on disk (an interrupted or failed
        // write) so a dangling, unplayable row self-heals instead of lingering
        // forever; the on-disk index is rewritten on the next mutation. Also
        // re-sort to the newest-first invariant the rest of the store relies on.
        let dir = directory
        let present = decoded.entries.filter {
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent($0.audioFileName, isDirectory: false).path
            )
        }
        return LoadedIndex(
            // Nothing can be running before the store exists, so nothing is pinned.
            entries: RecordingHistoryPruner.prune(present, maxUnprotected: maxEntries, pinned: []).kept,
            passthrough: decoded.passthrough,
            isClean: true
        )
    }

    /// Moves an unreadable index.json aside as `index.corrupt-<timestamp>.json`.
    /// While that file exists the launch reaper stays off (see
    /// `HistoryIndexCodec.mayReapOrphans`), so the audio it points at survives.
    private nonisolated static func quarantineIndex() {
        let destination = directory.appendingPathComponent(
            HistoryIndexCodec.quarantineFileName(at: Date()),
            isDirectory: false
        )
        do {
            try FileManager.default.moveItem(at: indexURL, to: destination)
            AppLog.history.error("Moved the unreadable history index aside as \(destination.lastPathComponent, privacy: .public)")
        } catch {
            AppLog.history.error("Couldn't move the unreadable history index aside: \(error.localizedDescription)")
        }
    }

    /// Recomputes saved-audio disk usage. When `referenced` is supplied (only at
    /// launch), the same directory pass also sweeps orphan WAVs — see
    /// `computeDiskUsage`.
    func refreshDiskUsage(reapingUnreferenced referenced: Set<String>? = nil) {
        enqueueIO { dir in
            let bytes = Self.computeDiskUsage(dir, reapingUnreferenced: referenced)
            // Reference the singleton rather than capturing `self` across the
            // queue → Task hop, which Swift 6 flags as a concurrent capture.
            Task { @MainActor in RecordingHistoryStore.shared.totalDiskUsageBytes = bytes }
        }
    }

    // MARK: - Filesystem helpers

    /// Hops the given work onto the serial IO queue with the history directory.
    private func enqueueIO(_ work: @escaping @Sendable (URL) -> Void) {
        let dir = Self.directory
        Self.ioQueue.async { work(dir) }
    }

    private nonisolated static func ensureDirectoryExists(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Sums the allocated size of every history WAV. When `referenced` is given
    /// (launch only), WAVs no surviving row — entry or passthrough — references
    /// are deleted in the same pass instead of counted, if old enough (below);
    /// init passes nil when `HistoryIndexCodec.mayReapOrphans` says the load
    /// can't be trusted.
    /// Orphans accrue when an entry is pruned by the cap or when the on-disk
    /// index lists more than the cap allows — the app quit during a delete's
    /// undo window, or after an Undo or an unstar pushed it over but before the
    /// next recording trimmed it — so loading trims it and strands the dropped
    /// entry's audio. At launch there's no in-flight recording or pending
    /// deletion, and this runs on the serial IO queue, ahead of any later
    /// write — self-healing a crash mid-window.
    ///
    /// An unreferenced WAV is only a true orphan if it's older than index.json
    /// (`HistoryIndexCodec.mayReapOrphanWAV`); a newer one is kept and counted.
    /// That's what saves a recording whose WAV landed but whose index write
    /// failed on a full disk (a same-volume move needs no space). The rule
    /// follows from the serial queue: `insert` enqueues the WAV landing before
    /// its `persistIndex`, and every WAV is dated when it lands. The date is the
    /// later of content and attribute modification: `ingest`'s move (or APFS
    /// clone-copy) keeps the source's content date — for a meeting, when
    /// recording stopped, before a transcription during which other index
    /// writes can land — but the kernel sets the attribute-change time (ctime)
    /// on every rename or new file, and nothing in user space can set it back
    /// or fail to set it. So an index write that ran before the landing is
    /// older than the WAV, and every one after it was snapshotted with the
    /// entry present. A WAV older than the last successful write was therefore
    /// dropped from that write on purpose (pruned by the cap, or trimmed on
    /// load after a quit mid-undo), and those are exactly the orphans reaped
    /// here. The one ordering this can't see is the wall clock stepping back
    /// between the last successful write and a landing.
    ///
    /// This only keeps the file until the next successful index write, which
    /// won't list it; the launch after that reaps it. The recovery path is
    /// `flush()` retrying the failed write at quit.
    private nonisolated static func computeDiskUsage(
        _ dir: URL,
        reapingUnreferenced referenced: Set<String>?
    ) -> Int64 {
        // Read once, before any WAV is judged; nil (no index) reaps nothing.
        let indexModified = referenced == nil
            ? nil
            : (try? indexURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .contentModificationDateKey, .attributeModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "wav" {
            let values = try? fileURL.resourceValues(forKeys: keys)
            let landed = [values?.contentModificationDate, values?.attributeModificationDate].compactMap { $0 }.max()
            if let referenced, !referenced.contains(fileURL.lastPathComponent),
               HistoryIndexCodec.mayReapOrphanWAV(modified: landed, indexModified: indexModified) {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
