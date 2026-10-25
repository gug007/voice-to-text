import AVFoundation
import CoreAudio
import Foundation

/// Exactly what `AudioRecorder` needs from whatever is capturing: the
/// hardware's input format, a tap, and start/stop. Two implementations:
///
/// - `EngineCaptureGraph`, AVAudioEngine on the system default input — the
///   path the app has always had, unchanged.
/// - `PinnedInputUnit`, a bare input-only AUHAL bound to the microphone picked
///   in Settings.
///
/// The split exists because AVAudioEngine cannot capture from a chosen device
/// without first coming up on the default ones: its I/O unit is created on a
/// private aggregate of the default input and output, so with AirPods as the
/// default both ways, merely building an engine asks bluetoothd for a
/// handsfree route — and pinning it elsewhere afterwards tears that down
/// under whatever the user is listening to, measured as paused playback and,
/// twice, AirPods dropping off CoreAudio altogether. It also never reports
/// the bound device dying, and drifts back to the default after a route
/// change. An AUHAL bound before it is initialised creates no aggregate and
/// produces no SCO traffic at all.
///
/// Every member is a CoreAudio round trip and is called on `AudioRecorder`'s
/// engine queue only. Implementations release their hardware when their last
/// reference goes, which `AudioRecorder.retire(_:)` makes happen off the main
/// thread, outside every lock, and after the burst of notifications that may
/// still be riding on them — so no listener or callback is left holding
/// hardware that has been released.
nonisolated protocol CaptureGraph: AnyObject {
    /// Posted, on any thread, when the graph's input configuration changed —
    /// Apple's "re-wire and start again" signal. The recorder observes it on
    /// the main queue with `configurationChangeObject` as the sender.
    var configurationChangeName: Notification.Name { get }
    var configurationChangeObject: AnyObject { get }
    /// The microphone this graph was built for; `nil` for the system default.
    /// Fixed for the graph's life, so reading it is never a CoreAudio call.
    var binding: PinnedInput? { get }
    /// Whether capture has to be watched for as long as it runs. AVAudioEngine
    /// stops itself and says so when its input changes; a bare unit whose
    /// device vanishes may simply stop calling back.
    var needsContinuousLivenessCheck: Bool { get }

    /// Pays the expensive part of bringing the graph up ahead of a take.
    func warm()
    /// The input hardware's current rate and channel count; zero for either
    /// when the input is unavailable, which is Apple's own test for "input is
    /// not enabled".
    func hardwareInputFormat() -> CaptureFormat
    /// Delivers captured buffers, in the hardware's format, on a thread that
    /// is not the real-time one. Replaces any tap already installed. Like
    /// AVAudioEngine's, removing a tap does not wait for a delivery in flight.
    func installTap(bufferSize: AVAudioFrameCount, _ handler: @escaping (AVAudioPCMBuffer) -> Void)
    func removeTap()
    /// `format` is the hardware format the caller has just probed and found
    /// usable, so it need not be read again.
    func prepare(for format: CaptureFormat) throws
    func start() throws
    func stop()
    /// Called on the engine queue just before the graph is handed to
    /// `retire`, for whatever must not outlive that moment.
    func willRetire()
}

typealias CaptureFormat = (sampleRate: Double, channelCount: AVAudioChannelCount)

/// A microphone picked in Settings and connected right now. The UID is what
/// was chosen; the device id is what it resolved to for this build of the
/// graph, so a mic unplugged and replugged — same UID, new id — never
/// matches a graph still bound to the id it had before.
nonisolated struct PinnedInput: Equatable, Sendable {
    let uid: String
    let device: AudioDeviceID
}

/// AVAudioEngine on the system default input, wrapped without changing a
/// single call it makes.
nonisolated final class EngineCaptureGraph: CaptureGraph, @unchecked Sendable {
    let engine = AVAudioEngine()

    var configurationChangeName: Notification.Name { .AVAudioEngineConfigurationChange }
    var configurationChangeObject: AnyObject { engine }
    var binding: PinnedInput? { nil }
    var needsContinuousLivenessCheck: Bool { false }

    /// Touching `inputNode` is what triggers the HAL enumeration.
    func warm() {
        _ = engine.inputNode
    }

    func hardwareInputFormat() -> CaptureFormat {
        let format = engine.inputNode.inputFormat(forBus: 0)
        return (format.sampleRate, format.channelCount)
    }

    func installTap(bufferSize: AVAudioFrameCount, _ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            handler(buffer)
        }
    }

    func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    /// The engine reads its own format; the probed one is not needed.
    func prepare(for format: CaptureFormat) throws {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    /// Nothing: an engine has always been retired as it stood, and stops
    /// itself as it deallocates.
    func willRetire() {}
}
