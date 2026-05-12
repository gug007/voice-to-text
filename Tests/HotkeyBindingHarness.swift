import Carbon.HIToolbox
import Foundation
import AppKit

struct BindingHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw BindingHarnessFailure(description: message)
    }
}

@main
struct HotkeyBindingHarness {
    static func main() throws {
        let rightControl = HotkeyBinding.rightControlBinding
        try expect(rightControl.keyCode == UInt32(kVK_RightControl), "right Control key code is stored")
        try expect(rightControl.modifiers == 0, "right Control binding has no modifier chord")
        try expect(rightControl.keyLabel == "Right Control", "right Control binding has a clear label")
        try expect(rightControl.isStandaloneModifier, "right Control is marked as standalone modifier")
        try expect(rightControl.displayKeys == ["Right Control"], "right Control display is a single key")
        let flagsChanged = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCTLKEYMASK)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_RightControl)
        )
        try expect(flagsChanged != nil, "synthetic right Control flagsChanged event can be created")
        try expect(
            flagsChanged.flatMap(HotkeyBinding.fromModifierEvent) == rightControl,
            "right Control flagsChanged event maps to standalone binding"
        )

        let defaultBinding = HotkeyBinding.defaultBinding
        try expect(!defaultBinding.isStandaloneModifier, "default Option+Space is not standalone modifier")
        try expect(defaultBinding.displayKeys == ["⌥", "Space"], "default display remains Option+Space")

        print("Hotkey binding harness passed")
    }
}
