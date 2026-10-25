import SwiftUI

/// Which microphone dictation and conversations record from. Backed by the
/// `audio.inputDevice.uid` / `audio.inputDevice.name` UserDefaults, which
/// `AudioRecorder` resolves at the start of every take and `MeetingRecorder`
/// at the start of every conversation — so a change here applies from the next
/// recording, never to one already running.
///
/// A pinned device that is unplugged stays selected and says so, rather than
/// the setting quietly resetting itself: plugging it back in is then all it
/// takes, and nobody comes back to find their choice gone.
struct MicrophoneCard: View {
    /// Read from `MicrophonePreference`, which every write goes through, and
    /// re-read when it announces one. Not `@AppStorage`: its keys contain
    /// dots, and a dotted key is not observed when written from outside the
    /// property wrapper.
    @State private var stored = MicrophonePreference.stored(in: .standard)
    private let monitor = InputDeviceMonitor.shared

    var body: some View {
        let menu = MicrophoneMenu(storedUID: stored.uid, lastKnownName: stored.lastKnownName, snapshot: monitor.snapshot)
        Plate {
            SettingHeader(title: "Microphone", subtitle: menu.subtitle) {
                MinimalDropdown(
                    selection: Binding(get: { menu.selection }, set: { select($0) }),
                    sections: sections(for: menu),
                    popupWidth: 300
                )
            }
        }
        // Listening only while the card is on screen; the monitor is shared
        // and counts its observers, so a reopened pane adds no listeners.
        .task { await monitor.observe() }
        .onReceive(NotificationCenter.default.publisher(for: MicrophonePreference.didChangeNotification)) { _ in
            stored = MicrophonePreference.stored(in: .standard)
        }
        .onChange(of: menu.renamedPinnedDevice, initial: true) { _, renamed in
            guard let renamed else { return }
            MicrophonePreference.recordName(renamed, in: .standard)
            stored = MicrophonePreference.stored(in: .standard)
        }
    }

    private func sections(for menu: MicrophoneMenu) -> [DropdownSection<String?>] {
        var sections = [DropdownSection(items: [item(menu.systemDefault)])]
        if !menu.devices.isEmpty {
            sections.append(DropdownSection(header: "Microphones", items: menu.devices.map(item)))
        }
        return sections
    }

    private func item(_ row: MicrophoneMenu.Row) -> DropdownItem<String?> {
        DropdownItem(value: row.value, title: row.title, detail: row.detail, caption: row.caption)
    }

    /// `nil` is the system default. A UID missing from the snapshot can only
    /// be the unplugged pin's own row, which is already the selection.
    private func select(_ uid: String?) {
        guard uid != stored.uid else { return }
        guard let uid else {
            MicrophonePreference.select(nil, in: .standard)
            return
        }
        guard let device = monitor.snapshot?.devices.first(where: { $0.uid == uid }) else { return }
        MicrophonePreference.select(device, in: .standard)
    }
}
