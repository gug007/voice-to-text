import Accelerate
import AVFoundation
import Foundation

enum WaveformStore {
    nonisolated static let peakCount = 180
    private static var memory: [String: [Float]] = [:]

    static func cached(_ url: URL) -> [Float]? {
        key(for: url).flatMap { memory[$0] }
    }

    static func peaks(for url: URL) async -> [Float]? {
        guard let key = key(for: url) else { return nil }
        if let hit = memory[key] { return hit }
        let result = await Task.detached(priority: .utility) {
            await WaveformReader.peaks(url: url, key: key, count: peakCount)
        }.value
        if let result { memory[key] = result }
        return result
    }

    private static func key(for url: URL) -> String? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else { return nil }
        return "\(url.deletingPathExtension().lastPathComponent)-\(size)"
    }
}

nonisolated enum WaveformReader {
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Waveforms", isDirectory: true)
    }

    static func peaks(url: URL, key: String, count: Int) async -> [Float]? {
        let file = directory.appendingPathComponent("\(key).peaks")
        if let data = try? Data(contentsOf: file), data.count == count * MemoryLayout<Float>.size {
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        guard let peaks = await read(url: url, count: count), !Task.isCancelled else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? peaks.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file, options: .atomic)
        return peaks
    }

    private static func read(url: URL, count: Int) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard
            let track = try? await asset.loadTracks(withMediaType: .audio).first,
            let duration = try? await asset.load(.duration).seconds,
            duration.isFinite, duration > 0,
            let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        let formats = (try? await track.load(.formatDescriptions)) ?? []
        let sampleRate = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 16_000

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let framesPerBucket = max(1, Int((duration * sampleRate / Double(count)).rounded(.up)))
        var energy = [Double](repeating: 0, count: count)
        var frames = [Int](repeating: 0, count: count)
        var samples: [Float] = []
        var index = 0
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let available = length / MemoryLayout<Float>.size
            guard available > 0 else { continue }
            if samples.count < available { samples = [Float](repeating: 0, count: available) }
            let copied = samples.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: available * MemoryLayout<Float>.size, destination: $0.baseAddress!)
            }
            guard copied == noErr else { continue }
            var offset = 0
            samples.withUnsafeBufferPointer { pointer in
                while offset < available {
                    let bucket = min(index / framesPerBucket, count - 1)
                    let room = bucket == count - 1 ? available - offset : framesPerBucket - index % framesPerBucket
                    let take = min(room, available - offset)
                    var sum: Float = 0
                    vDSP_svesq(pointer.baseAddress! + offset, 1, &sum, vDSP_Length(take))
                    energy[bucket] += Double(sum)
                    frames[bucket] += take
                    offset += take
                    index += take
                }
            }
        }
        guard reader.status == .completed else { return nil }

        let levels = zip(energy, frames).map { $1 > 0 ? Float(($0 / Double($1)).squareRoot()) : 0 }
        guard let loudest = levels.max(), loudest > 0 else { return levels }
        return levels.map { pow($0 / loudest, 0.7) }
    }
}
