import AppKit
import Carbon.HIToolbox

enum RecordingEscapePolicy {
    static func shouldCancel(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let pureModifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        return keyCode == UInt16(kVK_Escape) && pureModifiers.isEmpty
    }
}
