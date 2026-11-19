import AVFoundation
import Foundation
import Observation
import OSLog

@Observable
final class Library {
    static let shared = Library()

    private(set) var entries: [RecordingHistoryEntry] = []
    private(set) var saveError: String?
    private var passthrough: [HistoryIndexCodec.PassthroughRow] = []

    static let waitingStatus = RecordingHistoryEntry.Status(kind: .failed, message: "Waiting to be transcribed.")
    static let modelName = "Parakeet TDT v3"
    static let modelId = "parakeet-tdt-v3"

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("History", isDirectory: true)
    }

    private nonisolated static var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    private init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        load()
        recoverOrphans()
    }

    func entry(id: UUID) -> RecordingHistoryEntry? {
        entries.first { $0.id == id }
    }

    func audioURL(for entry: RecordingHistoryEntry) -> URL {
        Self.directory.appendingPathComponent(entry.audioFileName)
    }

    nonisolated static func newAudioURL(id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).wav")
    }

    @discardableResult
    func addPending(
        id: UUID,
        durationSeconds: Double,
        createdAt: Date = Date(),
        status: RecordingHistoryEntry.Status = Library.waitingStatus
    ) -> RecordingHistoryEntry {
        let entry = RecordingHistoryEntry(
            id: id,
            createdAt: createdAt,
            transcript: RecordingHistoryEntry.placeholderTranscript,
            audioFileName: "\(id.uuidString).wav",
            durationSeconds: durationSeconds,
            sampleRate: Int(AudioConfig.targetSampleRate),
            modelId: nil,
            modelName: nil,
            source: .meeting,
            status: status
        )
        entries.insert(entry, at: 0)
        entries.sort { $0.createdAt > $1.createdAt }
        save()
        return entry
    }

    func update(id: UUID, _ transform: (RecordingHistoryEntry) -> RecordingHistoryEntry?) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let updated = transform(entries[index]) else { return }
        entries[index] = updated
        save()
    }

    func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        try? FileManager.default.removeItem(at: audioURL(for: entry))
        save()
    }

    var diskUsageBytes: Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        do {
            let decoded = try HistoryIndexCodec.decode(data)
            entries = decoded.entries.sorted { $0.createdAt > $1.createdAt }
            passthrough = decoded.passthrough
        } catch {
            let aside = Self.directory.appendingPathComponent("index.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: Self.indexURL, to: aside)
            AppLog.history.error("History index unreadable, moved aside: \(error.localizedDescription)")
        }
    }

    private func recoverOrphans() {
        let referenced = HistoryIndexCodec.referencedAudio(entries: entries, passthrough: passthrough)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        var recovered = false
        for url in files where url.pathExtension == "wav" && !referenced.contains(url.lastPathComponent) {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  StreamingWAVWriter.repairHeaderInPlace(at: url),
                  let file = try? AVAudioFile(forReading: url),
                  file.length > 0 else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let duration = Double(file.length) / file.fileFormat.sampleRate
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            entries.append(RecordingHistoryEntry(
                id: id,
                createdAt: created,
                transcript: RecordingHistoryEntry.placeholderTranscript,
                audioFileName: url.lastPathComponent,
                durationSeconds: duration,
                sampleRate: Int(file.fileFormat.sampleRate),
                modelId: nil,
                modelName: nil,
                source: .meeting,
                status: Self.waitingStatus
            ))
            recovered = true
        }
        if recovered {
            entries.sort { $0.createdAt > $1.createdAt }
            save()
        }
    }

    private func save() {
        do {
            let data = try HistoryIndexCodec.encode(entries: entries, passthrough: passthrough)
            try data.write(to: Self.indexURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            AppLog.history.error("History index write failed: \(error.localizedDescription)")
        }
    }
}
