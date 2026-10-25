import Foundation

/// Which microphone the app records from, decided without touching CoreAudio.
///
/// Everything here is pure on purpose. The HAL reads that feed it can block
/// for seconds while a Bluetooth device renegotiates, so they happen where a
/// stall is survivable — `AudioRecorder`'s engine queue, the Settings
/// listener's own queue — and only their answers come here. That also lets a
/// harness exercise every case without plugging anything in.

// MARK: - Devices

/// One input device the user can pick.
///
/// The UID is the identity. It is stable across reconnects and reboots, where
/// an `AudioDeviceID` is reassigned by the HAL every time a device appears —
/// persisting one of those would pin whatever happens to get that number
/// next. Names are not identities either: two identical USB mics share one.
nonisolated struct InputDevice: Hashable, Sendable {
    let uid: String
    let name: String
    /// How it is attached ("Built-in", "USB", "Bluetooth"…), for the
    /// dropdown's trailing caption; `nil` when the HAL does not say.
    let caption: String?
}

/// What the Settings picker lists: the input devices present right now, and
/// the name of the one macOS would use by default.
nonisolated struct InputDeviceSnapshot: Equatable, Sendable {
    var devices: [InputDevice]
    var defaultInputName: String?
}

// MARK: - Preference

/// The persisted choice. An absent or blank UID means "System default", which
/// is exactly the behaviour the app had before the setting existed.
nonisolated enum MicrophonePreference {
    static let uidKey = "audio.inputDevice.uid"
    /// The pinned device's name as last seen, so the picker can still name it
    /// while it is unplugged instead of showing a bare UID.
    static let nameKey = "audio.inputDevice.name"
    /// Posted on the main thread by `select`. The recorders resolve the
    /// preference at every start regardless; this only lets a cached engine
    /// be rebuilt before the next press needs it, and the picker re-read it.
    static let didChangeNotification = Notification.Name("MicrophonePreferenceDidChange")

    struct Stored: Equatable, Sendable {
        let uid: String?
        let lastKnownName: String?
    }

    static func stored(in defaults: UserDefaults) -> Stored {
        Stored(
            uid: normalized(defaults.string(forKey: uidKey)),
            lastKnownName: normalized(defaults.string(forKey: nameKey))
        )
    }

    /// Pins `device`, or goes back to the system default for `nil`, and tells
    /// the recorders so they can drop an engine built for the old choice.
    static func select(_ device: InputDevice?, in defaults: UserDefaults) {
        if let device {
            defaults.set(device.uid, forKey: uidKey)
            if let name = normalized(device.name) {
                defaults.set(name, forKey: nameKey)
            } else {
                defaults.removeObject(forKey: nameKey)
            }
        } else {
            defaults.removeObject(forKey: uidKey)
            defaults.removeObject(forKey: nameKey)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Keeps the stored name of a pinned device current — a renamed pair of
    /// AirPods — so the picker names it correctly the next time it is away.
    /// The microphone itself has not changed, so nothing is posted.
    static func recordName(_ name: String, in defaults: UserDefaults) {
        defaults.set(name, forKey: nameKey)
    }

    /// Blank and whitespace-only values are treated as nothing stored, so a
    /// hand-edited or half-written default can never pin a device named "".
    static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

// MARK: - Resolution

/// The stored preference resolved against what is connected now.
///
/// Generic over the device payload so the two callers share one decision:
/// the recorders resolve to a live `AudioDeviceID` through a single HAL UID
/// lookup, the Settings picker to an `InputDevice` out of its snapshot.
nonisolated enum MicrophoneSelection<Device> {
    /// Nothing pinned: follow the system default input.
    case systemDefault
    /// Pinned and connected.
    case pinned(uid: String, device: Device)
    /// Pinned but not connected. Capture falls back to the system default for
    /// now, and the choice is kept rather than reset: plugging the device back
    /// in should be all it takes to get it back.
    case missing(uid: String, lastKnownName: String?)

    /// `find` is only called when something is pinned, so the system-default
    /// path costs no HAL lookup at all.
    static func resolve(
        storedUID: String?,
        lastKnownName: String?,
        find: (String) -> Device?
    ) -> MicrophoneSelection<Device> {
        guard let uid = MicrophonePreference.normalized(storedUID) else { return .systemDefault }
        if let device = find(uid) { return .pinned(uid: uid, device: device) }
        return .missing(uid: uid, lastKnownName: MicrophonePreference.normalized(lastKnownName))
    }

    /// What a capture should bind to, or `nil` to follow the system default
    /// — a pin that is not connected included.
    var pinned: (uid: String, device: Device)? {
        if case .pinned(let uid, let device) = self { return (uid, device) }
        return nil
    }
}

extension MicrophoneSelection: Equatable where Device: Equatable {}
extension MicrophoneSelection: Sendable where Device: Sendable {}

// MARK: - Picker model

/// The Settings dropdown's rows, built from the stored choice and the latest
/// snapshot. Kept out of the view so every state the picker can be in — not
/// yet enumerated, pinned and present, pinned and gone, two devices with one
/// name — is a harness case rather than something to reproduce by hand.
nonisolated struct MicrophoneMenu: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        /// `nil` is "System default"; anything else is a device UID.
        let value: String?
        let title: String
        let detail: String?
        let caption: String?
    }

    static let systemDefaultTitle = "System default"
    static let disconnectedDetail = "Not connected — using system default"
    static let unnamedDeviceTitle = "Unnamed microphone"
    static let unknownPinnedTitle = "Previously selected microphone"

    let systemDefault: Row
    let devices: [Row]
    /// The row to draw checked. A pinned device that is unplugged stays
    /// selected — it is still the user's choice — and says what is happening
    /// instead.
    let selection: String?
    let subtitle: String
    /// The pinned device's current name when it differs from the stored one —
    /// a renamed pair of AirPods — so the caller can refresh what it shows
    /// the next time the device is away.
    let renamedPinnedDevice: String?

    /// `snapshot` is `nil` until the first enumeration lands. Until then
    /// nothing is known to be missing, so a pinned device is listed under its
    /// stored name without being called disconnected.
    init(storedUID: String?, lastKnownName: String?, snapshot: InputDeviceSnapshot?) {
        let devices = Self.uniqued(snapshot?.devices ?? [])
        let resolved = MicrophoneSelection<InputDevice>.resolve(
            storedUID: storedUID,
            lastKnownName: lastKnownName
        ) { uid in devices.first { $0.uid == uid } }

        systemDefault = Row(
            value: nil,
            title: Self.systemDefaultTitle,
            detail: snapshot.map { snapshot in
                MicrophonePreference.normalized(snapshot.defaultInputName).map { "Currently \($0)" }
                    ?? "No microphone connected"
            },
            caption: nil
        )

        let titles = Self.disambiguatedTitles(for: devices)
        var rows = zip(devices, titles).map { device, title in
            Row(value: device.uid, title: title, detail: nil, caption: device.caption)
        }

        switch resolved {
        case .systemDefault:
            selection = nil
            subtitle = Self.defaultSubtitle
            renamedPinnedDevice = nil
        case .pinned(let uid, let device):
            selection = uid
            subtitle = Self.defaultSubtitle
            let current = MicrophonePreference.normalized(device.name)
            renamedPinnedDevice = current != MicrophonePreference.normalized(lastKnownName) ? current : nil
        case .missing(let uid, let name):
            selection = uid
            // Last, after everything that can actually be used right now.
            rows.append(Row(
                value: uid,
                title: name ?? Self.unknownPinnedTitle,
                detail: snapshot == nil ? nil : Self.disconnectedDetail,
                caption: nil
            ))
            subtitle = snapshot == nil
                ? Self.defaultSubtitle
                : "\(name ?? "The selected microphone") isn’t connected, so dictation and conversations use the system default."
            renamedPinnedDevice = nil
        }
        self.devices = rows
    }

    static let defaultSubtitle = "Used for dictation and conversations."

    /// The HAL promises unique UIDs, but the dropdown keys its rows by value,
    /// so a misbehaving driver reporting one twice must not produce two rows
    /// with one identity. Devices without a UID cannot be pinned at all.
    private static func uniqued(_ devices: [InputDevice]) -> [InputDevice] {
        var seen = Set<String>()
        return devices.filter { device in
            guard MicrophonePreference.normalized(device.uid) != nil else { return false }
            return seen.insert(device.uid).inserted
        }
    }

    /// Two identical USB mics, or two sets of the same AirPods, arrive with one
    /// name. Numbering the repeats in enumeration order keeps the rows
    /// distinguishable; the UID behind each row is what is stored, so the
    /// numbering only has to be consistent within one list.
    private static func disambiguatedTitles(for devices: [InputDevice]) -> [String] {
        var seen: [String: Int] = [:]
        return devices.map { device in
            let title = MicrophonePreference.normalized(device.name) ?? unnamedDeviceTitle
            seen[title, default: 0] += 1
            let ordinal = seen[title, default: 0]
            return ordinal == 1 ? title : "\(title) (\(ordinal))"
        }
    }
}
