import AVFoundation
import Foundation
import OSLog

nonisolated final class LiveAudioAACEncoder: LiveAudioEncoding {
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let inputBuffer: AVAudioPCMBuffer
    private let outputBuffer: AVAudioCompressedBuffer
    private var pending: [Float] = []
    private var pendingStart = 0

    init?() {
        guard let input = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(LiveAudioWire.sampleRate),
            channels: AVAudioChannelCount(LiveAudioWire.channels),
            interleaved: false
        ) else { return nil }
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(LiveAudioWire.sampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(LiveAudioWire.samplesPerPacket),
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(LiveAudioWire.channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let output = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: input, to: output),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(LiveAudioWire.samplesPerPacket))
        else { return nil }
        converter.bitRate = Self.closestBitRate(to: LiveAudioWire.bitRate, in: converter.applicableEncodeBitRates)
        let packetSize = max(converter.maximumOutputPacketSize, 2048)
        self.converter = converter
        self.inputFormat = input
        self.inputBuffer = inputBuffer
        self.outputBuffer = AVAudioCompressedBuffer(format: output, packetCapacity: 8, maximumPacketSize: packetSize)
    }

    func encode(_ samples: [Float]) -> [Data] {
        pending.append(contentsOf: samples)
        var packets: [Data] = []
        while pending.count - pendingStart >= LiveAudioWire.samplesPerPacket {
            outputBuffer.packetCount = 0
            outputBuffer.byteLength = 0
            var failure: NSError?
            let status = converter.convert(to: outputBuffer, error: &failure) { [self] _, inputStatus in
                guard pending.count - pendingStart >= LiveAudioWire.samplesPerPacket else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                fillInput()
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error {
                AppLog.remote.error("Live audio encode failed: \(failure?.localizedDescription ?? "unknown", privacy: .public)")
                pending.removeAll(keepingCapacity: true)
                pendingStart = 0
                return packets
            }
            packets.append(contentsOf: extractPackets())
            if outputBuffer.packetCount == 0 { break }
        }
        if pendingStart > 0 {
            pending.removeFirst(pendingStart)
            pendingStart = 0
        }
        return packets
    }

    private func fillInput() {
        let count = LiveAudioWire.samplesPerPacket
        guard let channel = inputBuffer.floatChannelData?[0] else { return }
        pending.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress! + pendingStart, count: count)
        }
        inputBuffer.frameLength = AVAudioFrameCount(count)
        pendingStart += count
    }

    private func extractPackets() -> [Data] {
        let count = Int(outputBuffer.packetCount)
        guard count > 0, let descriptions = outputBuffer.packetDescriptions else { return [] }
        var packets: [Data] = []
        packets.reserveCapacity(count)
        for index in 0..<count {
            let description = descriptions[index]
            let size = Int(description.mDataByteSize)
            guard size > 0, size <= LiveAudioWire.maxPayload else { continue }
            packets.append(Data(bytes: outputBuffer.data + Int(description.mStartOffset), count: size))
        }
        return packets
    }

    private static func closestBitRate(to wanted: Int, in available: [NSNumber]?) -> Int {
        let rates = (available ?? []).map(\.intValue).filter { $0 > 0 }
        guard !rates.isEmpty else { return wanted }
        return rates.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
    }
}

extension LiveAudioHub {
    nonisolated static let shared = LiveAudioHub(
        makeEncoder: { LiveAudioAACEncoder() },
        onListenerCountChange: {
            Task { @MainActor in RemoteControlController.shared.refreshLiveListeners() }
        }
    )
}
