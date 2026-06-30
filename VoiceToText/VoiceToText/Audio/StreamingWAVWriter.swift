import Foundation

/// Incrementally writes mono Float32 PCM samples (range -1…1) to a 16-bit
/// little-endian WAV file on disk, so an hour-long meeting streams to storage
/// instead of being held in RAM. The 44-byte header is written up front with
/// placeholder sizes and patched with the real lengths on `finalize()`.
///
/// Not thread-safe: drive it from a single serial queue (the recorder's audio
/// processing queue). `nonisolated` so it runs off the main actor.
nonisolated final class StreamingWAVWriter {
    let url: URL
    private let sampleRate: Int
    private let handle: FileHandle
    private(set) var totalSamples: Int = 0
    private var finalized = false
    /// Set once a write throws (e.g. disk full). FileHandle.write isn't
    /// guaranteed all-or-nothing, so a partial write could byte-misalign the
    /// rest of the file — stop appending entirely and keep what's aligned.
    private var writeFailed = false
    private var samplesSinceHeaderSync = 0

    private static let headerSize = WAVEncoder.headerSize
    private static let bytesPerSample = 2

    init(url: URL, sampleRate: Int) throws {
        self.url = url
        self.sampleRate = sampleRate
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: WAVEncoder.header(sampleRate: sampleRate, dataSize: 0))
    }

    /// Appends one buffer of samples, converting Float32 → Int16 LE.
    func append(_ samples: [Float]) {
        guard !finalized, !writeFailed, !samples.isEmpty else { return }
        do {
            try handle.write(contentsOf: WAVEncoder.int16LEData(from: samples))
            totalSamples += samples.count
            // Periodically patch the header so a crash / force-quit / power loss
            // during a long meeting loses at most a few seconds — without this
            // the data-chunk size stays 0 until finalize() and the whole file
            // reads as empty. Seek back to the end afterwards so the next append
            // doesn't clobber the header.
            samplesSinceHeaderSync += samples.count
            if samplesSinceHeaderSync >= sampleRate * 5 {
                samplesSinceHeaderSync = 0
                try patchSizes()
                try handle.seek(toOffset: UInt64(Self.headerSize + totalSamples * Self.bytesPerSample))
            }
        } catch {
            writeFailed = true
        }
    }

    /// Patches the RIFF + data chunk sizes to match what was written and closes
    /// the file. Returns the playable WAV's URL, or nil if nothing was written.
    @discardableResult
    func finalize() -> URL? {
        guard !finalized else { return totalSamples > 0 ? url : nil }
        finalized = true
        do {
            try patchSizes()
            try handle.close()
        } catch {
            try? handle.close()
            return nil
        }
        return totalSamples > 0 ? url : nil
    }

    private func patchSizes() throws {
        let dataSize = totalSamples * Self.bytesPerSample
        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: WAVEncoder.uint32LE(UInt32(Self.headerSize - 8 + dataSize)))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: WAVEncoder.uint32LE(UInt32(dataSize)))
    }

    /// Recovers a WAV left with a placeholder (0-length) data chunk by an
    /// interrupted recording: rewrites the RIFF + data sizes from the file's
    /// actual byte count so the audio becomes playable/decodable. Returns true
    /// when the repaired file holds real audio. Used by launch-time recovery.
    @discardableResult
    static func repairHeaderInPlace(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > UInt64(headerSize) else { return false }
        let dataSize = Int(size) - headerSize
        do {
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: WAVEncoder.uint32LE(UInt32(headerSize - 8 + dataSize)))
            try handle.seek(toOffset: 40)
            try handle.write(contentsOf: WAVEncoder.uint32LE(UInt32(dataSize)))
        } catch {
            return false
        }
        return dataSize > 0
    }

    /// Closes and deletes the file without finalizing — for cancelled recordings.
    func discard() {
        finalized = true
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }

    var durationSeconds: Double {
        sampleRate > 0 ? Double(totalSamples) / Double(sampleRate) : 0
    }
}
