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
        modifiers == 0 && Self.modifierKeyCodes.contains(keyCode)
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

    static let modifierKeyCodes: Set<UInt32> = Set(modifierKeyDescriptors.map(\.keyCode))

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
        guard let descriptor = modifierDescriptor(for: event) else { return nil }
        return HotkeyBinding(
            keyCode: descriptor.keyCode,
            modifiers: 0,
            keyLabel: descriptor.label
        )
    }

    static func modifierIsDown(_ binding: HotkeyBinding, in event: NSEvent) -> Bool {
        guard let descriptor = modifierDescriptor(forKeyCode: binding.keyCode) else { return false }
        return event.modifierFlags.rawValue & descriptor.deviceMask != 0
            || event.modifierFlags.contains(descriptor.aggregateFlag)
    }

    static func modifierIsDown(_ binding: HotkeyBinding, rawModifierFlags: UInt64) -> Bool {
        guard let descriptor = modifierDescriptor(forKeyCode: binding.keyCode) else { return false }
        return rawModifierFlags & UInt64(descriptor.deviceMask) != 0
    }

    static func modifierKeyEventMatches(_ keyCode: UInt16, binding: HotkeyBinding) -> Bool {
        guard let descriptor = modifierDescriptor(forKeyCode: binding.keyCode) else { return false }
        return descriptor.matches(keyCode: keyCode)
    }

    static func isReleaseOfModifier(_ binding: HotkeyBinding, event: NSEvent) -> Bool {
        guard let descriptor = modifierDescriptor(forKeyCode: binding.keyCode) else { return false }
        return descriptor.matches(event: event) && !modifierIsDown(binding, in: event)
    }

    static func otherModifiersAreDown(than binding: HotkeyBinding, in event: NSEvent) -> Bool {
        guard let descriptor = modifierDescriptor(forKeyCode: binding.keyCode) else { return false }
        let activeDeviceFlags = event.modifierFlags.rawValue & allModifierDeviceMask
        let activeAggregateFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return activeDeviceFlags & ~descriptor.deviceMask != 0
            || !activeAggregateFlags.subtracting(descriptor.aggregateFlag).isEmpty
    }

    static func otherModifiersAreDown(than binding: HotkeyBinding, rawModifierFlags: UInt64) -> Bool {
        guard let descriptor = modifierDescriptor(forKeyCode: binding.keyCode) else { return false }
        let activeDeviceFlags = UInt(rawModifierFlags) & allModifierDeviceMask
        return activeDeviceFlags & ~descriptor.deviceMask != 0
    }

    private static func modifierDescriptor(for event: NSEvent) -> ModifierKeyDescriptor? {
        let rawFlags = event.modifierFlags.rawValue
        if let descriptor = modifierKeyDescriptors.first(where: { descriptor in
            descriptor.matches(event: event)
                && rawFlags & descriptor.deviceMask != 0
        }) {
            return descriptor
        }

        return modifierKeyDescriptors.first { descriptor in
            event.keyCode == UInt16(descriptor.keyCode)
        }
    }

    private static func modifierDescriptor(forKeyCode keyCode: UInt32) -> ModifierKeyDescriptor? {
        modifierKeyDescriptors.first { $0.keyCode == keyCode }
    }
}

private struct ModifierKeyDescriptor {
    let keyCode: UInt32
    let genericKeyCode: UInt16
    let deviceMask: UInt
    let aggregateFlag: NSEvent.ModifierFlags
    let label: String

    func matches(event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode)
    }

    func matches(keyCode: UInt16) -> Bool {
        keyCode == UInt16(self.keyCode) || keyCode == genericKeyCode
    }
}

private let modifierKeyDescriptors: [ModifierKeyDescriptor] = [
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_Command),
        genericKeyCode: UInt16(kVK_Command),
        deviceMask: UInt(NX_DEVICELCMDKEYMASK),
        aggregateFlag: .command,
        label: "Command"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_RightCommand),
        genericKeyCode: UInt16(kVK_Command),
        deviceMask: UInt(NX_DEVICERCMDKEYMASK),
        aggregateFlag: .command,
        label: "Right Command"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_Shift),
        genericKeyCode: UInt16(kVK_Shift),
        deviceMask: UInt(NX_DEVICELSHIFTKEYMASK),
        aggregateFlag: .shift,
        label: "Shift"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_RightShift),
        genericKeyCode: UInt16(kVK_Shift),
        deviceMask: UInt(NX_DEVICERSHIFTKEYMASK),
        aggregateFlag: .shift,
        label: "Right Shift"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_Option),
        genericKeyCode: UInt16(kVK_Option),
        deviceMask: UInt(NX_DEVICELALTKEYMASK),
        aggregateFlag: .option,
        label: "Option"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_RightOption),
        genericKeyCode: UInt16(kVK_Option),
        deviceMask: UInt(NX_DEVICERALTKEYMASK),
        aggregateFlag: .option,
        label: "Right Option"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_Control),
        genericKeyCode: UInt16(kVK_Control),
        deviceMask: UInt(NX_DEVICELCTLKEYMASK),
        aggregateFlag: .control,
        label: "Control"
    ),
    ModifierKeyDescriptor(
        keyCode: UInt32(kVK_RightControl),
        genericKeyCode: UInt16(kVK_Control),
        deviceMask: UInt(NX_DEVICERCTLKEYMASK),
        aggregateFlag: .control,
        label: "Right Control"
    ),
]

private let allModifierDeviceMask = modifierKeyDescriptors.reduce(UInt(0)) { mask, descriptor in
    mask | descriptor.deviceMask
}

enum KeyCodeLabel {
    private static let specialKeys: [Int: String] = [
        kVK_Command: "Command",
        kVK_RightCommand: "Right Command",
        kVK_Shift: "Shift",
        kVK_RightShift: "Right Shift",
        kVK_Option: "Option",
        kVK_RightOption: "Right Option",
        kVK_Control: "Control",
        kVK_RightControl: "Right Control",
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
    private(set) var binding: HotkeyBinding = .defaultBinding
    private(set) var mode: RecordingShortcutMode = .toggle
    @ObservationIgnored var onChange: (() -> Void)?

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

    private func load() {
        if let data = UserDefaults.standard.data(forKey: bindingStorageKey),
           let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            binding = decoded
        }

        if let rawMode = UserDefaults.standard.string(forKey: modeStorageKey),
           let decodedMode = RecordingShortcutMode(rawValue: rawMode) {
            mode = decodedMode
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
}
