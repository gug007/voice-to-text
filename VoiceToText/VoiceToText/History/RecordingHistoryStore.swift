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
        refreshDiskUsage()
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
            for file in prunedFiles {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file, isDirectory: false))
            }
        }
        persistIndex()
        refreshDiskUsage()
        return entry.id
    }

    // MARK: - Mutation

    func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let removed = entries.remove(at: index)
        enqueueIO { dir in
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent(removed.audioFileName, isDirectory: false)
            )
        }
        persistIndex()
        refreshDiskUsage()
    }

    func clearAll() {
        guard !entries.isEmpty else { return }
        let files = entries.map(\.audioFileName)
        entries = []
        totalDiskUsageBytes = 0
        enqueueIO { dir in
            for file in files {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file, isDirectory: false))
            }
        }
        persistIndex()
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
        let snapshot = entries
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

    func refreshDiskUsage() {
        enqueueIO { dir in
            let bytes = Self.computeDiskUsage(dir)
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

    private nonisolated static func computeDiskUsage(_ dir: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "wav" {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
