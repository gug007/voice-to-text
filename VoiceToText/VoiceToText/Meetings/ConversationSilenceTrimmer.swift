import AVFoundation
import Foundation
import OSLog

/// "Remove silence": cuts the stretches with no speech out of a finished
/// conversation WAV, in place, before it is transcribed and filed — so half an
/// hour in which nobody spoke is neither kept nor sent to a model. Opt-in.
///
/// Two passes keep memory flat however long the recording runs. The first
/// reads it a block at a time and gives every 256 ms unit a speech verdict
/// (Silero, or the energy fallback for any block Silero can't score); the
/// second copies the ranges `SilenceTrimPlan` keeps into `scratchFolderName`
/// beside the recording. That copy then replaces the original with one
/// `rename` — or, with "Keep original" on, stays a separate file and the
/// original is left exactly where and as it was.
///
/// Never loses audio: any failure, or a plan that keeps almost nothing or
/// saves almost nothing, leaves the original file exactly as it was.
nonisolated enum ConversationSilenceTrimmer {
    static let defaultsKey = "conversation.removeSilence"
    static let keepOriginalDefaultsKey = "conversation.removeSilence.keepOriginal"
    /// Where the trimmed copy is written, beside the recording. Launch
    /// recovery deletes the folder whole and never files what is in it, so a
    /// crash at any point leaves the untouched original as the only recording.
    static let scratchFolderName = "Trimmed"

    /// Whole Silero chunks (≈ 60 s), so each block's verdicts line up with the
    /// file's units.
    private static let blockSamples = VoiceActivityGate.unitSamples * 234

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var keepsOriginal: Bool {
        UserDefaults.standard.bool(forKey: keepOriginalDefaultsKey)
    }

    struct Result: Equatable, Sendable {
        let keptSeconds: Double
        let originalSeconds: Double
        /// The trimmed audio: the recording's own URL when it was cut in place,
        /// a file in `scratchFolderName` when the original was kept.
        let trimmedURL: URL
        let keptOriginal: Bool
    }

    /// Trims the WAV at `url` — in place, or with `keepingOriginal` into a
    /// separate file, the caller's to file or delete. Nil when nothing was
    /// cut and `url` is untouched.
    static func trim(url: URL, keepingOriginal: Bool) async -> Result? {
        let partial = url.deletingLastPathComponent()
            .appendingPathComponent(scratchFolderName, isDirectory: true)
            .appendingPathComponent(url.lastPathComponent, isDirectory: false)
        let started = Date()
        do {
            let scan = try await scan(url: url)
            let rate = scan.sampleRate
            let ranges = SilenceTrimPlan.keepRanges(
                speech: scan.speech,
                unitSamples: VoiceActivityGate.unitSamples,
                totalSamples: scan.totalSamples,
                sampleRate: rate
            )
            let kept = ranges.reduce(0) { $0 + $1.count }
            let result = Result(
                keptSeconds: Double(kept) / Double(rate),
                originalSeconds: Double(scan.totalSamples) / Double(rate),
                trimmedURL: keepingOriginal ? partial : url,
                keptOriginal: keepingOriginal
            )
            guard SilenceTrimPlan.isWorthApplying(ranges, totalSamples: scan.totalSamples, sampleRate: rate) else {
                AppLog.audio.notice("Silence removal left the recording as is: plan kept \(result.keptSeconds, format: .fixed(precision: 1))s of \(result.originalSeconds, format: .fixed(precision: 1))s")
                return nil
            }
            try await Task.detached(priority: .userInitiated) {
                try write(ranges, from: url, to: partial, expectedSamples: kept)
                if !keepingOriginal { try replace(url, with: partial) }
            }.value
            AppLog.audio.notice("Silence removed\(keepingOriginal ? " (original kept)" : "", privacy: .public): kept \(result.keptSeconds, format: .fixed(precision: 1))s of \(result.originalSeconds, format: .fixed(precision: 1))s in \(ranges.count) ranges, \(scan.sileroUnits) of \(scan.speech.count) units scored by Silero, \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return result
        } catch {
            try? FileManager.default.removeItem(at: partial)
            AppLog.audio.error("Silence removal failed, keeping the full recording: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Pass 1: verdicts

    private struct Scan {
        let speech: [Bool]
        let totalSamples: Int
        let sampleRate: Int
        let sileroUnits: Int
    }

    private static func scan(url: URL) async throws -> Scan {
        let reader = try await Task.detached(priority: .userInitiated) {
            try BlockReader(url: url, capacity: blockSamples)
        }.value
        // Silero only scores 16 kHz, and every working WAV is written at it.
        guard reader.sampleRate == Int(AudioConfig.targetSampleRate) else {
            throw TrimError.unsupportedSampleRate(reader.sampleRate)
        }
        let tuning = VadTuning.current
        let sileroThreshold = tuning.sileroSpeechThreshold
        let energyThreshold = tuning.energyThresholdDBFS
        let unit = VoiceActivityGate.unitSamples

        var speech: [Bool] = []
        speech.reserveCapacity(reader.totalFrames / unit + 1)
        var sileroUnits = 0
        var start = 0
        while start < reader.totalFrames {
            let from = start
            let count = min(blockSamples, reader.totalFrames - from)
            // Detached for the same reason as `MeetingTranscriber`'s reads:
            // an awaited `nonisolated` call would run on the main actor.
            let block = try await Task.detached(priority: .userInitiated) {
                try reader.read(from: from, count: count)
            }.value
            let units = (count + unit - 1) / unit
            if let scores = await VoiceActivityGate.shared.speechProbabilities(block), scores.count == units {
                speech += scores.map { $0 >= sileroThreshold }
                sileroUnits += units
            } else {
                speech += await Task.detached(priority: .userInitiated) {
                    energyVerdicts(block, thresholdDBFS: energyThreshold)
                }.value
            }
            start += count
        }
        return Scan(speech: speech, totalSamples: reader.totalFrames, sampleRate: reader.sampleRate, sileroUnits: sileroUnits)
    }

    /// A unit is speech when any 30 ms frame in it clears the energy gate's
    /// threshold — the generous reading, since a missed word can't come back.
    private static func energyVerdicts(_ samples: [Float], thresholdDBFS: Float) -> [Bool] {
        let unit = VoiceActivityGate.unitSamples
        let frameLength = max(1, Int(AudioConfig.targetSampleRate) * DictationConfig.vadFrameMs / 1_000)
        return stride(from: 0, to: samples.count, by: unit).map { start in
            let slice = samples[start..<min(start + unit, samples.count)]
            return SpeechGate.frameLevels(slice, frameLength: frameLength).contains { $0 > thresholdDBFS }
        }
    }

    // MARK: - Pass 2: copy and swap

    private static func write(
        _ ranges: [Range<Int>],
        from source: URL,
        to destination: URL,
        expectedSamples: Int
    ) throws {
        let reader = try BlockReader(url: source, capacity: blockSamples)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        let writer = try StreamingWAVWriter(url: destination, sampleRate: reader.sampleRate)
        for range in ranges {
            var start = range.lowerBound
            while start < range.upperBound {
                let count = min(blockSamples, range.upperBound - start)
                writer.append(try reader.read(from: start, count: count))
                start += count
            }
        }
        let failure = writer.failure
        let finished = writer.finalize()
        // The file on disk must hold exactly the plan, header included: the
        // duration filed in History is read back from the byte count.
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        guard failure == nil, finished != nil, writer.totalSamples == expectedSamples,
              size == WAVEncoder.headerSize + expectedSamples * 2 else {
            throw TrimError.writeFailed(failure)
        }
    }

    /// `rename` rather than `FileManager.replaceItemAt`: it either swaps the
    /// file in whole or changes nothing, where a failed `replaceItemAt` can
    /// leave the original parked in a temporary location. The creation date
    /// is carried over because launch recovery dates a stranded recording by
    /// it.
    private static func replace(_ original: URL, with partial: URL) throws {
        let fm = FileManager.default
        if let created = (try? fm.attributesOfItem(atPath: original.path))?[.creationDate] as? Date {
            try? fm.setAttributes([.creationDate: created], ofItemAtPath: partial.path)
        }
        guard rename(partial.path, original.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private enum TrimError: Error {
        case unreadable
        case shortRead(expected: Int, got: Int)
        case unsupportedSampleRate(Int)
        case writeFailed(Error?)
    }

    /// Reads exact spans of a WAV as mono samples through one reused buffer.
    /// `@unchecked Sendable` in the `AudioChunkReader` style: one task drives
    /// it at a time, hopped onto a background executor for each read.
    private final class BlockReader: @unchecked Sendable {
        let sampleRate: Int
        let totalFrames: Int
        private let file: AVAudioFile
        private let buffer: AVAudioPCMBuffer

        init(url: URL, capacity: Int) throws {
            file = try AVAudioFile(forReading: url)
            sampleRate = Int(file.processingFormat.sampleRate.rounded())
            totalFrames = Int(file.length)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(max(1, min(capacity, totalFrames)))
            ) else { throw TrimError.unreadable }
            self.buffer = buffer
        }

        /// Exactly `count` samples from `start`, or throws — a short read
        /// would shift every range after it.
        func read(from start: Int, count: Int) throws -> [Float] {
            file.framePosition = AVAudioFramePosition(start)
            try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
            guard Int(buffer.frameLength) == count else {
                throw TrimError.shortRead(expected: count, got: Int(buffer.frameLength))
            }
            return AudioChunkReader.monoSamples(from: buffer)
        }
    }
}
