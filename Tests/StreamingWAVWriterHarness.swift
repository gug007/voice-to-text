import Foundation

struct StreamingWAVWriterHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw StreamingWAVWriterHarnessFailure(description: message)
    }
}

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vtt-wav-\(UUID().uuidString).wav")
}

private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

@main
struct StreamingWAVWriterHarness {
    static func main() throws {
        try writesValidHeaderAndData()
        try repairsZeroedHeader()
        try repairRejectsHeaderOnlyFile()
        print("Streaming WAV writer harness passed")
    }

    private static func writesValidHeaderAndData() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try StreamingWAVWriter(url: url, sampleRate: 16_000)
        let count = 16_000  // 1 second
        writer.append([Float](repeating: 0.5, count: count))
        try expect(writer.finalize() != nil, "finalize returns a url when audio was written")

        let data = try Data(contentsOf: url)
        try expect(data.count == 44 + count * 2, "file size == header + data bytes")
        try expect(Array(data[0..<4]) == Array("RIFF".utf8), "RIFF magic present")
        try expect(Array(data[8..<12]) == Array("WAVE".utf8), "WAVE magic present")
        try expect(Array(data[36..<40]) == Array("data".utf8), "data magic present")
        try expect(readUInt32LE(data, 40) == UInt32(count * 2), "data-chunk size patched")
        try expect(readUInt32LE(data, 4) == UInt32(36 + count * 2), "RIFF size patched")
    }

    private static func repairsZeroedHeader() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try StreamingWAVWriter(url: url, sampleRate: 16_000)
        let count = 8_000
        writer.append([Float](repeating: 0.1, count: count))
        _ = writer.finalize()

        // Simulate a crash before finalize: zero the size fields on disk.
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: 4); try handle.write(contentsOf: Data([0, 0, 0, 0]))
        try handle.seek(toOffset: 40); try handle.write(contentsOf: Data([0, 0, 0, 0]))
        try handle.close()
        try expect(readUInt32LE(try Data(contentsOf: url), 40) == 0, "header is zeroed (broken)")

        try expect(StreamingWAVWriter.repairHeaderInPlace(at: url), "repair reports success")
        let data = try Data(contentsOf: url)
        try expect(readUInt32LE(data, 40) == UInt32(count * 2), "data size recovered from file length")
        try expect(readUInt32LE(data, 4) == UInt32(data.count - 8), "RIFF size recovered")
    }

    private static func repairRejectsHeaderOnlyFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try StreamingWAVWriter(url: url, sampleRate: 16_000)
        _ = writer.finalize()  // header only, no samples
        try expect(!StreamingWAVWriter.repairHeaderInPlace(at: url), "header-only file isn't a recoverable recording")
    }
}
