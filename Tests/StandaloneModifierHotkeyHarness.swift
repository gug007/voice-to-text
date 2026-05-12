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

@main
struct StandaloneModifierHotkeyHarness {
    static func main() throws {
        try holdAloneEmitsPressThenRelease()
        try quickTapEmitsPressAndReleaseOnKeyUp()
        try chordBeforeDelaySuppressesStandaloneHotkey()
        try chordAfterDelayedPressCancelsStandaloneHotkey()
        try releaseUsesRightControlTransitionNotAggregateControlFlags()
        print("Standalone modifier hotkey harness passed")
    }

    private static func holdAloneEmitsPressThenRelease() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        let down = state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl))
        try expect(down, [.schedulePress(1)], "right Control down schedules delayed press")
        try expect(state.fireScheduledPress(token: 1), [.emitPressed], "delay emits press")
        try expect(
            state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl)),
            [.emitReleased],
            "right Control release emits release"
        )
    }

    private static func quickTapEmitsPressAndReleaseOnKeyUp() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl))
        try expect(
            state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl)),
            [.cancelScheduledPress, .emitPressed, .emitReleased],
            "quick tap still produces a full press/release"
        )
    }

    private static func chordBeforeDelaySuppressesStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl))
        try expect(
            state.handleKeyDown(keyCode: UInt16(kVK_ANSI_M)),
            [.cancelScheduledPress],
            "another key before delay suppresses standalone press"
        )
        try expect(state.fireScheduledPress(token: 1), [], "cancelled delay emits nothing")
        try expect(
            state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl)),
            [.cancelScheduledPress],
            "right Control release after suppressed chord emits nothing"
        )
    }

    private static func chordAfterDelayedPressCancelsStandaloneHotkey() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl))
        _ = state.fireScheduledPress(token: 1)
        try expect(
            state.handleKeyDown(keyCode: UInt16(kVK_ANSI_M)),
            [.emitCancelled],
            "another key after delayed press cancels standalone hotkey"
        )
        try expect(
            state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl)),
            [.cancelScheduledPress],
            "right Control release after cancelled chord emits nothing"
        )
    }

    private static func releaseUsesRightControlTransitionNotAggregateControlFlags() throws {
        var state = StandaloneModifierHotkeyState(modifierKeyCode: UInt16(kVK_RightControl))
        _ = state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl))
        _ = state.fireScheduledPress(token: 1)
        try expect(
            state.handleFlagsChanged(keyCode: UInt16(kVK_RightControl)),
            [.emitReleased],
            "right Control release is honored even if another Control key remains down"
        )
    }
}
