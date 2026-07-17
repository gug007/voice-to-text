import Foundation
import Observation

/// Saves every completed dictation — the recorded audio plus its transcript —
/// and exposes the list to the History pane. Audio is written as a WAV beside
/// a JSON index in Application Support; nothing leaves the Mac, matching the
/// rest of the app. All filesystem work runs on a private serial queue so the
/// main actor never blocks on disk and writes stay strictly ordered.
@Observable
@MainActor
final class RecordingHistoryStore {
    static let shared = RecordingHistoryStore()

    /// Most recent first. The source of truth at runtime; the on-disk index is
    /// a cache rebuilt from this on every change.
    private(set) var entries: [RecordingHistoryEntry] = []

    /// Total size of saved audio on disk, refreshed after each change. Shown in
    /// the pane header the same way the Models pane shows model disk usage.
    private(set) var totalDiskUsageBytes: Int64 = 0

    /// When off, new dictations aren't saved. Existing history is kept until the
    /// user clears it. Persisted so the choice survives relaunch.
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
        }
    }

    /// Cap on retained recordings; older ones are pruned (audio deleted too) so
    /// history can't grow without bound. `nonisolated` so the off-main index
    /// loader can read it.
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
        entries = Self.loadIndex()
        // One launch-time directory scan both totals disk usage and sweeps orphan
        // WAVs no surviving entry references (see `computeDiskUsage`).
        refreshDiskUsage(reapingUnreferenced: Set(entries.map(\.audioFileName)))
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

    /// Builds a new entry with a fresh id and matching `<id>.wav` file name.
    private func makeEntry(
        transcript: String,
        durationSeconds: Double,
        sampleRate: Int,
        model: ModelDescriptor?,
        source: RecordingHistoryEntry.Source
    ) -> RecordingHistoryEntry {
        let id = UUID()
        return RecordingHistoryEntry(
            id: id,
            createdAt: Date(),
            transcript: transcript,
            audioFileName: "\(id.uuidString).wav",
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            modelId: model?.id,
            modelName: model?.displayName,
            source: source
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
        let outcome = RecordingHistoryPruner.prune([entry] + entries, maxCount: Self.maxEntries)
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
    /// discard and shouldn't raise a confusing "undo the cancel" toast.
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
    /// also cancels this task, so the id check is a backstop).
    private func finalizePendingDeletion(expecting ids: [UUID]) {
        guard let pending = pendingDeletion, pending.entries.map(\.id) == ids else { return }
        pendingDeletion = nil
        pendingDeletionTask = nil
        commitRemoval(pending.entries)
    }

    /// Restores the recording(s) inside the undo window, back in their original
    /// order; no audio was ever removed, so this is a pure re-insert. No-op once
    /// the window has already committed.
    func undoPendingDeletion() {
        guard let pending = pendingDeletion else { return }
        pendingDeletionTask?.cancel()
        pendingDeletionTask = nil
        pendingDeletion = nil
        // Restoring can push the count past the cap if new recordings landed
        // during the window. Reserve room for the restored entries first and prune
        // only the *existing* visible list, so Undo always brings its recording
        // back — the entry being restored can never be the one evicted (which
        // would delete the very file the user asked to keep). Only the genuinely
        // oldest non-restored recordings are dropped, their audio removed to avoid
        // orphans, mirroring `insert`.
        let keepFromExisting = max(0, Self.maxEntries - pending.entries.count)
        let trimmed = RecordingHistoryPruner.prune(entries, maxCount: keepFromExisting)
        entries = RecordingHistoryPruner.prune(
            trimmed.kept + pending.entries,
            maxCount: Self.maxEntries
        ).kept
        removeAudioFiles(trimmed.removed.map(\.audioFileName))
        persistIndex()
        refreshDiskUsage()
    }

    /// Finalizes a deletion: removes the audio from disk and rewrites the index
    /// without these entries. Idempotent — an already-missing file is success.
    private func commitRemoval(_ removed: [RecordingHistoryEntry]) {
        guard !removed.isEmpty else { return }
        removeAudioFiles(removed.map(\.audioFileName))
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
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[index]
        entries[index] = RecordingHistoryEntry(
            id: old.id,
            createdAt: old.createdAt,
            transcript: old.transcript,
            audioFileName: old.audioFileName,
            durationSeconds: old.durationSeconds,
            sampleRate: old.sampleRate,
            modelId: old.modelId,
            modelName: old.modelName,
            source: old.source,
            isFavorite: !old.isFavorited,
            alternates: old.alternates,
            speakerNames: old.speakerNames
        )
        persistIndex()
    }

    /// Assigns display names to an entry's canonical speaker labels (persisted, no
    /// audio touched). Names are trimmed and empty ones dropped; an all-empty map
    /// is stored as `nil` so the speakers revert to "Speaker N". No-op on an
    /// unknown id. Giving two labels the same name merges them in the displayed
    /// transcript — see `SpeakerRelabeler.apply`.
    func setSpeakerNames(entryID: UUID, names: [String: String]) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var normalized: [String: String] = [:]
        for (label, name) in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { normalized[label] = trimmed }
        }
        entries[index] = entries[index].updatingSpeakerNames(normalized.isEmpty ? nil : normalized)
        persistIndex()
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

    /// Removes every saved recording, deferred behind the undo window like a
    /// single delete (the pane still confirms first). Audio is removed from disk
    /// only when the window commits, so an accidental Clear All is recoverable.
    func clearAll() {
        guard !entries.isEmpty else { return }
        let removed = entries
        entries = []
        beginPendingDeletion(removed)
    }

    /// Saves an already-recorded audio file (e.g. a meeting captured to disk by
    /// `MeetingRecorder`) into History by moving it into the history directory.
    /// Always saves — unlike `record`, this is an explicit user action, so it
    /// isn't gated by the auto-save toggle. Returns the new entry's id, or nil
    /// when the transcript is blank or the source file is missing.
    @discardableResult
    func ingest(
        fileURL: URL,
        transcript: String,
        durationSeconds: Double,
        model: ModelDescriptor?,
        source: RecordingHistoryEntry.Source
    ) -> UUID? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let entry = makeEntry(
            transcript: trimmed,
            durationSeconds: durationSeconds,
            sampleRate: Int(AudioConfig.targetSampleRate),
            model: model,
            source: source
        )
        return insert(entry) { dest in
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: fileURL, to: dest)
            } catch {
                // Cross-volume or busy source: fall back to copy-then-remove.
                try? FileManager.default.copyItem(at: fileURL, to: dest)
                try? FileManager.default.removeItem(at: fileURL)
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
        // already newest-first and ≤ maxEntries, and `loadIndex` re-sorts and
        // re-caps on launch, so the on-disk order is just a cache.
        let snapshot = entries + (pendingDeletion?.entries ?? [])
        enqueueIO { dir in
            Self.ensureDirectoryExists(dir)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    private nonisolated static func loadIndex() -> [RecordingHistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([RecordingHistoryEntry].self, from: data) else { return [] }
        // Drop entries whose WAV never landed on disk (an interrupted or failed
        // write) so a dangling, unplayable row self-heals instead of lingering
        // forever; the on-disk index is rewritten on the next mutation. Also
        // re-sort to the newest-first invariant the rest of the store relies on.
        let dir = directory
        let present = decoded.filter {
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent($0.audioFileName, isDirectory: false).path
            )
        }
        return RecordingHistoryPruner.prune(present, maxCount: maxEntries).kept
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
    /// (launch only), WAVs no surviving entry references are deleted in the same
    /// pass instead of counted: orphans accrue when an entry is pruned by the cap
    /// or when the app is quit during a delete's undo window (the on-disk index
    /// can briefly list more than the cap, so loading trims it and strands the
    /// dropped entry's audio). At launch there's no in-flight recording or pending
    /// deletion, so any unreferenced WAV is a true orphan, and this runs on the
    /// serial IO queue, ahead of any later write — self-healing a crash mid-window.
    private nonisolated static func computeDiskUsage(
        _ dir: URL,
        reapingUnreferenced referenced: Set<String>?
    ) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "wav" {
            if let referenced, !referenced.contains(fileURL.lastPathComponent) {
                try? FileManager.default.removeItem(at: fileURL)
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
