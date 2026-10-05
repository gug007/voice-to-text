import Foundation

enum ModelStorage {
    nonisolated static var whisperKitBaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceToText/WhisperKit", isDirectory: true)
    }

    nonisolated static var fluidAudioBaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    nonisolated static func location(for descriptor: ModelDescriptor) -> URL? {
        switch descriptor.backend {
        case .fluidAudio:
            return fluidAudioBaseURL.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
        case .whisperKit:
            return whisperKitModelFolder(variant: descriptor.backendModelId)
        case .openAI, .openAIRealtime, .elevenLabs:
            return nil
        }
    }

    /// Where `WhisperKit.download` puts a variant under `whisperKitBaseURL`:
    /// the Hub snapshot of `argmaxinc/whisperkit-coreml`, then the variant's
    /// own folder. `WhisperKitEngine` loads from here without the network.
    nonisolated static func whisperKitModelFolder(variant: String) -> URL {
        whisperKitBaseURL
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(variant)", isDirectory: true)
    }

    /// Whether the model's folder holds any file. Stops at the first one,
    /// where `installedState` sizes the whole tree.
    static func isInstalled(_ descriptor: ModelDescriptor) -> Bool {
        guard let url = location(for: descriptor) else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
              let enumerator = FileManager.default.enumerator(
                  at: url,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ) else { return false }
        return enumerator.nextObject() != nil
    }

    /// Whether the model is downloaded, ready to load without the network:
    /// on disk, and not still being fetched (`readiness`). `isInstalled`
    /// alone is true once the folder holds any file, and a download writes
    /// into that same folder as it goes. The folder must also hold every
    /// file a load needs — Whisper's CoreML bundles (`WhisperKitModelFiles`),
    /// Parakeet's bundles and vocabulary (`ParakeetModelFiles`) — which
    /// catches a download cancelled, dropped or stalled out part way, which
    /// leaves the files it finished behind.
    static func isDownloaded(_ descriptor: ModelDescriptor, readiness: ModelReadiness) -> Bool {
        guard !readiness.isDownloading, isInstalled(descriptor) else { return false }
        switch descriptor.backend {
        case .whisperKit:
            return WhisperKitModelFiles.hasRequiredModels(in: whisperKitModelFolder(variant: descriptor.backendModelId))
        case .fluidAudio:
            return location(for: descriptor).map { ParakeetModelFiles.hasRequiredModels(in: $0) } ?? false
        case .openAI, .openAIRealtime, .elevenLabs:
            return true
        }
    }

    static func diskUsageBytes(_ descriptor: ModelDescriptor) -> Int64 {
        installedState(descriptor).sizeBytes
    }

    /// Single-pass walk that returns both whether the model directory has
    /// any contents and its total allocated size. Callers that need both
    /// should prefer this over `isInstalled` + `diskUsageBytes`, which would
    /// enumerate the same tree twice.
    static func installedState(_ descriptor: ModelDescriptor) -> (installed: Bool, sizeBytes: Int64) {
        guard let url = location(for: descriptor) else { return (false, 0) }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return (false, 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (false, 0) }

        var total: Int64 = 0
        var hasFiles = false
        for case let fileURL as URL in enumerator {
            hasFiles = true
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return (hasFiles, total)
    }

    static func delete(_ descriptor: ModelDescriptor) throws {
        guard let url = location(for: descriptor) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

extension Int64 {
    var formattedDiskSize: String {
        let mb = Double(self) / 1_000_000.0
        if mb >= 1000 {
            return String(format: "%.2f GB", mb / 1000.0)
        }
        if mb >= 1 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.1f KB", Double(self) / 1000.0)
    }
}
