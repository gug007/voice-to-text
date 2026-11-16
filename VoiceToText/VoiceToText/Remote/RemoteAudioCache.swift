import AVFoundation
import Foundation
import OSLog

/// AAC copies of conversation audio for the iPhone. History keeps 16-bit WAV
/// (about 115 MB an hour); AAC is a tenth of that, which is the difference
/// between a download that finishes over a phone's connection and one that
/// doesn't. The copy is made once per conversation, off the main actor, and
/// kept in Caches (the system may purge it; it is rebuilt on the next ask).
/// History's own files are only ever read.
actor RemoteAudioCache {
    static let shared = RemoteAudioCache()

    /// Copies kept at once; older ones are deleted as new ones are made.
    nonisolated static let keptCopies = 5

    private var inFlight: [UUID: Task<URL, Error>] = [:]

    nonisolated static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let bundle = Bundle.main.bundleIdentifier ?? "voice-to-text-ai.VoiceToText"
        return caches.appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("RemoteAudio", isDirectory: true)
    }

    /// The AAC copy of `source`, made now if there is none newer than it.
    func m4a(for id: UUID, source: URL) async throws -> URL {
        let destination = Self.directory.appendingPathComponent("\(id.uuidString).m4a")
        if Self.isFresh(destination, comparedTo: source) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return destination
        }
        if let running = inFlight[id] { return try await running.value }
        let task = Task.detached(priority: .userInitiated) {
            try await Self.export(source, to: destination)
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let url = try await task.value
        Self.prune(keeping: destination)
        return url
    }

    private nonisolated static func isFresh(_ copy: URL, comparedTo source: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let made = try? copy.resourceValues(forKeys: keys),
              let original = try? source.resourceValues(forKeys: keys),
              let madeDate = made.contentModificationDate,
              let originalDate = original.contentModificationDate,
              (made.fileSize ?? 0) > 0 else { return false }
        return madeDate >= originalDate
    }

    private nonisolated static func export(_ source: URL, to destination: URL) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent("\(UUID().uuidString).partial.m4a")
        defer { try? fm.removeItem(at: partial) }
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RemoteAudioError.exportUnavailable
        }
        let started = Date()
        try await session.export(to: partial, as: .m4a)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: partial, to: destination)
        let seconds = Date().timeIntervalSince(started)
        AppLog.remote.notice("Made the iPhone's AAC copy of a conversation in \(seconds, format: .fixed(precision: 1), privacy: .public)s")
        return destination
    }

    private nonisolated static func prune(keeping current: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let copies = files
            .filter { $0.pathExtension == "m4a" && !$0.lastPathComponent.contains(".partial.") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for stale in copies.dropFirst(keptCopies) where stale != current {
            try? fm.removeItem(at: stale)
        }
    }
}

nonisolated enum RemoteAudioError: LocalizedError {
    case exportUnavailable

    var errorDescription: String? {
        "This Mac couldn't convert the recording for the iPhone."
    }
}
