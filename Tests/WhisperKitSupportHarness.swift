import Foundation

struct WhisperKitSupportHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw WhisperKitSupportHarnessFailure(description: message)
    }
}

private struct DecodeFailed: Error {}

@main
struct WhisperKitSupportHarness {
    static func main() throws {
        try installedFolderNeedsAllThreeModels()
        try packagesCountLikeCompiledBundles()
        try missingFolderIsNotInstalled()
        try chunkCheckRetriesFailures()
        try chunkCheckRetriesEmptyPromptedSpeechWithoutPrompt()
        try chunkCheckAcceptsHonestSilence()
        print("WhisperKit support harness passed")
    }

    private static func scratchFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperkit-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeCompiled(_ name: String, in folder: URL) throws {
        let bundle = folder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
    }

    private static func installedFolderNeedsAllThreeModels() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try expect(!WhisperKitModelFiles.hasRequiredModels(in: folder), "an empty folder isn't loadable")
        // Exactly what a real download leaves beside the bundles; none of it
        // stands in for a model.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("generation_config.json"))
        try makeCompiled("MelSpectrogram", in: folder)
        try makeCompiled("AudioEncoder", in: folder)
        try expect(!WhisperKitModelFiles.hasRequiredModels(in: folder),
                   "a folder without TextDecoder goes to the download path")
        try makeCompiled("TextDecoder", in: folder)
        try expect(WhisperKitModelFiles.hasRequiredModels(in: folder),
                   "MelSpectrogram + AudioEncoder + TextDecoder load from disk")
        try expect(WhisperKitModelFiles.requiredModelNames == ["MelSpectrogram", "AudioEncoder", "TextDecoder"],
                   "the list matches WhisperKit.loadModels; TextDecoderContextPrefill stays optional")
    }

    private static func packagesCountLikeCompiledBundles() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try makeCompiled("MelSpectrogram", in: folder)
        try makeCompiled("AudioEncoder", in: folder)
        let packageModel = folder.appendingPathComponent("TextDecoder.mlpackage/Data/com.apple.CoreML", isDirectory: true)
        try FileManager.default.createDirectory(at: packageModel, withIntermediateDirectories: true)
        try expect(!WhisperKitModelFiles.hasRequiredModels(in: folder),
                   "an .mlpackage without its model.mlmodel doesn't count")
        try Data("x".utf8).write(to: packageModel.appendingPathComponent("model.mlmodel"))
        try expect(WhisperKitModelFiles.hasRequiredModels(in: folder),
                   "an .mlpackage counts, as ModelUtilities.detectModelURL resolves it")
    }

    private static func missingFolderIsNotInstalled() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperkit-support-missing-\(UUID().uuidString)", isDirectory: true)
        try expect(!WhisperKitModelFiles.hasRequiredModels(in: folder), "a folder that doesn't exist isn't loadable")
    }

    private static func chunkCheckRetriesFailures() throws {
        let action = WhisperChunkCheck.action(for: .failure(DecodeFailed()), prompted: false) { true }
        try expect(action == .retry, "a chunk that threw gets one more pass instead of being dropped")
    }

    private static func chunkCheckRetriesEmptyPromptedSpeechWithoutPrompt() throws {
        let action = WhisperChunkCheck.action(for: .success("  "), prompted: true) { true }
        try expect(action == .retryWithoutPrompt,
                   "empty under a prompt over speech: the prefill end-of-text bug, so decode again unprompted")
    }

    private static func chunkCheckAcceptsHonestSilence() throws {
        var asked = false
        let unprompted = WhisperChunkCheck.action(for: .success(""), prompted: false) {
            asked = true
            return true
        }
        try expect(unprompted == .accept(""), "an unprompted empty result is the model's answer")
        try expect(!asked, "speech energy isn't measured when it can't change the outcome")

        let silent = WhisperChunkCheck.action(for: .success(""), prompted: true) { false }
        try expect(silent == .accept(""),
                   "empty under a prompt over silence stays empty — an unprompted pass would invite a hallucination")

        let text = WhisperChunkCheck.action(for: .success(" Hello there. "), prompted: true) {
            asked = true
            return true
        }
        try expect(text == .accept("Hello there."), "text is accepted, trimmed")
        try expect(!asked, "and never pays for the energy check")
    }
}
