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
        allowedModifierFlags: NSEvent.ModifierFlags = [],
        recordingShortcutKeyCode: UInt16? = nil
    ) -> Bool {
        guard keyCode == UInt16(kVK_Escape) else { return false }

        let activeModifiers = modifierFlags.intersection(shortcutModifierFlags)
        let allowedModifiers = allowedModifierFlags.intersection(shortcutModifierFlags)
        if activeModifiers.isEmpty { return true }

        guard recordingShortcutKeyCode != UInt16(kVK_Escape) else { return false }
        return activeModifiers == allowedModifiers
    }

    static func shouldStartCancel(
        isKeyDown: Bool,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        allowedModifierFlags: NSEvent.ModifierFlags = [],
        recordingShortcutKeyCode: UInt16? = nil
    ) -> Bool {
        isKeyDown && shouldCancel(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            allowedModifierFlags: allowedModifierFlags,
            recordingShortcutKeyCode: recordingShortcutKeyCode
        )
    }

    static func isEscape(keyCode: UInt16) -> Bool {
        keyCode == UInt16(kVK_Escape)
    }

    /// Whether a bare Esc belongs to the dictation's card once recording has
    /// stopped — the preparing, transcribing, review and failure cards.
    ///
    /// Those cards float over every app and stay up after the user clicks
    /// elsewhere, so their session-wide tap used to take every Esc typed
    /// anywhere: one meant for vim or a dialog discarded a finished dictation.
    /// Esc is the card's only while the user is plausibly talking to it. An
    /// Esc typed into the card itself (it is key) always is, like Esc in any
    /// dialog. One typed into the app they are dictating into is the card's
    /// only while "Esc cancels dictation" is on — the setting is about Esc
    /// reaching past our own window, not about our window's own keys.
    static func hudShouldTakeEscape(
        escapeCancelsDictation: Bool,
        panelIsKey: Bool,
        frontmostPID: pid_t?,
        pasteTargetPID: pid_t?
    ) -> Bool {
        if panelIsKey { return true }
        guard escapeCancelsDictation else { return false }
        guard let frontmostPID, let pasteTargetPID else { return false }
        return frontmostPID == pasteTargetPID
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

    /// Whether an Escape this state took is still held down.
    var isSwallowing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return awaitingKeyUp
    }
}
