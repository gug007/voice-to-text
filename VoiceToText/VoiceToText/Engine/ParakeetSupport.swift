import Foundation

/// The files a Parakeet (FluidAudio) model folder must hold to load without
/// the network — what `ModelStorage.isDownloaded` asks of it, as
/// `WhisperKitModelFiles` answers for Whisper.
///
/// FluidAudio moves each file into the folder as soon as it has finished
/// downloading, so a download cancelled, dropped or stalled out part way
/// leaves a folder that holds files but not a model. Its own loader checks
/// for the four CoreML bundles and the vocabulary, then opens each bundle's
/// `coremldata.bin`; this also asks for each bundle's weights, the largest
/// file and so the likeliest one a dropped connection cut off.
nonisolated enum ParakeetModelFiles {
    /// FluidAudio's `ModelNames.ASR.requiredModels`, without the extension.
    static let requiredModelNames = ["Preprocessor", "Encoder", "Decoder", "JointDecision"]
    /// FluidAudio's `ModelNames.ASR.vocabularyFile`.
    static let vocabularyFileName = "parakeet_vocab.json"
    /// Inside each `.mlmodelc`: what the loader opens, and the weights.
    static let requiredBundleFiles = ["coremldata.bin", "weights/weight.bin"]

    static func hasRequiredModels(in folder: URL, fileManager: FileManager = .default) -> Bool {
        let bundlesComplete = requiredModelNames.allSatisfy { name in
            let bundle = folder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            return requiredBundleFiles.allSatisfy { file in
                fileManager.fileExists(atPath: bundle.appendingPathComponent(file, isDirectory: false).path)
            }
        }
        return bundlesComplete
            && fileManager.fileExists(atPath: folder.appendingPathComponent(vocabularyFileName).path)
    }
}

/// Parakeet's preparation progress, mapped onto the convention the rest of
/// the app reads.
///
/// FluidAudio reports a preparation as one 0–1 range split in half: the
/// download fills 0–0.5, by bytes, and the CoreML compile 0.5–1. Whisper's
/// download fills 0–1 and its load then reports 0.95, and the dictation card
/// and History show a percentage only while the download runs — so Parakeet
/// read "50%" at the end of its download, then jumped to "Loading". Mapped,
/// the download fills 0–1 and the compile 0.95–1, as Whisper's do.
nonisolated enum ParakeetProgress {
    /// Where the compile starts, as Whisper's load does.
    static let compileStart = 0.95

    /// `reported` is FluidAudio's `fractionCompleted`; `isLoading` is true
    /// past the download — the compile, or a model found already on disk.
    /// Listing and downloading are the download.
    static func fraction(_ reported: Double, isLoading: Bool) -> Double {
        guard reported.isFinite else { return 0 }
        let clamped = min(max(reported, 0), 1)
        guard isLoading else { return min(clamped * 2, 1) }
        return compileStart + max(clamped - 0.5, 0) * 2 * (1 - compileStart)
    }
}
