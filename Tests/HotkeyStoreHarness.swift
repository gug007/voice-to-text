import Carbon.HIToolbox
import Foundation

struct StoreHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw StoreHarnessFailure(description: message)
    }
}

@main
struct HotkeyStoreHarness {
    static func main() async throws {
        let defaults = UserDefaults.standard
        let bindingKey = "hotkey.binding.v1"
        let modeKey = "hotkey.recordingMode.v1"
        let meetingBindingKey = "hotkey.meetingBinding.v1"
        let escapeKey = "hotkey.escapeCancelsDictation.v1"
        let previousBinding = defaults.data(forKey: bindingKey)
        let previousMode = defaults.string(forKey: modeKey)
        let previousMeetingBinding = defaults.data(forKey: meetingBindingKey)
        let previousEscape = defaults.object(forKey: escapeKey) as? Bool

        defer {
            if let previousBinding {
                defaults.set(previousBinding, forKey: bindingKey)
            } else {
                defaults.removeObject(forKey: bindingKey)
            }

            if let previousMode {
                defaults.set(previousMode, forKey: modeKey)
            } else {
                defaults.removeObject(forKey: modeKey)
            }

            if let previousMeetingBinding {
                defaults.set(previousMeetingBinding, forKey: meetingBindingKey)
            } else {
                defaults.removeObject(forKey: meetingBindingKey)
        defaults.removeObject(forKey: escapeKey)
            }

            if let previousEscape {
                defaults.set(previousEscape, forKey: escapeKey)
            } else {
                defaults.removeObject(forKey: escapeKey)
            }
        }

        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: meetingBindingKey)

        try await MainActor.run {
            let store = HotkeyStore.shared
            try expect(store.mode == .toggle, "missing mode preserves existing toggle behavior")

            store.updateMode(to: .toggle)
            try expect(store.mode == .toggle, "mode updates in memory")

            store.updateMode(to: .hold)
            try expect(store.mode == .hold, "mode can switch back to hold")
            try expect(defaults.string(forKey: modeKey) == "hold", "hold mode persists to defaults")

            let rightControl = HotkeyBinding.rightControlBinding
            store.update(to: rightControl)
            let saved = defaults.data(forKey: bindingKey)
            try expect(saved != nil, "binding persists to defaults")
            let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: saved ?? Data())
            try expect(decoded == rightControl, "persisted binding decodes as right Control")

            try expect(store.meetingBinding == nil, "conversation shortcut is unset by default")

            let conversation = HotkeyBinding(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(optionKey | shiftKey),
                keyLabel: "R"
            )
            store.updateMeetingBinding(to: conversation)
            try expect(store.meetingBinding == conversation, "conversation shortcut updates in memory")
            let savedMeeting = defaults.data(forKey: meetingBindingKey)
            try expect(savedMeeting != nil, "conversation shortcut persists to defaults")
            let decodedMeeting = try JSONDecoder().decode(HotkeyBinding.self, from: savedMeeting ?? Data())
            try expect(decodedMeeting == conversation, "persisted conversation shortcut decodes back")

            store.clearMeetingBinding()
            try expect(store.meetingBinding == nil, "clearing the conversation shortcut unsets it")
            try expect(
                defaults.data(forKey: meetingBindingKey) == nil,
                "clearing the conversation shortcut removes the key rather than storing a null"
            )

            try expect(
                store.escapeCancelsDictation,
                "a missing Esc-cancels key reads as on, so upgrades keep today's behavior"
            )

            store.updateEscapeCancelsDictation(false)
            try expect(!store.escapeCancelsDictation, "Esc cancel can be turned off")
            try expect(
                defaults.object(forKey: escapeKey) as? Bool == false,
                "Esc cancel off persists to defaults"
            )

            store.updateEscapeCancelsDictation(true)
            try expect(store.escapeCancelsDictation, "Esc cancel can be turned back on")
            try expect(
                defaults.object(forKey: escapeKey) as? Bool == true,
                "Esc cancel on persists to defaults"
            )
        }

        print("Hotkey store harness passed")
    }
}
