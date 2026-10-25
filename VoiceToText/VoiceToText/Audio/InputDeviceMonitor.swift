import CoreAudio
import Foundation
import Observation
import OSLog

/// The input devices on this Mac, kept current for the Settings microphone
/// picker while it is on screen.
///
/// Listening only while someone is looking is deliberate, not tidiness. The
/// device list can change on every take that runs through a private
/// aggregate — AVAudioEngine creates those in our own process — so a listener
/// left on for the app's lifetime would re-enumerate the HAL in the middle of
/// a recording's start, contending for the locks the engine is negotiating
/// with. One shared instance, reference-counted by `observe()`, so reopening
/// the pane never stacks a second set of listeners.
@Observable
@MainActor
final class InputDeviceMonitor {
    static let shared = InputDeviceMonitor()

    /// `nil` until the first enumeration lands, so the picker never claims a
    /// pinned device is disconnected just because nothing has been read yet.
    private(set) var snapshot: InputDeviceSnapshot?

    @ObservationIgnored private var activations = 0
    @ObservationIgnored private let listener = InputDeviceListener()

    private init() {}

    /// Listens for as long as the calling task runs — a view's `.task`, which
    /// SwiftUI cancels as the view goes away. Tying the listeners to a task's
    /// lifetime rather than to an appear/disappear pair means an unbalanced
    /// pair can never leave them on for the life of the app.
    func observe() async {
        activations += 1
        if activations == 1 {
            listener.start { snapshot in
                Task { @MainActor in InputDeviceMonitor.shared.apply(snapshot) }
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3_600))
        }
        activations -= 1
        if activations == 0 { listener.stop() }
    }

    private func apply(_ snapshot: InputDeviceSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}

/// Owns the CoreAudio listeners behind `InputDeviceMonitor`. Every HAL call —
/// adding and removing the listeners included — runs on `queue`, never on the
/// main thread, and so does every read and write of the state below; that
/// confinement is what the `@unchecked Sendable` stands for.
nonisolated final class InputDeviceListener: @unchecked Sendable {
    private let listeners = HALListenerSet(queue: DispatchQueue(label: "InputDeviceListener", qos: .utility))
    private var queue: DispatchQueue { listeners.queue }
    /// Plugging in a Bluetooth headset posts several device-list and
    /// default-device changes within a few hundred milliseconds. One
    /// enumeration after the burst is all the picker needs.
    private static let debounce: DispatchTimeInterval = .milliseconds(250)

    private static let watched: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice,
    ]

    private var onChange: (@Sendable (InputDeviceSnapshot) -> Void)?
    private var pendingRefresh: DispatchWorkItem?

    func start(onChange: @escaping @Sendable (InputDeviceSnapshot) -> Void) {
        queue.async {
            guard self.onChange == nil else { return }
            self.onChange = onChange
            // Strong on purpose: the HAL holds the block only until `stop()`
            // removes it, and this object lives as long as the shared monitor.
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                self.scheduleRefresh()
            }
            for selector in Self.watched {
                self.listeners.add(on: AudioObjectID(kAudioObjectSystemObject), selector, block: block)
            }
            self.refresh()
        }
    }

    func stop() {
        queue.async {
            self.pendingRefresh?.cancel()
            self.pendingRefresh = nil
            self.onChange = nil
            self.listeners.removeAll()
        }
    }

    /// Called on `queue` — the listener blocks are registered on it.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = item
        queue.asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }

    private func refresh() {
        pendingRefresh = nil
        // Re-checked so a refresh queued just before `stop()` reads nothing.
        guard let onChange else { return }
        onChange(InputDeviceCatalog.snapshot())
    }
}
