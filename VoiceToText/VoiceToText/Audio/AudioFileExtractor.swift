import AVFoundation
import CoreMedia
import Foundation

/// Decodes the audio track of any AVFoundation-readable media — a video
/// container (.mp4 / .mov / .m4v …) or an audio file (.mp3 / .m4a / .wav …) —
/// into a 16 kHz mono 16-bit PCM WAV on disk, so an uploaded file flows through
/// the exact same chunk → transcribe → History pipeline as a recorded
/// conversation (`MeetingTranscriber`).
///
/// Sample buffers stream through `StreamingWAVWriter` rather than being held in
/// memory, so a two-hour film extracts without a RAM spike. The blocking decode
/// runs on a detached task so it never executes on the caller's actor (under the
/// project's approachable-concurrency settings a plain `nonisolated async`
/// function would otherwise inherit the caller's — here the main — executor).
nonisolated enum AudioFileExtractor {
    enum ExtractionError: LocalizedError {
        case noAudioTrack
        case unreadable(String)
        case decodeFailed(String)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                return "That file has no audio to transcribe."
            case .unreadable(let reason):
                return "Couldn't open the file: \(reason)"
            case .decodeFailed(let reason):
                return "Couldn't decode the audio: \(reason)"
            case .writeFailed:
                return "Couldn't write the extracted audio to disk."
            }
        }
    }

    /// Extracts `source`'s audio into a 16 kHz mono WAV at `destination`.
    /// `onProgress` reports 0…1 as decoding advances (by decoded time over total
    /// duration). Throws `ExtractionError` and leaves no partial file behind on
    /// failure. The heavy synchronous decode runs on a detached task, so the main
    /// actor stays responsive while a long file is processed.
    static func extractToWAV(
        source: URL,
        destination: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try await runExtraction(source: source, destination: destination, onProgress: onProgress)
        }.value
    }

    /// The actual decode. Created assets/readers never cross a task boundary, so
    /// no non-`Sendable` AVFoundation type escapes the detached context.
    private static func runExtraction(
        source: URL,
        destination: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        let asset = AVURLAsset(url: source)

        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw ExtractionError.unreadable(error.localizedDescription)
        }
        guard let track = audioTracks.first else { throw ExtractionError.noAudioTrack }

        let cmDuration = (try? await asset.load(.duration)) ?? .zero
        let totalSeconds = cmDuration.seconds.isFinite ? max(cmDuration.seconds, 0) : 0

        let sampleRate = Int(AudioConfig.targetSampleRate)
        // Ask the reader for 16 kHz mono Float32 — it resamples and downmixes for
        // us, so a 48 kHz stereo movie soundtrack arrives in the format the rest
        // of the pipeline expects.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ExtractionError.unreadable(error.localizedDescription)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        guard reader.canAdd(output) else {
            throw ExtractionError.decodeFailed("Unsupported audio format.")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw ExtractionError.decodeFailed(reader.error?.localizedDescription ?? "Reader failed to start.")
        }

        let writer: StreamingWAVWriter
        do {
            writer = try StreamingWAVWriter(url: destination, sampleRate: sampleRate)
        } catch {
            reader.cancelReading()
            throw ExtractionError.writeFailed
        }

        onProgress?(0)
        // Report at most every 0.5% so decoding a long file doesn't fire tens of
        // thousands of progress callbacks (one per sample buffer).
        var lastReported = 0.0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let samples = floatSamples(from: sampleBuffer), !samples.isEmpty {
                writer.append(samples)
            }
            if totalSeconds > 0, let onProgress {
                let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                if seconds.isFinite {
                    let fraction = min(1, max(0, seconds / totalSeconds))
                    if fraction - lastReported >= 0.005 {
                        lastReported = fraction
                        onProgress(fraction)
                    }
                }
            }
        }

        switch reader.status {
        case .completed:
            break
        default:
            writer.discard()
            throw ExtractionError.decodeFailed(reader.error?.localizedDescription ?? "Decoding stopped before the end of the file.")
        }

        onProgress?(1)
        guard writer.finalize() != nil else {
            throw ExtractionError.noAudioTrack
        }
    }

    /// Copies a sample buffer of interleaved Float32 mono PCM into `[Float]`.
    /// Uses the retained-block-buffer accessor so non-contiguous decoder output
    /// is handled correctly (a plain data-pointer read could see only the first
    /// segment).
    private static func floatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.stride,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard let buffer = buffers.first,
              let data = buffer.mData,
              buffer.mDataByteSize > 0 else { return nil }

        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return nil }
        let pointer = data.assumingMemoryBound(to: Float.self)
        // `blockBuffer` owns the memory `pointer` reads. ARC only keeps a local
        // alive to its last *use*, so without this the optimizer could free it
        // before the copy below — a use-after-free on the decoded PCM.
        return withExtendedLifetime(blockBuffer) {
            Array(UnsafeBufferPointer(start: pointer, count: count))
        }
    }
}
