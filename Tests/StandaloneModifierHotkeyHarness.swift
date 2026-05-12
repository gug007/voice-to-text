import Carbon.HIToolbox
import Foundation

struct StandaloneModifierHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(
    _ actual: [StandaloneModifierHotkeyEffect],
    _ expected: [StandaloneModifierHotkeyEffect],
    _ message: String
) throws {
    if actual != expected {
        throw StandaloneModifierHarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw StandaloneModifierHarnessFailure(description: message)
    }
}

@main
struct StandaloneModifierHotkeyHarness {
    static func main() throws {
        try holdAloneEmitsPressThenRelease()
        try quickTapEmitsPressAndReleaseOnKeyUp()
        try chordBeforeDelaySuppressesStandaloneHotkey()
        try chordAfterDelayedPressCancelsStandaloneHotkey()
        try modifierChordBeforeDelaySuppressesStandaloneHotkey()
        try modifierChordAfterDelayedPressCancelsStandaloneHotkey()
        try mouseChordBeforeDelaySuppressesStandaloneHotkey()
        try mouseChordAfterDelayedPressCancelsStandaloneHotkey()
        try existingModifierSuppressesStandaloneHotkey()
        try existingKeyInputSuppressesStandaloneHotkey()
        try releaseUsesRightControlTransitionNotAggregateControlFlags()
        try missedReleaseDoesNotMakeNextReleaseLookLikePress()
        try missedPressDoesNotMakeNextPressLookLikeRelease()
        try activeInputTrackerTracksHeldKeysAndButtons()
        print("Standalone modifier hotkey harness passed")
    }

    private static func holdAloneEmitsPressThenRelease() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        let down = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        try expect(down, [.schedulePress(1)], "right Control down schedules delayed press")
        try expect(state.fireScheduledPress(token: 1), [.emitPressed], "delay emits press")
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.emitReleased],
            "right Control release emits release"
        )
    }

    private static func quickTapEmitsPressAndReleaseOnKeyUp() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress, .emitPressed, .emitReleased],
            "quick tap still produces a full press/release"
        )
    }

    private static func chordBeforeDelaySuppressesStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        try expect(
            state.handleKeyDown(keyCode: UInt16(kVK_ANSI_M)),
            [.cancelScheduledPress],
            "another key before delay suppresses standalone press"
        )
        try expect(state.fireScheduledPress(token: 1), [], "cancelled delay emits nothing")
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after suppressed chord emits nothing"
        )
    }

    private static func chordAfterDelayedPressCancelsStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        _ = state.fireScheduledPress(token: 1)
        try expect(
            state.handleKeyDown(keyCode: UInt16(kVK_ANSI_M)),
            [.emitCancelled],
            "another key after delayed press cancels standalone hotkey"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after cancelled chord emits nothing"
        )
    }

    private static func modifierChordBeforeDelaySuppressesStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_Option),
                isModifierDown: true
            ),
            [.cancelScheduledPress],
            "another modifier before delay suppresses standalone press"
        )
        try expect(state.fireScheduledPress(token: 1), [], "cancelled modifier chord emits nothing")
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after modifier chord emits nothing"
        )
    }

    private static func modifierChordAfterDelayedPressCancelsStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        _ = state.fireScheduledPress(token: 1)
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_Option),
                isModifierDown: true
            ),
            [.emitCancelled],
            "another modifier after delayed press cancels standalone hotkey"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after cancelled modifier chord emits nothing"
        )
    }

    private static func mouseChordBeforeDelaySuppressesStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        try expect(
            state.handleChord(),
            [.cancelScheduledPress],
            "mouse action before delay suppresses standalone press"
        )
        try expect(state.fireScheduledPress(token: 1), [], "cancelled mouse chord emits nothing")
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after mouse chord emits nothing"
        )
    }

    private static func mouseChordAfterDelayedPressCancelsStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        _ = state.fireScheduledPress(token: 1)
        try expect(
            state.handleChord(),
            [.emitCancelled],
            "mouse action after delayed press cancels standalone hotkey"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after cancelled mouse chord emits nothing"
        )
    }

    private static func existingModifierSuppressesStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: true,
                hasOtherModifierDown: true
            ),
            [],
            "right Control down while another modifier is held does not schedule standalone press"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after existing modifier emits nothing"
        )
    }

    private static func existingKeyInputSuppressesStandaloneHotkey() throws {
        var tracker = StandaloneActiveInputTracker()
        tracker.keyDown(UInt16(kVK_ANSI_M), excluding: UInt16(kVK_RightControl))

        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: true,
                hasOtherModifierDown: tracker.hasActiveInput
            ),
            [],
            "right Control down while another key is held does not schedule standalone press"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress],
            "right Control release after existing key emits nothing"
        )
    }

    private static func releaseUsesRightControlTransitionNotAggregateControlFlags() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        _ = state.fireScheduledPress(token: 1)
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.emitReleased],
            "right Control release is honored even if another Control key remains down"
        )
    }

    private static func missedReleaseDoesNotMakeNextReleaseLookLikePress() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightControl),
            isModifierDown: true
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: true
            ),
            [],
            "duplicate right Control down after a missed release does not toggle to release"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [.cancelScheduledPress, .emitPressed, .emitReleased],
            "actual right Control up still finishes the tap"
        )
    }

    private static func missedPressDoesNotMakeNextPressLookLikeRelease() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: false
            ),
            [],
            "right Control up with no tracked press is ignored"
        )
        try expect(
            state.handleFlagsChanged(
                keyCode: UInt16(kVK_RightControl),
                isModifierDown: true
            ),
            [.schedulePress(1)],
            "next actual right Control down starts a fresh press"
        )
    }

    private static func activeInputTrackerTracksHeldKeysAndButtons() throws {
        var tracker = StandaloneActiveInputTracker()
        try expect(!tracker.hasActiveInput, "starts with no active input")

        tracker.keyDown(UInt16(kVK_ANSI_M), excluding: UInt16(kVK_RightControl))
        try expect(tracker.hasActiveInput, "tracks held non-modifier key before right Control")
        tracker.keyDown(UInt16(kVK_RightControl), excluding: UInt16(kVK_RightControl))
        try expect(tracker.hasActiveInput, "ignores right Control itself")
        tracker.keyUp(UInt16(kVK_ANSI_M))
        try expect(!tracker.hasActiveInput, "clears held key on key-up")

        tracker.mouseDown(button: 0)
        try expect(tracker.hasActiveInput, "tracks held mouse button before right Control")
        tracker.mouseUp(button: 0)
        try expect(!tracker.hasActiveInput, "clears held mouse button on mouse-up")
    }
}
