import Foundation

enum StandaloneModifierHotkeyEffect: Equatable {
    case schedulePress(UInt64)
    case cancelScheduledPress
    case emitPressed
    case emitReleased
    case emitCancelled
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

    mutating func handleFlagsChanged(
        keyCode: UInt16,
        isModifierDown: Bool,
        hasOtherModifierDown: Bool = false
    ) -> [StandaloneModifierHotkeyEffect] {
        guard keyCode == modifierKeyCode else {
            return isModifierDown ? cancelForChord() : []
        }

        if isModifierDown {
            if hasOtherModifierDown {
                guard !modifierIsDown else { return cancelForChord() }
                modifierIsDown = true
                suppressUntilRelease = true
                pendingPressToken = nil
                pressWasEmitted = false
                return []
            }
            guard !modifierIsDown else { return [] }
            nextToken += 1
            modifierIsDown = true
            pressWasEmitted = false
            suppressUntilRelease = false
            pendingPressToken = nextToken
            return [.schedulePress(nextToken)]
        }

        guard modifierIsDown else { return [] }
        return releaseModifier()
    }

    mutating func handleKeyDown(keyCode: UInt16) -> [StandaloneModifierHotkeyEffect] {
        guard modifierIsDown, keyCode != modifierKeyCode else { return [] }
        return handleChord()
    }

    mutating func handleChord() -> [StandaloneModifierHotkeyEffect] {
        guard modifierIsDown else { return [] }
        return cancelForChord()
    }

    private mutating func cancelForChord() -> [StandaloneModifierHotkeyEffect] {
        suppressUntilRelease = true

        if pendingPressToken != nil {
            pendingPressToken = nil
            return [.cancelScheduledPress]
        }

        if pressWasEmitted {
            pressWasEmitted = false
            return [.emitCancelled]
        }

        return []
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
