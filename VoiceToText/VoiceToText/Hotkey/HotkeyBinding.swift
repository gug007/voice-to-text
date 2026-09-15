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

    static let rightControlBinding = HotkeyBinding(
        keyCode: UInt32(kVK_RightControl),
        modifiers: 0,
        keyLabel: "Right Control"
    )

    var isStandaloneModifier: Bool {
        modifiers == 0 && keyCode == UInt32(kVK_RightControl)
    }

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

    static func fromModifierEvent(_ event: NSEvent) -> HotkeyBinding? {
        guard event.keyCode == UInt16(kVK_RightControl) else { return nil }
        return .rightControlBinding
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

    private let bindingStorageKey = "hotkey.binding.v1"
    private let modeStorageKey = "hotkey.recordingMode.v1"
    private let meetingBindingStorageKey = "hotkey.meetingBinding.v1"
    private let escapeCancelsDictationStorageKey = "hotkey.escapeCancelsDictation.v1"
    private(set) var binding: HotkeyBinding = .defaultBinding
    private(set) var mode: RecordingShortcutMode = .toggle
    /// The conversation shortcut. Optional and off by default — conversation
    /// recording is a deliberate, occasional act, so it gets no key until the
    /// user asks for one.
    private(set) var meetingBinding: HotkeyBinding?
    /// Whether Esc discards an in-flight dictation. On by default. Off means Esc
    /// is never swallowed while recording or transcribing, so it reaches the app
    /// the user is actually working in.
    private(set) var escapeCancelsDictation = true
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onMeetingChange: (() -> Void)?

    private init() { load() }

    func update(to new: HotkeyBinding) {
        guard new != binding else { return }
        binding = new
        saveBinding()
        onChange?()
    }

    func updateMode(to new: RecordingShortcutMode) {
        guard new != mode else { return }
        mode = new
        saveMode()
    }

    func resetToDefault() {
        update(to: .defaultBinding)
    }

    func updateMeetingBinding(to new: HotkeyBinding?) {
        guard new != meetingBinding else { return }
        meetingBinding = new
        saveMeetingBinding()
        onMeetingChange?()
    }

    func clearMeetingBinding() {
        updateMeetingBinding(to: nil)
    }

    func updateEscapeCancelsDictation(_ new: Bool) {
        guard new != escapeCancelsDictation else { return }
        escapeCancelsDictation = new
        UserDefaults.standard.set(new, forKey: escapeCancelsDictationStorageKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: bindingStorageKey),
           let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            binding = decoded
        }

        if let rawMode = UserDefaults.standard.string(forKey: modeStorageKey),
           let decodedMode = RecordingShortcutMode(rawValue: rawMode) {
            mode = decodedMode
        }

        if let data = UserDefaults.standard.data(forKey: meetingBindingStorageKey),
           let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            meetingBinding = decoded
        }

        // `object(forKey:)`, not `bool(forKey:)`: a missing key has to read as
        // on, and `bool(forKey:)` would call it off for everyone upgrading.
        if let stored = UserDefaults.standard.object(forKey: escapeCancelsDictationStorageKey) as? Bool {
            escapeCancelsDictation = stored
        }
    }

    private func saveBinding() {
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: bindingStorageKey)
        }
    }

    private func saveMode() {
        UserDefaults.standard.set(mode.rawValue, forKey: modeStorageKey)
    }

    /// A cleared conversation shortcut removes the key outright rather than
    /// storing a null, so "never set" and "set then removed" read identically.
    private func saveMeetingBinding() {
        guard let meetingBinding, let data = try? JSONEncoder().encode(meetingBinding) else {
            UserDefaults.standard.removeObject(forKey: meetingBindingStorageKey)
            return
        }
        UserDefaults.standard.set(data, forKey: meetingBindingStorageKey)
    }
}
