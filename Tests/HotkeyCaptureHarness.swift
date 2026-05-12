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
        try capturesRightControlAsStandaloneOnlyOnRelease()
        try capturesRightControlChordWhenAnotherKeyIsPressed()
        try modifierChordCancelsStandaloneRightControlCapture()
        try existingModifierSuppressesStandaloneRightControlCapture()
        try existingLeftControlSuppressesStandaloneRightControlCapture()
        try capturesRightControlReleaseEvenWhenAnotherControlKeyIsDown()
        try escapeCancelsCapture()
        print("Hotkey capture harness passed")
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
            session.handle(event: mDown) == .captured(expected),
            "right Control plus M captures a Control+M chord instead of standalone right Control"
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
