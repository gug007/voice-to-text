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
        try remainderUnderASecondIsKept()
        try remainderThatOverflowsSplitsEvenly()
        try coveredChunksAreUntouched()
        try languageProbeStartsAtFirstSpeech()
        print("WhisperKit support harness passed")
    }

    /// `VADAudioChunker.chunkAll`'s loop (WhisperKit 0.17, AudioChunker.swift
    /// 66-107) with the split point supplied by the caller: it stops once less
    /// than `windowPadding` is left after a cut.
    private static func chunkAll(count: Int, maxChunk: Int = 480_000, split: (Int, Int) -> Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = 0
        while start < count - 16_000 {
            var end = count
            if start + maxChunk < end { end = split(start, min(count, start + maxChunk)) }
            guard end > start else { break }
            out.append(start..<end)
            start = end
        }
        return out
    }

    private static func remainderUnderASecondIsKept() throws {
        let rate = 16_000
        let count = Int(30.8 * Double(rate))
        // Longest pause at 29.8 s: the chunker stops with 1.0 s left over.
        let cuts = chunkAll(count: count) { _, _ in Int(29.8 * Double(rate)) }
        try expect(cuts.last?.upperBound == Int(29.8 * Double(rate)), "the replica drops the last second, as WhisperKit does")
        let covered = WhisperChunkCheck.coveringRemainder(cuts, sampleCount: count, maxLength: 480_000)
        try expect(covered.last?.upperBound == count, "the remainder is decoded")
        try expect(covered.count == 2 && covered.allSatisfy { $0.count <= 480_000 }, "split in two, each within a window: \(covered)")
        try expect(covered.first?.lowerBound == 0 && zip(covered, covered.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound },
                   "contiguous from the start")
    }

    private static func remainderThatOverflowsSplitsEvenly() throws {
        let rate = 16_000
        let count = Int(75.6 * Double(rate))
        let cuts = [0..<(25 * rate), (25 * rate)..<(50 * rate), (50 * rate)..<Int(74.9 * Double(rate))]
        let covered = WhisperChunkCheck.coveringRemainder(cuts, sampleCount: count, maxLength: 480_000)
        try expect(covered.count == 3, "a remainder that fits joins the last chunk: \(covered)")
        try expect(covered.last == (50 * rate)..<count, "the last chunk now runs to the end")

        let full = [0..<(30 * rate - 100)]
        let overflow = WhisperChunkCheck.coveringRemainder(full, sampleCount: 30 * rate + 8_000, maxLength: 30 * rate)
        try expect(overflow.count == 2 && overflow.allSatisfy { $0.count <= 30 * rate && $0.count > 16_000 },
                   "a merge past one window splits evenly, no piece under a second: \(overflow)")
        try expect(overflow.last?.upperBound == 30 * rate + 8_000, "still to the end")
    }

    private static func coveredChunksAreUntouched() throws {
        let cuts = [0..<100, 100..<200]
        try expect(WhisperChunkCheck.coveringRemainder(cuts, sampleCount: 200, maxLength: 150) == cuts,
                   "chunks that reach the end are left alone")
        try expect(WhisperChunkCheck.coveringRemainder([], sampleCount: 250, maxLength: 100) == [0..<83, 83..<166, 166..<250],
                   "no chunks at all: even pieces within the window")
    }

    private static func languageProbeStartsAtFirstSpeech() throws {
        typealias P = WhisperLanguageProbe
        try expect(P.window(firstSpeechSample: 32_000, sampleCount: 1_000_000, windowSamples: 480_000) == 32_000..<512_000,
                   "one window from the first speech")
        try expect(P.window(firstSpeechSample: 900_000, sampleCount: 1_000_000, windowSamples: 480_000) == 520_000..<1_000_000,
                   "speech late in the take: a full window ending at the end")
        try expect(P.window(firstSpeechSample: nil, sampleCount: 80_000, windowSamples: 480_000) == 0..<80_000,
                   "no speech found, short take: the whole take")
        try expect(P.window(firstSpeechSample: 5, sampleCount: 0, windowSamples: 480_000).isEmpty, "no audio, no window")
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
