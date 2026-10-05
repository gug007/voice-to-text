import Foundation

struct ParakeetSupportHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ParakeetSupportHarnessFailure(description: message)
    }
}

@main
struct ParakeetSupportHarness {
    static func main() throws {
        try onlyAWholeFolderIsDownloaded()
        try theDownloadFillsTheWholeRange()
        print("Parakeet support harness passed")
    }

    private static func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private static func onlyAWholeFolderIsDownloaded() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-harness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try expect(!ParakeetModelFiles.hasRequiredModels(in: folder), "a folder that doesn't exist isn't loadable")

        try touch(folder.appendingPathComponent("config.json"))
        for name in ParakeetModelFiles.requiredModelNames {
            try touch(folder.appendingPathComponent("\(name).mlmodelc/coremldata.bin"))
        }
        try touch(folder.appendingPathComponent(ParakeetModelFiles.vocabularyFileName))
        try expect(
            !ParakeetModelFiles.hasRequiredModels(in: folder),
            "a download cut off before the weights landed isn't loadable"
        )

        for name in ParakeetModelFiles.requiredModelNames where name != "Encoder" {
            try touch(folder.appendingPathComponent("\(name).mlmodelc/weights/weight.bin"))
        }
        try expect(
            !ParakeetModelFiles.hasRequiredModels(in: folder),
            "nor one missing the encoder's weights alone"
        )

        try touch(folder.appendingPathComponent("Encoder.mlmodelc/weights/weight.bin"))
        try expect(ParakeetModelFiles.hasRequiredModels(in: folder), "every bundle and the vocabulary: loadable")

        try FileManager.default.removeItem(at: folder.appendingPathComponent(ParakeetModelFiles.vocabularyFileName))
        try expect(!ParakeetModelFiles.hasRequiredModels(in: folder), "without the vocabulary it isn't")

        try expect(
            ParakeetModelFiles.requiredModelNames == ["Preprocessor", "Encoder", "Decoder", "JointDecision"]
                && ParakeetModelFiles.vocabularyFileName == "parakeet_vocab.json",
            "the names FluidAudio's loader asks for"
        )
    }

    private static func theDownloadFillsTheWholeRange() throws {
        let cases: [(Double, Bool, Double)] = [
            (0, false, 0),
            (0.21, false, 0.42),
            (0.5, false, 1),
            (0.7, false, 1),
            (0.5, true, 0.95),
            (0.75, true, 0.975),
            (1, true, 1),
            (0.2, true, 0.95),
            (.nan, false, 0),
        ]
        for (reported, isLoading, expected) in cases {
            let got = ParakeetProgress.fraction(reported, isLoading: isLoading)
            try expect(
                abs(got - expected) < 1e-9,
                "\(reported) (loading: \(isLoading)) → \(got), expected \(expected)"
            )
        }
    }
}
