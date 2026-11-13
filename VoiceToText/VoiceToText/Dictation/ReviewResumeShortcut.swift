import Foundation

/// ⌘R on the review card, matched the way AppKit matches a menu key
/// equivalent rather than by the character the key types.
///
/// `charactersIgnoringModifiers` is the unmodified layer of the active layout,
/// so on a Russian (or any Cyrillic) layout the R key reports "к" and a plain
/// `== "r"` test leaves ⌘R dead. Those layouts map their ⌘ layer to Latin,
/// which is how every menu's ⌘R keeps working on them — so the ⌘-layer
/// characters are accepted too. A bare key-code match would fix Cyrillic and
/// break Dvorak, whose R lives on a different physical key.
nonisolated enum ReviewResumeShortcut {
    /// - Parameters:
    ///   - isCommandOnly: ⌘ is the only device-independent modifier down.
    ///   - charactersIgnoringModifiers: `NSEvent.charactersIgnoringModifiers`.
    ///   - commandLayerCharacters: `NSEvent.characters(byApplyingModifiers: .command)`.
    static func matches(
        isCommandOnly: Bool,
        charactersIgnoringModifiers: String?,
        commandLayerCharacters: String?
    ) -> Bool {
        isCommandOnly && matchesKeyEquivalent(
            "r",
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            commandLayerCharacters: commandLayerCharacters
        )
    }

    /// `letter` on either the unmodified layer or the ⌘ layer.
    fileprivate static func matchesKeyEquivalent(
        _ letter: String,
        charactersIgnoringModifiers: String?,
        commandLayerCharacters: String?
    ) -> Bool {
        charactersIgnoringModifiers?.lowercased() == letter
            || commandLayerCharacters?.lowercased() == letter
    }
}

/// ⇧⌘C on the review card: Copy, matched as `ReviewResumeShortcut` matches
/// ⌘R. Shift is required, so a plain ⌘C still copies the editor's selection.
nonisolated enum ReviewCopyShortcut {
    /// `isCommandShiftOnly`: ⌘ and ⇧ are the only device-independent modifiers down.
    static func matches(
        isCommandShiftOnly: Bool,
        charactersIgnoringModifiers: String?,
        commandLayerCharacters: String?
    ) -> Bool {
        isCommandShiftOnly && ReviewResumeShortcut.matchesKeyEquivalent(
            "c",
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            commandLayerCharacters: commandLayerCharacters
        )
    }
}
