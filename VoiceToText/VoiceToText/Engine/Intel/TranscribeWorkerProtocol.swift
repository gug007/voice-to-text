#if arch(x86_64)
import Foundation

/// The wire protocol between the app (`TranscribeSupervisor`) and its
/// transcribe.cpp worker process (`TranscribeWorker`).
///
/// Strict request and response over the worker's stdin and stdout: every
/// request but `cancel` gets exactly one response, in order. Each message is
/// one frame, `[u32 json length][json][u32 pcm length][pcm bytes]`, lengths
/// little-endian and PCM as little-endian Float32. The JSON says what to do;
/// the PCM is the audio of a `transcribe` and empty otherwise. stderr carries
/// the worker's and the native libraries' log lines.
nonisolated enum TranscribeWorkerProtocol {
    /// The hidden first argument that turns the app's executable into a worker.
    static let workerFlag = "--transcribe-worker"
    /// Worker argument: register only the CPU backends, so no GPU driver code
    /// runs in the process at all.
    static let cpuOnlyFlag = "--cpu-only"
    /// Bumped whenever a message changes shape. A worker started from an app
    /// that was updated in place would be the new build; its hello says so.
    static let version = 1
    /// Prefix on the worker's own stderr lines, so the parent can tell them
    /// from raw native output (a `GGML_ASSERT` right before an abort).
    static let logLinePrefix = "\u{1}"

    /// Refuses frames larger than this, so a garbage length can't become a
    /// multi-gigabyte allocation. Two hours of 16 kHz Float32 audio is 460 MB.
    static let maxSectionBytes = 1 << 30

    enum FramingError: LocalizedError {
        case sectionTooLarge(Int)
        case truncated
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .sectionTooLarge(let bytes):
                return "A worker message of \(bytes) bytes is over the \(maxSectionBytes)-byte limit."
            case .truncated:
                return "A worker message ended part way."
            case .malformed(let reason):
                return "A worker message couldn't be read: \(reason)"
            }
        }
    }

    // MARK: - Messages

    struct Request: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            /// The first request to every worker, answered once the backends
            /// are registered, with the compute devices.
            case hello
            /// Load `modelPath`, freeing whatever model was loaded.
            case load
            /// Transcribe the frame's PCM with `run`.
            case transcribe
            /// Stop the transcription in progress. Read by the worker's stdin
            /// thread as it arrives and never answered: the transcription it
            /// stops answers `aborted`.
            case cancel
            /// Free the model.
            case unload
        }

        var kind: Kind
        var modelPath: String? = nil
        /// CPU threads for the ops that run on the CPU.
        var threads: Int? = nil
        var run: RunOptions? = nil
    }

    /// What a transcription asks for beyond the audio. The Whisper fields are
    /// ignored for other families.
    struct RunOptions: Codable, Sendable, Equatable {
        /// Nil detects the language, where the model can.
        var language: String? = nil
        /// Context for the decoder: the user's hint and the committed tail.
        var prompt: String? = nil
        /// Whisper with no timestamp tokens. Only for audio that fits one 30 s
        /// window: past that, Whisper moves on by its timestamps.
        var withoutTimestamps: Bool = false
        var temperatureIncrement: Float? = nil
        var compressionRatioThreshold: Float? = nil
        var logProbThreshold: Float? = nil
        var noSpeechThreshold: Float? = nil
    }

    struct Response: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case hello
            case loaded
            case transcript
            case ok
            /// The transcription was stopped by a `cancel`.
            case aborted
            case error
        }

        var kind: Kind
        var version: Int? = nil
        var devices: [Device]? = nil
        var loaded: Loaded? = nil
        var transcript: Transcript? = nil
        var message: String? = nil
        /// transcribe.cpp said its backend failed (`TRANSCRIBE_ERR_BACKEND`):
        /// the GPU's fault when the model is on one, and recoverable on the CPU.
        var isBackendFailure: Bool? = nil
    }

    struct Device: Codable, Sendable, Equatable {
        var name: String
        var description: String
        /// transcribe.cpp's vendor kind: "cpu", "metal", "accel", …
        var kind: String
        var isGPU: Bool
        var memoryBytes: UInt64
    }

    /// What the app needs to know about a loaded model.
    struct Loaded: Codable, Sendable, Equatable {
        var architecture: String
        /// The backend the model landed on, as transcribe.cpp names it.
        var backend: String
        /// The device it runs on, e.g. "AMD Radeon Pro 5500M" or the CPU's name.
        var device: String
        /// Whether that device is a GPU, so a crash there may be the GPU's fault.
        var onGPU: Bool
        var loadMilliseconds: Double
    }

    struct Transcript: Codable, Sendable, Equatable {
        var text: String
        /// The language the model detected, when it was asked to detect one.
        var language: String?
        var melMilliseconds: Double
        var encodeMilliseconds: Double
        var decodeMilliseconds: Double
    }

    // MARK: - Framing

    static func encode<Message: Encodable>(_ message: Message, pcm: [Float] = []) throws -> Data {
        let json = try JSONEncoder().encode(message)
        let pcmBytes = pcm.count * MemoryLayout<Float>.size
        guard json.count <= maxSectionBytes else { throw FramingError.sectionTooLarge(json.count) }
        guard pcmBytes <= maxSectionBytes else { throw FramingError.sectionTooLarge(pcmBytes) }
        var frame = Data(capacity: 8 + json.count + pcmBytes)
        appendLength(json.count, to: &frame)
        frame.append(json)
        appendLength(pcmBytes, to: &frame)
        // Float32 is little-endian on every Mac this runs on.
        pcm.withUnsafeBytes { frame.append(contentsOf: $0) }
        return frame
    }

    /// Reads one frame from `fd`, blocking. Nil on a clean end of file before
    /// the first byte of a frame; a frame cut off part way throws.
    static func read<Message: Decodable>(_ type: Message.Type, from fd: Int32) throws -> (Message, [Float])? {
        guard let jsonLength = try readLength(from: fd, eofAllowed: true) else { return nil }
        let json = try readExactly(jsonLength, from: fd)
        let message: Message
        do {
            message = try JSONDecoder().decode(Message.self, from: json)
        } catch {
            throw FramingError.malformed(error.localizedDescription)
        }
        guard let pcmLength = try readLength(from: fd, eofAllowed: false) else { throw FramingError.truncated }
        guard pcmLength % MemoryLayout<Float>.size == 0 else {
            throw FramingError.malformed("the audio isn't a whole number of samples")
        }
        var pcm = [Float](repeating: 0, count: pcmLength / MemoryLayout<Float>.size)
        try pcm.withUnsafeMutableBytes { try readExactly(into: $0, from: fd) }
        return (message, pcm)
    }

    /// Writes all of `data` to `fd`, blocking. False if the other end is gone.
    @discardableResult
    static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer -> Bool in
            guard var pointer = buffer.baseAddress else { return true }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                pointer += written
                remaining -= written
            }
            return true
        }
    }

    private static func appendLength(_ length: Int, to data: inout Data) {
        withUnsafeBytes(of: UInt32(length).littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readLength(from fd: Int32, eofAllowed: Bool) throws -> Int? {
        var raw: UInt32 = 0
        let complete = try withUnsafeMutableBytes(of: &raw) { buffer -> Bool in
            let filled = try readFully(into: buffer, from: fd)
            if filled == 0 && eofAllowed { return false }
            guard filled == buffer.count else { throw FramingError.truncated }
            return true
        }
        guard complete else { return nil }
        let length = Int(UInt32(littleEndian: raw))
        guard length <= maxSectionBytes else { throw FramingError.sectionTooLarge(length) }
        return length
    }

    private static func readExactly(_ count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { try readExactly(into: $0, from: fd) }
        return data
    }

    private static func readExactly(into buffer: UnsafeMutableRawBufferPointer, from fd: Int32) throws {
        guard try readFully(into: buffer, from: fd) == buffer.count else { throw FramingError.truncated }
    }

    /// Fills `buffer` unless the file ends first. Returns the bytes read.
    private static func readFully(into buffer: UnsafeMutableRawBufferPointer, from fd: Int32) throws -> Int {
        guard let base = buffer.baseAddress else { return 0 }
        var filled = 0
        while filled < buffer.count {
            let count = Darwin.read(fd, base + filled, buffer.count - filled)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw FramingError.malformed(String(cString: strerror(errno)))
            }
            filled += count
        }
        return filled
    }
}
#endif
