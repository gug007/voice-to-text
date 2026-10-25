import CoreAudio
import Foundation

/// Names the capture device for the log.
///
/// Diagnostics only, never a decision input — the pinned-device decision is
/// `InputDeviceCatalog`'s, made on the engine queue. Two reasons this must stay
/// that way. HAL property reads take HAL locks and are documented to block for
/// seconds exactly while a Bluetooth device renegotiates its profile — the one
/// moment we are most curious — so nothing may wait on an answer. And with
/// AirPods the engine is driven through a private aggregate device, so the id
/// it reports is the aggregate's, not the headset's; the UID below is the
/// device we asked for, which is the thing worth recording.
///
/// The app logged nothing about the input device at all before this, which is
/// why the first field investigation had to reconstruct which microphone was
/// involved from Apple's private CoreAudio debug lines.
nonisolated enum AudioDeviceProbe {
    /// e.g. `Gurgen's AirPods (uid=9C-F3-AC-31-D0-6E:input, transport=bluetooth) [system default]`.
    ///
    /// `boundDevice` is the device the capture graph was built for, or `nil`
    /// when it follows the system default; the line says which. A pin that
    /// was not connected has already said so where it was looked up.
    static func captureInputSummary(boundDevice: AudioDeviceID?) -> String {
        if let boundDevice { return "\(summary(of: boundDevice)) [pinned in Settings]" }
        return "\(defaultInputSummary()) [system default]"
    }

    private static func defaultInputSummary() -> String {
        guard let device = InputDeviceCatalog.defaultInputDevice() else { return "none (no default input device)" }
        return summary(of: device)
    }

    private static func summary(of device: AudioDeviceID) -> String {
        let name = InputDeviceCatalog.stringProperty(device, kAudioObjectPropertyName) ?? "unnamed"
        let uid = InputDeviceCatalog.stringProperty(device, kAudioDevicePropertyDeviceUID) ?? "no-uid"
        return "\(name) (uid=\(uid), transport=\(transport(device)))"
    }

    /// Whether a mid-recording renegotiation is expected behaviour for this
    /// device or a genuine surprise — the single most useful field on the line.
    private static func transport(_ device: AudioDeviceID) -> String {
        guard let value = InputDeviceCatalog.transportType(device) else { return "unknown" }
        switch value {
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "bluetooth-le"
        case kAudioDeviceTransportTypeBuiltIn: return "built-in"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return "continuity"
        default: return fourCharCode(value)
        }
    }

    private static func fourCharCode(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        let scalars = bytes.map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : "?" }
        return String(scalars)
    }
}
