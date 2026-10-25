import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import OSLog
import Synchronization

/// Capture from the microphone picked in Settings through a bare, input-only
/// AUHAL — never AVAudioEngine; `CaptureGraph` says why.
///
/// The unit is bound to its device before it is initialised and has output
/// disabled, so it never comes up on the system default devices first. It
/// also has to do for itself what AVAudioEngine did implicitly:
///
/// - **Configuration changes.** HAL listeners on the pinned device (alive,
///   nominal rate, input stream layout, has-changed) and on the device list
///   post `configurationChangeName`, which the recorder answers through the
///   same restart policy as an engine's. AUHAL does no sample-rate conversion
///   on input, so `prepare(for:)` rebuilds the client format whenever the
///   device's rate moved — a Bluetooth mic's own handsfree switch included.
/// - **A tap.** The I/O thread renders into preallocated memory and hands
///   tap-sized slots to a reader thread, which calls the tap. The real-time
///   thread takes no lock, allocates nothing, and never waits on the
///   recorder.
///
/// Engine-queue only, like every `CaptureGraph`; the hardware is released in
/// `deinit`, through `AudioRecorder.retire(_:)`.
nonisolated final class PinnedInputUnit: CaptureGraph, @unchecked Sendable {
    static let configurationChange = Notification.Name("PinnedInputUnitConfigurationChange")

    let device: AudioDeviceID
    let uid: String

    var configurationChangeName: Notification.Name { Self.configurationChange }
    var configurationChangeObject: AnyObject { signal }
    var binding: PinnedInput? { PinnedInput(uid: uid, device: device) }
    var needsContinuousLivenessCheck: Bool { true }

    private let unit: AudioUnit
    /// The notification sender. A separate object so the listener blocks
    /// never hold the unit itself: one still running when the unit is retired
    /// must not end up being the thing that disposes it.
    private let signal = PinnedInputSignal()
    private let renderer: PinnedInputRenderer
    private let sink = PinnedInputSink()
    private let listeners = HALListenerSet(queue: DispatchQueue(label: "PinnedInputUnit.listener"))
    private var chunkFrames = Int(AudioConfig.tapBufferSize)
    private var initialized = false
    private var running = false

    /// Opens the unit on `device`. Throws if the device cannot be bound — gone
    /// since it was looked up, or refused by the HAL — and the recorder falls
    /// back to the system default rather than failing the take.
    init(_ pinned: PinnedInput) throws {
        self.device = pinned.device
        self.uid = pinned.uid
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw PinnedInputUnitError(step: "find the HAL output unit", status: kAudioUnitErr_InvalidElement)
        }
        var created: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &created), "create the input unit")
        guard let created else {
            throw PinnedInputUnitError(step: "create the input unit", status: kAudioUnitErr_Uninitialized)
        }
        unit = created
        renderer = PinnedInputRenderer(unit: created)
        // Every property is set from here on, so a throw below runs `deinit`,
        // which disposes the instance — never initialised or started, so on
        // the engine queue that is safe.
        //
        // Output off and input on before the device is chosen, so the unit
        // never has a reason to open the default output.
        var on: UInt32 = 1
        var off: UInt32 = 0
        try Self.check(AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, UInt32(MemoryLayout<UInt32>.size)
        ), "enable input")
        try Self.check(AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, UInt32(MemoryLayout<UInt32>.size)
        ), "disable output")
        var id = device
        try Self.check(AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)
        ), "bind the device")
        // The real-time callback. Renders the cycle into the ring's scratch
        // buffer and files it into slots; everything it touches was
        // allocated before I/O started.
        var callback = AURenderCallbackStruct(
            inputProc: { refCon, flags, timestamp, bus, frames, _ in
                let renderer = Unmanaged<PinnedInputRenderer>.fromOpaque(refCon).takeUnretainedValue()
                guard let ring = renderer.ring else { return noErr }
                return ring.render(unit: renderer.unit, flags: flags, timestamp: timestamp, bus: bus, frames: frames)
            },
            inputProcRefCon: Unmanaged.passUnretained(renderer).toOpaque()
        )
        try Self.check(AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        ), "install the input callback")
        installListeners()
    }

    deinit {
        listeners.removeAll()
        if running { AudioOutputUnitStop(unit) }
        if initialized { AudioUnitUninitialize(unit) }
        AudioComponentInstanceDispose(unit)
        renderer.ring?.finish()
    }

    // MARK: - CaptureGraph

    /// Nothing to pay ahead of time: the expensive part of an engine was the
    /// default devices' aggregate, which this unit never builds.
    func warm() {}

    /// Read from the device, not the unit: the unit's view is only refreshed
    /// by initialising it, and the restart path asks before that.
    func hardwareInputFormat() -> CaptureFormat {
        guard InputDeviceCatalog.isAlive(device),
              let rate = InputDeviceCatalog.nominalSampleRate(device) else { return (0, 0) }
        return (rate, InputDeviceCatalog.inputChannelCount(device))
    }

    func installTap(bufferSize: AVAudioFrameCount, _ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        chunkFrames = Int(bufferSize)
        sink.set(handler)
    }

    func removeTap() {
        sink.set(nil)
    }

    /// Brings the unit up at `format`, the device's format as just probed. A
    /// no-op when it is already initialised at that format; otherwise it
    /// re-initialises with a client format at the device's own rate — AUHAL
    /// converts sample format and layout on input, never rate — and a ring
    /// sized for it.
    func prepare(for format: CaptureFormat) throws {
        // The first two channels at most: AUHAL maps device channels into
        // the client format in order, a dictation needs one, and a format of
        // more than two would need a channel layout for nothing.
        let channels = min(format.channelCount, 2)
        if initialized, let ring = renderer.ring,
           ring.sampleRate == format.sampleRate,
           ring.channelCount == channels,
           ring.chunkFrames == chunkFrames {
            return
        }
        if running {
            AudioOutputUnitStop(unit)
            running = false
        }
        if initialized {
            AudioUnitUninitialize(unit)
            initialized = false
        }
        guard let client = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw PinnedInputUnitError(step: "describe the client format", status: kAudioUnitErr_FormatNotSupported)
        }
        var stream = client.streamDescription.pointee
        try Self.check(AudioUnitSetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &stream,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ), "set the client format")
        // The most one callback can hand over: the unit's own slice limit,
        // with headroom over the device's I/O cycle in case that is larger.
        var slice: UInt32 = 0
        var sliceSize = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &slice, &sliceSize)
        let maxFrames = max(Int(slice), Int(InputDeviceCatalog.bufferFrameSize(device) ?? 0) * 2, 4_096)
        guard let ring = PinnedCaptureRing(
            format: client, chunkFrames: chunkFrames, maxFrames: maxFrames, sink: sink
        ) else {
            throw PinnedInputUnitError(step: "allocate the capture ring", status: kAudio_MemFullError)
        }
        try Self.check(AudioUnitInitialize(unit), "initialise the input unit")
        initialized = true
        // Swapped only while I/O is stopped, which is the one moment the
        // real-time thread is guaranteed not to be reading it.
        renderer.ring?.finish()
        renderer.ring = ring
        ring.startReader()
    }

    func start() throws {
        guard initialized, let ring = renderer.ring else { throw AudioRecorderError.inputUnavailable }
        ring.resetWriter()
        try Self.check(AudioOutputUnitStart(unit), "start the input unit")
        running = true
    }

    /// The I/O goes now, on the engine queue; the unit itself goes later,
    /// through `retire`. Left running, a unit replaced by a rebuild kept the
    /// microphone open — and its tap feeding the take — until its grace ran
    /// out.
    func willRetire() {
        removeTap()
        stop()
    }

    /// `AudioOutputUnitStop` returns only once the I/O thread is out of the
    /// callback, so everything after it is single-threaded again. Anything
    /// already handed to the reader is discarded rather than delivered later,
    /// to the next take's tap.
    func stop() {
        guard running else { return }
        AudioOutputUnitStop(unit)
        running = false
        guard let ring = renderer.ring else { return }
        ring.discardPending()
        let dropped = ring.takeDroppedFrames()
        if dropped > 0 {
            AppLog.audio.warning("Pinned capture dropped \(dropped) frames: the reader fell a whole ring behind")
        }
        // A unit that runs but cannot render looks exactly like a silent
        // room from everywhere else; this line is the only thing that tells
        // the two apart.
        if let failure = ring.takeRenderFailures() {
            AppLog.audio.error("Pinned capture failed \(failure.count) render(s) this take (last OSStatus \(failure.lastStatus))")
        }
    }

    // MARK: - Listeners

    /// The pinned device's own changes, plus the device list — an aggregate
    /// being destroyed, or a USB mic pulled, is not reliably announced
    /// through the device's own properties before the object is gone.
    private func installListeners() {
        let signal = signal
        let device = device
        let post: AudioObjectPropertyListenerBlock = { _, _ in
            NotificationCenter.default.post(name: PinnedInputUnit.configurationChange, object: signal)
        }
        let deviceProperties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
            (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
            (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
            (kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput),
            (kAudioDevicePropertyDeviceHasChanged, kAudioObjectPropertyScopeGlobal),
        ]
        for (selector, scope) in deviceProperties {
            listeners.add(on: device, selector, scope, block: post)
        }
        // Every plug and unplug on the machine lands here; only the one that
        // took our device is a change for us.
        let onDeviceList: AudioObjectPropertyListenerBlock = { _, _ in
            guard !InputDeviceCatalog.isAlive(device) else { return }
            NotificationCenter.default.post(name: PinnedInputUnit.configurationChange, object: signal)
        }
        listeners.add(on: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, block: onDeviceList)
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw PinnedInputUnitError(step: step, status: status) }
    }
}

nonisolated struct PinnedInputUnitError: LocalizedError {
    let step: String
    let status: OSStatus

    var errorDescription: String? {
        "Could not \(step) for the selected microphone (OSStatus \(status))."
    }
}

/// The configuration-change sender; carries nothing.
nonisolated final class PinnedInputSignal: Sendable {}

/// Holds the tap. Read by the reader thread for every slot, written by the
/// engine queue on install and removal — never touched by the I/O thread.
nonisolated final class PinnedInputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((AVAudioPCMBuffer) -> Void)?

    func set(_ handler: ((AVAudioPCMBuffer) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    func deliver(_ buffer: AVAudioPCMBuffer) {
        let handler = lock.withLock { self.handler }
        handler?(buffer)
    }
}

/// What the input callback is handed as its refcon. Owned by the unit and
/// outlives every callback: the unit stops I/O before it lets go of it.
nonisolated final class PinnedInputRenderer: @unchecked Sendable {
    let unit: AudioUnit
    /// Replaced only while I/O is stopped.
    var ring: PinnedCaptureRing?

    init(unit: AudioUnit) {
        self.unit = unit
    }
}

/// Preallocated slots between the I/O thread and the reader thread, for one
/// client format. A format change gets a new ring; the old one's reader is
/// told to finish and discards what it had not delivered.
nonisolated final class PinnedCaptureRing: @unchecked Sendable {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let chunkFrames: Int

    private let slots: [AVAudioPCMBuffer]
    private let slotChannels: [[UnsafeMutablePointer<Float>]]
    /// What each cycle is rendered into, sized for the most one callback can
    /// hand over. Held for its memory; the list and channel pointers below are
    /// its own, cached so the real-time thread never messages it.
    private let scratch: AVAudioPCMBuffer
    private let scratchList: UnsafeMutableAudioBufferListPointer
    private let scratchChannels: [UnsafeMutablePointer<Float>]
    private let scratchFrames: Int
    private let sink: PinnedInputSink

    /// I/O thread only, or the engine queue while I/O is stopped.
    private var cursor: CaptureRingCursor
    private let published = Atomic<UInt64>(0)
    private let consumed = Atomic<UInt64>(0)
    /// Slots below this index are dropped by the reader instead of delivered.
    private let discardBelow = Atomic<UInt64>(0)
    private let droppedFrames = Atomic<UInt64>(0)
    private let finished = Atomic<Bool>(false)
    private let renderFailures = Atomic<UInt64>(0)
    private let lastRenderFailure = Atomic<Int32>(0)
    private let wake = DispatchSemaphore(value: 0)

    /// Enough for the reader to fall well over a tenth of a second behind —
    /// a scheduling hiccup, or `handle` rebuilding its converter — without
    /// the I/O thread dropping a frame.
    private static let slotCount = 16

    init?(format: AVAudioFormat, chunkFrames: Int, maxFrames: Int, sink: PinnedInputSink) {
        let channels = Int(format.channelCount)
        guard channels > 0, chunkFrames > 0, maxFrames > 0,
              let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(maxFrames)),
              let scratchData = scratch.floatChannelData else { return nil }
        var slots: [AVAudioPCMBuffer] = []
        var slotChannels: [[UnsafeMutablePointer<Float>]] = []
        for _ in 0..<Self.slotCount {
            guard let slot = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)),
                  let data = slot.floatChannelData else { return nil }
            // Only ever handed over full, so the length is fixed up front and
            // the I/O thread never has to message the buffer.
            slot.frameLength = AVAudioFrameCount(chunkFrames)
            slots.append(slot)
            slotChannels.append((0..<channels).map { data[$0] })
        }
        self.sampleRate = format.sampleRate
        self.channelCount = format.channelCount
        self.chunkFrames = chunkFrames
        self.slots = slots
        self.slotChannels = slotChannels
        self.scratch = scratch
        self.scratchList = UnsafeMutableAudioBufferListPointer(scratch.mutableAudioBufferList)
        self.scratchChannels = (0..<channels).map { scratchData[$0] }
        self.scratchFrames = maxFrames
        self.sink = sink
        self.cursor = CaptureRingCursor(chunkFrames: chunkFrames, slotCount: Self.slotCount)
    }

    /// Real-time. Pulls the cycle with `AudioUnitRender` — the input callback
    /// only announces that data is ready — and files it into slots.
    func render(
        unit: AudioUnit,
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        bus: UInt32,
        frames: UInt32
    ) -> OSStatus {
        let count = Int(frames)
        guard count <= scratchFrames else {
            droppedFrames.wrappingAdd(UInt64(count), ordering: .relaxed)
            return noErr
        }
        // Reset every cycle to our own memory at its full capacity: a render
        // may leave the list pointing at the unit's buffers, and shrinks the
        // sizes to what it wrote. A list sized to the cycle alone, in place of
        // the slice the unit allows, was rejected with -50 on every call.
        for index in 0..<scratchList.count {
            scratchList[index].mData = UnsafeMutableRawPointer(scratchChannels[index])
            scratchList[index].mDataByteSize = UInt32(scratchFrames * MemoryLayout<Float>.size)
        }
        let status = AudioUnitRender(unit, flags, timestamp, bus, frames, scratchList.unsafeMutablePointer)
        guard status == noErr else {
            renderFailures.wrappingAdd(1, ordering: .relaxed)
            lastRenderFailure.store(status, ordering: .relaxed)
            return status
        }

        let outcome = cursor.write(
            frames: count,
            published: published.load(ordering: .relaxed),
            consumed: consumed.load(ordering: .acquiring),
            copy: { slot, slotOffset, sourceOffset, length in
                let destination = self.slotChannels[slot]
                for channel in 0..<self.scratchChannels.count {
                    (destination[channel] + slotOffset)
                        .update(from: self.scratchChannels[channel] + sourceOffset, count: length)
                }
            },
            publish: { _ in
                self.published.wrappingAdd(1, ordering: .releasing)
                self.wake.signal()
            }
        )
        if outcome.dropped > 0 {
            droppedFrames.wrappingAdd(UInt64(outcome.dropped), ordering: .relaxed)
        }
        return noErr
    }

    func startReader() {
        let thread = Thread { [self] in readLoop() }
        thread.name = "PinnedInputUnit.reader"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func readLoop() {
        while true {
            wake.wait()
            while true {
                let next = consumed.load(ordering: .relaxed)
                guard next < published.load(ordering: .acquiring) else { break }
                if !finished.load(ordering: .acquiring), next >= discardBelow.load(ordering: .acquiring) {
                    sink.deliver(slots[Int(next % UInt64(slots.count))])
                }
                consumed.store(next &+ 1, ordering: .releasing)
            }
            if finished.load(ordering: .acquiring) { return }
        }
    }

    /// Engine queue, I/O stopped.
    func resetWriter() {
        cursor.reset()
    }

    /// Engine queue, I/O stopped: whatever is waiting for the reader belongs
    /// to a take that is over.
    func discardPending() {
        discardBelow.store(published.load(ordering: .acquiring), ordering: .releasing)
        cursor.reset()
    }

    func takeDroppedFrames() -> UInt64 {
        droppedFrames.exchange(0, ordering: .relaxed)
    }

    func takeRenderFailures() -> (count: UInt64, lastStatus: OSStatus)? {
        let count = renderFailures.exchange(0, ordering: .relaxed)
        guard count > 0 else { return nil }
        return (count, lastRenderFailure.load(ordering: .relaxed))
    }

    /// Lets the reader thread drain and exit. Called once I/O is stopped for
    /// good, or the ring has been replaced.
    func finish() {
        finished.store(true, ordering: .releasing)
        wake.signal()
    }
}
