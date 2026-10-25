import CoreAudio
import Foundation
import OSLog

/// The HAL reads behind the microphone picker and the pinned-device binding.
///
/// Every function here is a round trip into coreaudiod, and HAL property
/// reads are documented to block for seconds while a Bluetooth device
/// renegotiates its profile. So none of them may run on the main thread:
/// `AudioRecorder` and `PinnedInputUnit` call them on the engine queue,
/// inside the start/restart timeouts, and from the unit's own listener queue;
/// `InputDeviceMonitor` on its own serial queue; `MeetingRecorder` from a
/// detached task.
nonisolated enum InputDeviceCatalog {
    /// The stored preference, resolved to a live device. One UID lookup when
    /// something is pinned, nothing at all when it isn't — the system-default
    /// path stays exactly as cheap as it was before pinning existed.
    ///
    /// A pin that is not connected is logged once here, at `.notice` because
    /// `.info` is not persisted, naming what falls back (`context`); pass
    /// `nil` to resolve quietly.
    static func resolvePinnedInput(logMissingFor context: String?) -> MicrophoneSelection<AudioDeviceID> {
        let stored = MicrophonePreference.stored(in: .standard)
        let selection = MicrophoneSelection.resolve(
            storedUID: stored.uid,
            lastKnownName: stored.lastKnownName
        ) { uid in
            deviceID(forUID: uid)
        }
        if let context, case .missing(let uid, let name) = selection {
            AppLog.audio.notice("Pinned microphone \(name ?? "unnamed", privacy: .public) (uid=\(uid, privacy: .public)) is not connected; \(context, privacy: .public) uses the system default")
        }
        return selection
    }

    /// The input devices a person could choose, in the HAL's order, plus the
    /// name of the current default.
    static func snapshot() -> InputDeviceSnapshot {
        InputDeviceSnapshot(
            devices: inputDevices(),
            defaultInputName: defaultInputDevice().flatMap { stringProperty($0, kAudioObjectPropertyName) }
        )
    }

    static func defaultInputDevice() -> AudioDeviceID? {
        let device = scalar(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultInputDevice,
            as: AudioDeviceID.self
        )
        return device == AudioDeviceID(kAudioObjectUnknown) ? nil : device
    }

    static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        cfProperty(object, selector) as? String
    }

    static func transportType(_ device: AudioDeviceID) -> UInt32? {
        scalar(device, kAudioDevicePropertyTransportType, as: UInt32.self)
    }

    /// False for a device that is going away, and for one that has already
    /// gone — a read that fails is the same answer.
    static func isAlive(_ device: AudioDeviceID) -> Bool {
        scalar(device, kAudioDevicePropertyDeviceIsAlive, as: UInt32.self).map { $0 != 0 } ?? false
    }

    static func nominalSampleRate(_ device: AudioDeviceID) -> Double? {
        scalar(device, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
    }

    /// Channels across every input stream, 0 when the device has none or the
    /// read fails.
    static func inputChannelCount(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + $1.mNumberChannels }
    }

    /// The device's I/O cycle in frames — the most one input callback can
    /// hand over.
    static func bufferFrameSize(_ device: AudioDeviceID) -> UInt32? {
        scalar(device, kAudioDevicePropertyBufferFrameSize, as: UInt32.self)
    }

    /// One fixed-size property, or `nil` when the read fails.
    static func scalar<Value: AdditiveArithmetic>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        as _: Value.Type
    ) -> Value? {
        var address = AudioObjectPropertyAddress(selector, scope)
        var value = Value.zero
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
        }
        return status == noErr ? value : nil
    }

    // MARK: - Private

    /// Existence only, by design. Whether the device has input is settled when
    /// it is pinned — the picker lists nothing else — and re-checking it here
    /// would read stream state in the middle of an AirPods profile switch,
    /// where it flaps, and could turn a 20 ms dip into a mid-take switch to a
    /// different microphone.
    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier: CFString = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &size,
                &device
            )
        }
        // An unknown UID is not an error to the HAL: it answers
        // `kAudioObjectUnknown`, which is the "not connected" case.
        guard status == noErr, device != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// Input-capable, visible, and not somebody's private aggregate. That last
    /// filter matters more than it looks: AVAudioEngine can drive a Bluetooth
    /// input through a private aggregate it creates inside our own process, and
    /// without the filter a take could briefly add that aggregate as a row in
    /// the open picker.
    private static func inputDevices() -> [InputDevice] {
        allDevices().compactMap { device in
            guard hasInputStreams(device), !isHidden(device) else { return nil }
            let transport = transportType(device)
            guard !(transport == kAudioDeviceTransportTypeAggregate && isPrivateAggregate(device)),
                  let uid = stringProperty(device, kAudioDevicePropertyDeviceUID), !uid.isEmpty
            else { return nil }
            return InputDevice(
                uid: uid,
                name: stringProperty(device, kAudioObjectPropertyName) ?? "",
                caption: transport.flatMap(caption(forTransport:))
            )
        }
    }

    /// A CF-typed property, released into Swift's ownership.
    private static func cfProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> CFTypeRef? {
        var address = AudioObjectPropertyAddress(selector)
        var value: Unmanaged<CFTypeRef>?
        var size = UInt32(MemoryLayout<Unmanaged<CFTypeRef>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue()
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        // The list can shrink between the two calls; `size` comes back as what
        // was actually written.
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return Array(devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isHidden(_ device: AudioDeviceID) -> Bool {
        scalar(device, kAudioDevicePropertyIsHidden, as: UInt32.self).map { $0 != 0 } ?? false
    }

    private static func isPrivateAggregate(_ device: AudioDeviceID) -> Bool {
        guard let composition = cfProperty(device, kAudioAggregateDevicePropertyComposition) as? [String: Any] else {
            return false
        }
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }

    /// Coarser than CoreAudio's transport types: the user is choosing a
    /// microphone, and "Bluetooth LE" versus "Bluetooth" is not a distinction
    /// they make. `nil` for anything else — an empty caption beats a made-up
    /// one.
    private static func caption(forTransport transport: UInt32) -> String? {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return "Continuity"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypePCI: return "PCI"
        case kAudioDeviceTransportTypeFireWire: return "FireWire"
        case kAudioDeviceTransportTypeAVB: return "AVB"
        default: return nil
        }
    }
}

nonisolated extension AudioObjectPropertyAddress {
    /// The main element of `selector` in `scope` — the only element this app
    /// ever reads or watches.
    init(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        self.init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

/// HAL property listeners registered on one queue and removed together.
///
/// Each block is stored as the block type itself, so the exact object handed
/// to `AudioObjectAddPropertyListenerBlock` is the one later passed to the
/// remove call — a Swift closure re-bridged at each call site would be a new
/// block every time, and the HAL would never find it to remove. Only adds the
/// HAL accepted are recorded. Not thread-safe: the owner confines it.
nonisolated final class HALListenerSet {
    let queue: DispatchQueue
    private var records: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func add(
        on object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = AudioObjectPropertyAddress(selector, scope)
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        guard status == noErr else {
            AppLog.audio.error("Could not watch audio property \(selector) on object \(object) (OSStatus \(status))")
            return
        }
        records.append((object, address, block))
    }

    func removeAll() {
        for record in records {
            var address = record.address
            AudioObjectRemovePropertyListenerBlock(record.object, &address, queue, record.block)
        }
        records.removeAll()
    }
}
