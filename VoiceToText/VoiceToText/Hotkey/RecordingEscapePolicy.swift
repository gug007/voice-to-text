import AppKit
import Carbon.HIToolbox

enum RecordingEscapePolicy {
    static func shouldCancel(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let pureModifiers = modifierFlags.intersection([.command, .option, .control, .shift])
        return keyCode == UInt16(kVK_Escape) && pureModifiers.isEmpty
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
