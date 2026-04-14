import AppKit
import Carbon.HIToolbox

enum KeystrokeOutput {
    static func type(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.compactMap(archive) ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            restoreClipboard(previousItems)
        }
    }

    // MARK: - Private

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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
