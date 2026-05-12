import AppKit
import Carbon.HIToolbox
import Foundation

struct CaptureHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CaptureHarnessFailure(description: message)
    }
}

private let leftControlModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCTLKEYMASK))
private let rightControlModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCTLKEYMASK))
private let bothControlModifierFlags = NSEvent.ModifierFlags(
    rawValue: UInt(NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK)
)

private func keyEvent(
    type: NSEvent.EventType,
    keyCode: Int,
    modifiers: NSEvent.ModifierFlags,
    characters: String = ""
) throws -> NSEvent {
    guard let event = NSEvent.keyEvent(
        with: type,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: UInt16(keyCode)
    ) else {
        throw CaptureHarnessFailure(description: "could not create synthetic event")
    }

    return event
}

@main
struct HotkeyCaptureHarness {
    static func main() throws {
        try capturesBareKeyOnRelease()
        try capturesModifiedKeyOnRelease()
        try capturesRightControlAsStandaloneOnlyOnRelease()
        try duplicateStandaloneModifierDownWaitsForRelease()
        try capturesRightControlWhenAppKitReportsGenericControlKeyCode()
        try capturesRightCommandAsStandaloneOnlyOnRelease()
        try capturesRightControlChordWhenAnotherKeyIsPressed()
        try modifierChordCancelsStandaloneRightControlCapture()
        try existingModifierSuppressesStandaloneRightControlCapture()
        try existingLeftControlSuppressesStandaloneRightControlCapture()
        try capturesRightControlReleaseEvenWhenAnotherControlKeyIsDown()
        try capturesRightControlReleaseEvenWhenAggregateControlFlagRemains()
        try escapeCancelsCapture()
        print("Hotkey capture harness passed")
    }

    private static func capturesBareKeyOnRelease() throws {
        var session = HotkeyCaptureSession()

        let jDown = try keyEvent(
            type: .keyDown,
            keyCode: kVK_ANSI_J,
            modifiers: [],
            characters: "j"
        )
        try expect(
            session.handle(event: jDown) == .ignored,
            "bare J down waits for release before capture"
        )

        let jUp = try keyEvent(
            type: .keyUp,
            keyCode: kVK_ANSI_J,
            modifiers: [],
            characters: "j"
        )
        try expect(
            session.handle(event: jUp) == .captured(
                HotkeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: 0, keyLabel: "J")
            ),
            "bare J release captures J"
        )
    }

    private static func capturesModifiedKeyOnRelease() throws {
        var session = HotkeyCaptureSession()

        let commandDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_Command,
            modifiers: .command
        )
        _ = session.handle(event: commandDown)

        let jDown = try keyEvent(
            type: .keyDown,
            keyCode: kVK_ANSI_J,
            modifiers: .command,
            characters: "j"
        )
        try expect(
            session.handle(event: jDown) == .ignored,
            "Command+J down waits for J release before capture"
        )

        let jUp = try keyEvent(
            type: .keyUp,
            keyCode: kVK_ANSI_J,
            modifiers: .command,
            characters: "j"
        )
        try expect(
            session.handle(event: jUp) == .captured(
                HotkeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey), keyLabel: "J")
            ),
            "Command+J release captures Command+J"
        )
    }

    private static func capturesRightControlAsStandaloneOnlyOnRelease() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags
        )
        try expect(
            session.handle(event: rightControlDown) == .pendingStandaloneModifier,
            "right Control down waits for either another key or release"
        )

        let rightControlUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: []
        )
        try expect(
            session.handle(event: rightControlUp) == .captured(.rightControlBinding),
            "right Control release captures standalone right Control"
        )
    }

    private static func duplicateStandaloneModifierDownWaitsForRelease() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags
        )
        _ = session.handle(event: rightControlDown)

        let duplicateRightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags
        )
        try expect(
            session.handle(event: duplicateRightControlDown) == .pendingStandaloneModifier,
            "duplicate right Control down keeps waiting for release"
        )

        let rightControlUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: []
        )
        try expect(
            session.handle(event: rightControlUp) == .captured(.rightControlBinding),
            "right Control release after duplicate down captures standalone right Control"
        )
    }

    private static func capturesRightControlWhenAppKitReportsGenericControlKeyCode() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_Control,
            modifiers: rightControlModifierFlags
        )
        try expect(
            session.handle(event: rightControlDown) == .pendingStandaloneModifier,
            "right Control down with generic Control key code waits for release"
        )

        let rightControlUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_Control,
            modifiers: []
        )
        try expect(
            session.handle(event: rightControlUp) == .captured(.rightControlBinding),
            "right Control release with generic Control key code captures standalone right Control"
        )
    }

    private static func capturesRightCommandAsStandaloneOnlyOnRelease() throws {
        var session = HotkeyCaptureSession()

        let rightCommandDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightCommand,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK))
        )
        try expect(
            session.handle(event: rightCommandDown) == .pendingStandaloneModifier,
            "right Command down waits for release"
        )

        let rightCommandUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightCommand,
            modifiers: []
        )
        try expect(
            session.handle(event: rightCommandUp) == .captured(
                HotkeyBinding(keyCode: UInt32(kVK_RightCommand), modifiers: 0, keyLabel: "Right Command")
            ),
            "right Command release captures standalone right Command"
        )
    }

    private static func capturesRightControlChordWhenAnotherKeyIsPressed() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags
        )
        _ = session.handle(event: rightControlDown)

        let mDown = try keyEvent(
            type: .keyDown,
            keyCode: kVK_ANSI_M,
            modifiers: .control,
            characters: "m"
        )
        let expected = HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(controlKey),
            keyLabel: "M"
        )
        try expect(
            session.handle(event: mDown) == .ignored,
            "right Control plus M waits for M release before capture"
        )

        let mUp = try keyEvent(
            type: .keyUp,
            keyCode: kVK_ANSI_M,
            modifiers: .control,
            characters: "m"
        )
        try expect(
            session.handle(event: mUp) == .captured(expected),
            "right Control plus M release captures a Control+M chord instead of standalone right Control"
        )

        let rightControlUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: []
        )
        try expect(
            session.handle(event: rightControlUp) == .ignored,
            "right Control release after a chord does not overwrite the chord"
        )
    }

    private static func modifierChordCancelsStandaloneRightControlCapture() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags
        )
        _ = session.handle(event: rightControlDown)

        let optionDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_Option,
            modifiers: [.control, .option]
        )
        try expect(
            session.handle(event: optionDown) == .ignored,
            "another modifier cancels pending standalone right Control capture"
        )

        let rightControlUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: .option
        )
        try expect(
            session.handle(event: rightControlUp) == .ignored,
            "right Control release after a modifier chord does not capture standalone"
        )
    }

    private static func existingModifierSuppressesStandaloneRightControlCapture() throws {
        var session = HotkeyCaptureSession()

        let rightControlDownWithOptionHeld = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags.union(.option)
        )
        try expect(
            session.handle(event: rightControlDownWithOptionHeld) == .ignored,
            "right Control down while another modifier is held is not pending standalone"
        )

        let rightControlUp = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: .option
        )
        try expect(
            session.handle(event: rightControlUp) == .ignored,
            "right Control release after an existing modifier does not capture standalone"
        )
    }

    private static func existingLeftControlSuppressesStandaloneRightControlCapture() throws {
        var session = HotkeyCaptureSession()

        let rightControlDownWithLeftControlHeld = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: bothControlModifierFlags
        )
        try expect(
            session.handle(event: rightControlDownWithLeftControlHeld) == .ignored,
            "right Control down while left Control is held is not pending standalone"
        )

        let rightControlUpWithLeftControlHeld = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: leftControlModifierFlags
        )
        try expect(
            session.handle(event: rightControlUpWithLeftControlHeld) == .ignored,
            "right Control release after existing left Control does not capture standalone"
        )
    }

    private static func capturesRightControlReleaseEvenWhenAnotherControlKeyIsDown() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags
        )
        _ = session.handle(event: rightControlDown)

        let rightControlUpWithLeftControlStillDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: leftControlModifierFlags
        )
        try expect(
            session.handle(event: rightControlUpWithLeftControlStillDown) == .captured(.rightControlBinding),
            "right Control release captures standalone even if another Control key remains down"
        )
    }

    private static func capturesRightControlReleaseEvenWhenAggregateControlFlagRemains() throws {
        var session = HotkeyCaptureSession()

        let rightControlDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: rightControlModifierFlags.union(.control)
        )
        _ = session.handle(event: rightControlDown)

        let rightControlUpWithLeftControlStillDown = try keyEvent(
            type: .flagsChanged,
            keyCode: kVK_RightControl,
            modifiers: leftControlModifierFlags.union(.control)
        )
        try expect(
            session.handle(event: rightControlUpWithLeftControlStillDown) == .captured(.rightControlBinding),
            "right Control release captures standalone even if aggregate Control remains from left Control"
        )
    }

    private static func escapeCancelsCapture() throws {
        var session = HotkeyCaptureSession()

        let escape = try keyEvent(
            type: .keyDown,
            keyCode: kVK_Escape,
            modifiers: [],
            characters: "\u{1b}"
        )
        try expect(
            session.handle(event: escape) == .cancelled,
            "bare Escape cancels shortcut capture"
        )
    }
}
