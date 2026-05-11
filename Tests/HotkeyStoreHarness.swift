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
        let previousBinding = defaults.data(forKey: bindingKey)
        let previousMode = defaults.string(forKey: modeKey)

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
        }

        defaults.removeObject(forKey: modeKey)

        try await MainActor.run {
            let store = HotkeyStore.shared
            try expect(store.mode == .toggle, "missing mode preserves existing toggle behavior")

            store.updateMode(to: .toggle)
            try expect(store.mode == .toggle, "mode updates in memory")

            store.updateMode(to: .hold)
            try expect(store.mode == .hold, "mode can switch back to hold")
            try expect(defaults.string(forKey: modeKey) == "hold", "hold mode persists to defaults")

            let controlF1 = HotkeyBinding(
                keyCode: UInt32(kVK_F1),
                modifiers: UInt32(controlKey),
                keyLabel: "F1"
            )
            store.update(to: controlF1)
            let saved = defaults.data(forKey: bindingKey)
            try expect(saved != nil, "binding persists to defaults")
            let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: saved ?? Data())
            try expect(decoded == controlF1, "persisted binding decodes")
        }

        print("Hotkey store harness passed")
    }
}
