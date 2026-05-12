import AppKit
import Carbon.HIToolbox

enum RecordingEscapePolicy {
    private static let shortcutModifierFlags: NSEvent.ModifierFlags = [
        .command,
        .option,
        .control,
        .shift,
    ]

    static func shouldCancel(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        allowedModifierFlags: NSEvent.ModifierFlags = []
    ) -> Bool {
        guard keyCode == UInt16(kVK_Escape) else { return false }

        let activeModifiers = modifierFlags.intersection(shortcutModifierFlags)
        let allowedModifiers = allowedModifierFlags.intersection(shortcutModifierFlags)
        return activeModifiers.subtracting(allowedModifiers).isEmpty
    }

    static func shouldStartCancel(
        isKeyDown: Bool,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        allowedModifierFlags: NSEvent.ModifierFlags = []
    ) -> Bool {
        isKeyDown && shouldCancel(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            allowedModifierFlags: allowedModifierFlags
        )
    }

    static func isEscape(keyCode: UInt16) -> Bool {
        keyCode == UInt16(kVK_Escape)
    }
}

final class RecordingEscapeSwallowState: @unchecked Sendable {
    private let lock = NSLock()
    private var awaitingKeyUp = false

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !awaitingKeyUp else { return false }
        awaitingKeyUp = true
        return true
    }

    func finishIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard awaitingKeyUp else { return false }
        awaitingKeyUp = false
        return true
    }

    func reset() {
        lock.lock()
        awaitingKeyUp = false
        lock.unlock()
    }
}
