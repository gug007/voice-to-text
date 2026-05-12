import AppKit
import Carbon.HIToolbox
import Foundation

struct RecordingEscapePolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RecordingEscapePolicyHarnessFailure(description: message)
    }
}

@main
struct RecordingEscapePolicyHarness {
    static func main() throws {
        try expect(
            RecordingEscapePolicy.shouldCancel(keyCode: UInt16(kVK_Escape), modifierFlags: []),
            "bare Escape cancels recording"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(keyCode: UInt16(kVK_Escape), modifierFlags: .option),
            "modified Escape is left available for configured shortcuts"
        )
        try expect(
            RecordingEscapePolicy.shouldCancel(
                keyCode: UInt16(kVK_Escape),
                modifierFlags: .option,
                allowedModifierFlags: .option
            ),
            "Escape with the held hold-mode hotkey modifier cancels recording"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(
                keyCode: UInt16(kVK_Escape),
                modifierFlags: .option,
                allowedModifierFlags: [.command, .option]
            ),
            "Escape with only part of a held multi-modifier hotkey passes through"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(
                keyCode: UInt16(kVK_Escape),
                modifierFlags: .option,
                allowedModifierFlags: .option,
                recordingShortcutKeyCode: UInt16(kVK_Escape)
            ),
            "Escape does not cancel when it is the held recording shortcut key"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(
                keyCode: UInt16(kVK_Escape),
                modifierFlags: [.option, .command],
                allowedModifierFlags: .option
            ),
            "Escape with extra modifiers still passes through"
        )
        try expect(
            RecordingEscapePolicy.shouldStartCancel(
                isKeyDown: true,
                keyCode: UInt16(kVK_Escape),
                modifierFlags: .option,
                allowedModifierFlags: .option,
                recordingShortcutKeyCode: UInt16(kVK_Space)
            ),
            "Escape key-down with held hotkey modifier starts cancellation"
        )
        try expect(
            !RecordingEscapePolicy.shouldStartCancel(
                isKeyDown: false,
                keyCode: UInt16(kVK_Escape),
                modifierFlags: .option,
                allowedModifierFlags: .option,
                recordingShortcutKeyCode: UInt16(kVK_Space)
            ),
            "Escape key-up does not start cancellation"
        )
        try expect(
            !RecordingEscapePolicy.shouldCancel(keyCode: UInt16(kVK_ANSI_M), modifierFlags: []),
            "non-Escape keys do not cancel recording"
        )
        try expect(
            RecordingEscapePolicy.isEscape(keyCode: UInt16(kVK_Escape)),
            "Escape key-up can finish a swallowed cancel gesture"
        )
        try expect(
            !RecordingEscapePolicy.isEscape(keyCode: UInt16(kVK_ANSI_M)),
            "non-Escape key-up does not finish a swallowed cancel gesture"
        )

        let swallowState = RecordingEscapeSwallowState()
        try expect(swallowState.begin(), "first bare Escape down starts swallowing")
        try expect(!swallowState.begin(), "repeated Escape down is swallowed without restarting")
        try expect(swallowState.finishIfNeeded(), "Escape key-up finishes swallowing")
        try expect(!swallowState.finishIfNeeded(), "extra Escape key-up passes after swallowing ends")
        try expect(swallowState.begin(), "swallowing can begin again after key-up")
        swallowState.reset()
        try expect(!swallowState.finishIfNeeded(), "reset clears pending swallowed Escape")

        print("Recording escape policy harness passed")
    }
}
