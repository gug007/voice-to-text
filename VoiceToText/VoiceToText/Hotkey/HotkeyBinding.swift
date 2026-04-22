import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

struct HotkeyBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultBinding = HotkeyBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        keyLabel: "Space"
    )

    var modifierSymbols: [String] {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        return parts
    }

    var displayKeys: [String] { modifierSymbols + [keyLabel] }

    static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
        kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    var isFunctionKey: Bool { Self.functionKeyCodes.contains(Int(keyCode)) }

    static func fromEvent(_ event: NSEvent) -> HotkeyBinding {
        var mods: UInt32 = 0
        let f = event.modifierFlags
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        if f.contains(.option)  { mods |= UInt32(optionKey) }
        if f.contains(.control) { mods |= UInt32(controlKey) }
        if f.contains(.shift)   { mods |= UInt32(shiftKey) }
        return HotkeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: mods,
            keyLabel: KeyCodeLabel.label(for: UInt32(event.keyCode), event: event)
        )
    }
}

enum KeyCodeLabel {
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Escape: "Esc",
        kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦",
        kVK_Home: "Home",
        kVK_End: "End",
        kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func label(for keyCode: UInt32, event: NSEvent? = nil) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        if let chars = event?.charactersIgnoringModifiers,
           !chars.isEmpty, chars.first?.isASCII == true {
            return chars.uppercased()
        }
        if let chars = translate(keyCode: keyCode), !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func translate(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }

        var deadKeyState: UInt32 = 0
        var actualLen = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            4,
            &actualLen,
            &chars
        )
        guard status == noErr, actualLen > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: actualLen)
    }
}

@Observable
@MainActor
final class HotkeyStore {
    static let shared = HotkeyStore()

    private let storageKey = "hotkey.binding.v1"
    private(set) var binding: HotkeyBinding = .defaultBinding
    @ObservationIgnored var onChange: ((HotkeyBinding) -> Void)?

    private init() { load() }

    func update(to new: HotkeyBinding) {
        guard new != binding else { return }
        binding = new
        save()
        onChange?(new)
    }

    func resetToDefault() {
        update(to: .defaultBinding)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return }
        binding = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
