import AVFoundation
import Foundation

nonisolated final class LiveAudioDecoder {
    enum Failure: Error {
        case unsupportedFormat
        case decode(String)
    }

    let output: AVAudioFormat
    private let input: AVAudioFormat
    private let converter: AVAudioConverter
    private let packet: AVAudioCompressedBuffer
    private var lastSequence: UInt32?

    init(header: LiveAudioStreamHeader) throws {
        guard header.codec == .aacLC, header.sampleRate > 0, header.channels > 0 else { throw Failure.unsupportedFormat }
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(header.sampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(LiveAudioWire.samplesPerPacket),
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(header.channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let input = AVAudioFormat(streamDescription: &description),
              let output = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(header.sampleRate),
                  channels: AVAudioChannelCount(header.channels),
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: input, to: output)
        else { throw Failure.unsupportedFormat }
        self.input = input
        self.output = output
        self.converter = converter
        packet = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: LiveAudioWire.maxPayload)
    }

    func decode(_ frame: LiveAudioFrame) throws -> AVAudioPCMBuffer? {
        let payload = frame.payload
        guard !payload.isEmpty, payload.count <= LiveAudioWire.maxPayload else { return nil }
        if let lastSequence, frame.sequence != lastSequence &+ 1 { converter.reset() }
        lastSequence = frame.sequence
        payload.copyBytes(to: packet.data.assumingMemoryBound(to: UInt8.self), count: payload.count)
        packet.byteLength = UInt32(payload.count)
        packet.packetCount = 1
        packet.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 0,
            mDataByteSize: UInt32(payload.count)
        )
        guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(LiveAudioWire.samplesPerPacket * 2)) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { [packet] _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return packet
        }
        if status == .error {
            converter.reset()
            throw Failure.decode(error?.localizedDescription ?? "unknown")
        }
        return pcm.frameLength > 0 ? pcm : nil
    }
}
