import Foundation

nonisolated enum LiveAudioWire {
    static let magic: [UInt8] = Array("VTLA".utf8)
    static let version: UInt8 = 1
    static let headerLength = 12
    static let frameHeaderLength = 6
    static let maxPayload = 8192
    static let sampleRate = 16_000
    static let channels = 1
    static let samplesPerPacket = 1024
    static let bitRate = 32_000
    static let contentType = "application/octet-stream"
    static let maxListeners = 2
}

nonisolated enum LiveAudioCodec: UInt8, Sendable {
    case aacLC = 1
}

nonisolated struct LiveAudioStreamHeader: Equatable, Sendable {
    var codec: LiveAudioCodec
    var sampleRate: Int
    var channels: Int

    static let standard = LiveAudioStreamHeader(
        codec: .aacLC,
        sampleRate: LiveAudioWire.sampleRate,
        channels: LiveAudioWire.channels
    )

    func encoded() -> Data {
        var bytes = LiveAudioWire.magic
        bytes.append(LiveAudioWire.version)
        bytes.append(codec.rawValue)
        bytes.append(UInt8(clamping: channels))
        bytes.append(0)
        let rate = UInt32(clamping: sampleRate)
        bytes.append(UInt8(truncatingIfNeeded: rate >> 24))
        bytes.append(UInt8(truncatingIfNeeded: rate >> 16))
        bytes.append(UInt8(truncatingIfNeeded: rate >> 8))
        bytes.append(UInt8(truncatingIfNeeded: rate))
        return Data(bytes)
    }
}

nonisolated struct LiveAudioFrame: Equatable, Sendable {
    let sequence: UInt32
    let payload: Data

    func encoded() -> Data {
        var bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: sequence >> 24),
            UInt8(truncatingIfNeeded: sequence >> 16),
            UInt8(truncatingIfNeeded: sequence >> 8),
            UInt8(truncatingIfNeeded: sequence),
            UInt8(truncatingIfNeeded: payload.count >> 8),
            UInt8(truncatingIfNeeded: payload.count),
        ]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }
}

nonisolated struct LiveAudioStreamParser: Sendable {
    enum Failure: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt8)
        case unsupportedCodec(UInt8)
        case oversizedFrame(Int)
    }

    private(set) var header: LiveAudioStreamHeader?
    private var buffer: [UInt8] = []

    init() {}

    mutating func append(_ data: Data) throws -> [LiveAudioFrame] {
        buffer.append(contentsOf: data)
        var offset = 0
        if header == nil {
            guard buffer.count >= LiveAudioWire.headerLength else { return [] }
            guard Array(buffer[0..<4]) == LiveAudioWire.magic else { throw Failure.badMagic }
            guard buffer[4] == LiveAudioWire.version else { throw Failure.unsupportedVersion(buffer[4]) }
            guard let codec = LiveAudioCodec(rawValue: buffer[5]) else { throw Failure.unsupportedCodec(buffer[5]) }
            let rate = Int(buffer[8]) << 24 | Int(buffer[9]) << 16 | Int(buffer[10]) << 8 | Int(buffer[11])
            header = LiveAudioStreamHeader(codec: codec, sampleRate: rate, channels: Int(buffer[6]))
            offset = LiveAudioWire.headerLength
        }
        var frames: [LiveAudioFrame] = []
        while buffer.count - offset >= LiveAudioWire.frameHeaderLength {
            let sequence = UInt32(buffer[offset]) << 24 | UInt32(buffer[offset + 1]) << 16
                | UInt32(buffer[offset + 2]) << 8 | UInt32(buffer[offset + 3])
            let length = Int(buffer[offset + 4]) << 8 | Int(buffer[offset + 5])
            guard length <= LiveAudioWire.maxPayload else { throw Failure.oversizedFrame(length) }
            let start = offset + LiveAudioWire.frameHeaderLength
            guard buffer.count - start >= length else { break }
            frames.append(LiveAudioFrame(sequence: sequence, payload: Data(buffer[start..<(start + length)])))
            offset = start + length
        }
        if offset > 0 { buffer.removeFirst(offset) }
        return frames
    }
}
