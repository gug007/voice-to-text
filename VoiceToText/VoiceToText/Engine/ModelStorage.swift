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

    nonisolated static func location(for descriptor: ModelDescriptor) -> URL {
        switch descriptor.backend {
        case .fluidAudio:
            return fluidAudioBaseURL.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
        case .whisperKit:
            return whisperKitBaseURL
                .appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(descriptor.backendModelId)", isDirectory: true)
        }
    }

    static func isInstalled(_ descriptor: ModelDescriptor) -> Bool {
        let url = location(for: descriptor)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return !contents.isEmpty
    }

    static func diskUsageBytes(_ descriptor: ModelDescriptor) -> Int64 {
        folderSize(at: location(for: descriptor))
    }

    static func delete(_ descriptor: ModelDescriptor) throws {
        let url = location(for: descriptor)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
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
