import Foundation

struct ReviewResumeShortcutHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw ReviewResumeShortcutHarnessFailure(description: message)
    }
}

private func matches(_ commandOnly: Bool, _ plain: String?, _ commandLayer: String?) -> Bool {
    ReviewResumeShortcut.matches(
        isCommandOnly: commandOnly,
        charactersIgnoringModifiers: plain,
        commandLayerCharacters: commandLayer
    )
}

@main
struct ReviewResumeShortcutHarness {
    static func main() throws {
        try expect(matches(true, "r", "r"), "US layout ⌘R resumes")
        // Caps Lock is dropped from `isCommandOnly` at the call site; what
        // reaches here is the upper-cased character.
        try expect(matches(true, "R", "R"), "an upper-case R still resumes")
        // Russian: the R key types "к", its ⌘ layer is Latin "r".
        try expect(matches(true, "к", "r"), "Russian layout ⌘R resumes via the ⌘ layer")
        // Dvorak: the key in QWERTY's R position types "p" on both layers, so a
        // key-code match (kVK_ANSI_R) would have fired on ⌘P.
        try expect(!matches(true, "p", "p"), "Dvorak ⌘P (QWERTY R position) does not")
        try expect(!matches(true, "к", "к"), "a Cyrillic ⌘ layer without Latin doesn't match")
        try expect(!matches(true, nil, nil), "no characters → no match")
        try expect(!matches(false, "r", "r"), "⌘⇧R / ⌥R / bare R do not resume")
        print("Review resume shortcut harness passed")
    }
}
