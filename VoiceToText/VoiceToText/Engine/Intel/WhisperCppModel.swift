#if arch(x86_64)
import Foundation

/// The whisper.cpp build of a local Whisper model, which the Intel slice runs
/// in place of WhisperKit's CoreML one (see `WhisperCppEngine`).
///
/// Each is a single quantized GGML file from `ggerganov/whisper.cpp` on
/// Hugging Face, kept in a folder of its own under `baseURL` so
/// `ModelStorage`'s folder-based `isInstalled`, `installedState` and `delete`
/// work for it as they do for the other local models. Sizes and SHA-256s are
/// the files on the Hub at `main`, checked once a download finishes.
nonisolated struct WhisperCppModel: Sendable, Equatable {
    /// The `ModelCatalog` id this is the Intel build of.
    let catalogID: String
    let fileName: String
    let byteCount: Int64
    let sha256: String
    /// The Models pane's note on Intel, where the catalog's would mislead.
    let intelNotes: String?

    static let all: [WhisperCppModel] = [
        WhisperCppModel(
            catalogID: "whisper-large-v3-turbo",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            byteCount: 574_041_195,
            sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            intelNotes: nil
        ),
        WhisperCppModel(
            catalogID: "whisper-large-v3",
            fileName: "ggml-large-v3-q5_0.bin",
            byteCount: 1_081_140_203,
            sha256: "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1",
            intelNotes: "Extremely accurate offline, but slow on an Intel Mac. Turbo is much faster."
        ),
        WhisperCppModel(
            catalogID: "whisper-small",
            fileName: "ggml-small-q5_1.bin",
            byteCount: 190_085_487,
            sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
            intelNotes: nil
        ),
        WhisperCppModel(
            catalogID: "whisper-base",
            fileName: "ggml-base-q5_1.bin",
            byteCount: 59_707_625,
            sha256: "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898",
            intelNotes: nil
        ),
        WhisperCppModel(
            catalogID: "whisper-tiny",
            fileName: "ggml-tiny-q5_1.bin",
            byteCount: 32_152_673,
            sha256: "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7",
            intelNotes: nil
        ),
    ]

    static func model(forCatalogID id: String) -> WhisperCppModel? {
        all.first { $0.catalogID == id }
    }

    static var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceToText/WhisperCpp", isDirectory: true)
    }

    private static let downloadBase = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/")!

    var downloadURL: URL { Self.downloadBase.appendingPathComponent(fileName, isDirectory: false) }

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
}
#endif
