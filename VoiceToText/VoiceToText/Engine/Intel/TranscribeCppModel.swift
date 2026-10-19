#if arch(x86_64)
import Foundation
import OSLog

/// The transcribe.cpp build of a local model, which the Intel slice runs in
/// place of WhisperKit's and FluidAudio's CoreML ones (see
/// `TranscribeCppEngine`).
///
/// Each is a single quantized GGUF file from one of Handy's
/// `handy-computer/*-gguf` repositories on Hugging Face, at a pinned revision,
/// kept in a folder of its own under `baseURL` so `ModelStorage`'s
/// folder-based `isInstalled`, `installedState` and `delete` work for it as
/// they do for the other local models. Sizes and SHA-256s are the files at
/// that revision (Handy's `catalog.json`), checked once a download finishes.
nonisolated struct TranscribeCppModel: Sendable, Equatable {
    enum Family: Sendable, Equatable {
        case parakeet
        case whisper
    }

    /// The `ModelCatalog` id this is the Intel build of.
    let catalogID: String
    let family: Family
    /// The Hugging Face repository, `owner/name`.
    let repository: String
    /// The commit the file is fetched at, so a later push to the repository
    /// can't change what a size and checksum were pinned for.
    let revision: String
    let fileName: String
    let byteCount: Int64
    let sha256: String
    /// The Models pane's note on Intel, where the catalog's would mislead.
    let intelNotes: String?

    static let all: [TranscribeCppModel] = [
        // Q4_K_M rather than Handy's default Q8_0: on a real Intel CPU it was
        // as fast and as accurate (the same words on our 48 s clip), and it is
        // 250 MB smaller.
        TranscribeCppModel(
            catalogID: "parakeet-tdt-v3",
            family: .parakeet,
            repository: "handy-computer/parakeet-tdt-0.6b-v3-gguf",
            revision: "85ac09ea12fc4b1112fa76810059364bc6adc9de",
            fileName: "parakeet-tdt-0.6b-v3-Q4_K_M.gguf",
            byteCount: 485_425_504,
            sha256: "b68557be1e3c40207fd7c4bd9d63f1d3316b963f15325bfb0cc16a8bb0ffd181",
            intelNotes: nil
        ),
        TranscribeCppModel(
            catalogID: "whisper-large-v3-turbo",
            family: .whisper,
            repository: "handy-computer/whisper-large-v3-turbo-gguf",
            revision: "5eaf945c7978e564bae5b28a5b1639dd93c2bfb1",
            fileName: "whisper-large-v3-turbo-Q8_0.gguf",
            byteCount: 886_381_760,
            sha256: "b2e30cc286bc9f3aba4db9099fc7403543497c05ce7100d0d83091ddfd25a183",
            intelNotes: nil
        ),
        TranscribeCppModel(
            catalogID: "whisper-large-v3",
            family: .whisper,
            repository: "handy-computer/whisper-large-v3-gguf",
            revision: "e3e29bee6389c7da4a141406f07bb80ddac5337c",
            fileName: "whisper-large-v3-Q5_K_M.gguf",
            byteCount: 1_161_143_008,
            sha256: "6053d0fd69a0fd48b8fea5ea7a52b9e0cde389343566fa30e453a1b2b258dc38",
            intelNotes: "Extremely accurate offline, but slow on an Intel Mac. Turbo is much faster."
        ),
        TranscribeCppModel(
            catalogID: "whisper-small",
            family: .whisper,
            repository: "handy-computer/whisper-small-gguf",
            revision: "c0214bd34be9296695486f838e0142f900803159",
            fileName: "whisper-small-Q8_0.gguf",
            byteCount: 269_751_136,
            sha256: "9b9c8811bbcc82a7766f0fb0925614bdacb0923b2cc630daeac17108b655b860",
            intelNotes: nil
        ),
        TranscribeCppModel(
            catalogID: "whisper-base",
            family: .whisper,
            repository: "handy-computer/whisper-base-gguf",
            revision: "e0f69524f648720eca44c024d1d0dbb7027d1fa0",
            fileName: "whisper-base-Q8_0.gguf",
            byteCount: 84_962_880,
            sha256: "81c069428bc8a24551a8169cf31cf09bcfd9d4cf50389ae281323c9aa9648c81",
            intelNotes: nil
        ),
        TranscribeCppModel(
            catalogID: "whisper-tiny",
            family: .whisper,
            repository: "handy-computer/whisper-tiny-gguf",
            revision: "6687f30c99641ee265df421e582354adbc8848fc",
            fileName: "whisper-tiny-Q8_0.gguf",
            byteCount: 45_981_088,
            sha256: "325b9c7997cd1eff81ef709d55766565e71be696130cc3a3d444713798706834",
            intelNotes: nil
        ),
    ]

    static func model(forCatalogID id: String) -> TranscribeCppModel? {
        all.first { $0.catalogID == id }
    }

    /// Debug builds take `VTT_TRANSCRIBE_MODELS_DIR` instead, so a test run
    /// never downloads into, or deletes from, the real models folder.
    static var baseURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["VTT_TRANSCRIBE_MODELS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceToText/TranscribeCpp", isDirectory: true)
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(fileName)")!
    }

    var folder: URL { Self.baseURL.appendingPathComponent(catalogID, isDirectory: true) }

    var fileURL: URL { folder.appendingPathComponent(fileName, isDirectory: false) }

    var approxSizeMB: Int { Int((byteCount + 500_000) / 1_000_000) }

    /// Whether the model file is in its folder whole. Only a download that
    /// passed its size and SHA-256 check is ever moved there, so the exact size
    /// tells it apart from anything else without hashing a gigabyte.
    func isDownloaded(fileManager: FileManager = .default) -> Bool {
        guard let size = (try? fileManager.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == byteCount
    }

    // MARK: - The whisper.cpp models this replaced

    /// Where v0.2.8 kept its whisper.cpp builds of the Whisper models. Only
    /// the Intel slice ever wrote there, and nothing reads those files now.
    static var legacyWhisperCppURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceToText/WhisperCpp", isDirectory: true)
    }

    /// Frees the disk the whisper.cpp models took. Once there is no folder,
    /// this is one `stat` per launch.
    static func removeLegacyWhisperCppModels(fileManager: FileManager = .default) {
        let legacy = legacyWhisperCppURL
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        do {
            try fileManager.removeItem(at: legacy)
            AppLog.engine.info("Removed the whisper.cpp models, which transcribe.cpp replaced")
        } catch {
            AppLog.engine.error("Couldn't remove the whisper.cpp models: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
