import CoreAudio
import Foundation

/// Names the default input device for the log.
///
/// Diagnostics only, never a decision input. Two reasons it must stay that
/// way. HAL property reads take HAL locks and are documented to block for
/// seconds exactly while a Bluetooth device renegotiates its profile — the one
/// moment we are most curious — so nothing may wait on an answer. And with
/// AirPods the engine is driven through a private aggregate device, so the id
/// it reports is the aggregate's, not the headset's; the UID below is the
/// system's default input, which is the thing worth recording.
///
/// The app logged nothing about the input device at all before this, which is
/// why the first field investigation had to reconstruct which microphone was
/// involved from Apple's private CoreAudio debug lines.
nonisolated enum AudioDeviceProbe {
    /// e.g. `Gurgen's AirPods (uid=9C-F3-AC-31-D0-6E:input, transport=bluetooth)`.
    static func defaultInputSummary() -> String {
        guard let device = defaultInputDevice() else { return "none (no default input device)" }
        let name = stringProperty(device, kAudioObjectPropertyName) ?? "unnamed"
        let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) ?? "no-uid"
        return "\(name) (uid=\(uid), transport=\(transport(device)))"
    }

    private static func defaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func stringProperty(
        _ device: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// Whether a mid-recording renegotiation is expected behaviour for this
    /// device or a genuine surprise — the single most useful field on the line.
    private static func transport(_ device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return "unknown"
        }
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
