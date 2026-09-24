import AppKit
import Carbon.HIToolbox
import OSLog

enum KeystrokeOutput {
    /// Pastes `text` into the active app with a synthetic ⌘V, then puts the
    /// user's previous clipboard back.
    ///
    /// Returns whether both key events could be created — the only failure
    /// `CGEventPost` will ever admit to, and so the only one worth logging.
    @discardableResult
    static func type(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.compactMap(archive) ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // The restore below may only undo *our* write. If the clipboard has
        // moved on by then — the user copied something, or the target app
        // wrote to it while handling the paste — restoring would clobber that.
        // This does not protect a ⌘V that was silently dropped: that leaves
        // the pasteboard untouched, so the restore still runs over the
        // transcript. Keeping ⌘V away from where it would be dropped is
        // `PasteFocusPolicy`'s job (its `.copyOnly` path skips this function).
        let transcriptChangeCount = pasteboard.changeCount

        let eventsCreated = postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard NSPasteboard.general.changeCount == transcriptChangeCount else {
                AppLog.dictation.notice("Paste: clipboard restore skipped — the pasteboard changed after the transcript was written")
                return
            }
            restoreClipboard(previousItems)
        }
        return eventsCreated
    }

    /// Puts `text` on the clipboard and nothing else: no ⌘V, no restore. The
    /// fallback for when ⌘V has nowhere safe to go, so the transcript survives
    /// for the user to paste by hand.
    static func copyOnly(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Private

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return keyDown != nil && keyUp != nil
    }

    private static func archive(_ item: NSPasteboardItem) -> [NSPasteboard.PasteboardType: Data]? {
        var bucket: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) {
                bucket[type] = data
            }
        }
        return bucket.isEmpty ? nil : bucket
    }

    private static func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var restoredItems: [NSPasteboardItem] = []
        for bucket in items {
            let item = NSPasteboardItem()
            for (type, data) in bucket {
                item.setData(data, forType: type)
            }
            restoredItems.append(item)
        }
        pasteboard.writeObjects(restoredItems)
    }
}
