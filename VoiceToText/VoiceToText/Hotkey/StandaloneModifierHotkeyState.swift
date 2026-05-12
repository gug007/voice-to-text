import Foundation

enum StandaloneModifierHotkeyEffect: Equatable {
    case schedulePress(UInt64)
    case cancelScheduledPress
    case emitPressed
    case emitReleased
}

struct StandaloneModifierHotkeyState {
    private let modifierKeyCode: UInt16
    private var nextToken: UInt64 = 0
    private var pendingPressToken: UInt64?
    private var modifierIsDown = false
    private var pressWasEmitted = false
    private var suppressUntilRelease = false

    init(modifierKeyCode: UInt16) {
        self.modifierKeyCode = modifierKeyCode
    }

    mutating func handleFlagsChanged(keyCode: UInt16) -> [StandaloneModifierHotkeyEffect] {
        guard keyCode == modifierKeyCode else { return [] }

        if modifierIsDown {
            return releaseModifier()
        }

        nextToken += 1
        modifierIsDown = true
        pressWasEmitted = false
        suppressUntilRelease = false
        pendingPressToken = nextToken
        return [.schedulePress(nextToken)]
    }

    mutating func handleKeyDown(keyCode: UInt16) -> [StandaloneModifierHotkeyEffect] {
        guard modifierIsDown, keyCode != modifierKeyCode else { return [] }
        suppressUntilRelease = true

        guard pendingPressToken != nil else { return [] }
        pendingPressToken = nil
        return [.cancelScheduledPress]
    }

    mutating func fireScheduledPress(token: UInt64) -> [StandaloneModifierHotkeyEffect] {
        guard pendingPressToken == token,
              modifierIsDown,
              !suppressUntilRelease else { return [] }

        pendingPressToken = nil
        pressWasEmitted = true
        return [.emitPressed]
    }

    mutating func reset() -> [StandaloneModifierHotkeyEffect] {
        let shouldRelease = pressWasEmitted
        pendingPressToken = nil
        modifierIsDown = false
        pressWasEmitted = false
        suppressUntilRelease = false
        return shouldRelease ? [.cancelScheduledPress, .emitReleased] : [.cancelScheduledPress]
    }

    private mutating func releaseModifier() -> [StandaloneModifierHotkeyEffect] {
        modifierIsDown = false
        suppressUntilRelease = false

        if pressWasEmitted {
            pressWasEmitted = false
            pendingPressToken = nil
            return [.emitReleased]
        }

        if pendingPressToken != nil {
            pendingPressToken = nil
            return [.cancelScheduledPress, .emitPressed, .emitReleased]
        }

        return [.cancelScheduledPress]
    }
}
