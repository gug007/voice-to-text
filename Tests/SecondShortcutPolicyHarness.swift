import Foundation

struct SecondShortcutHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SecondShortcutHarnessFailure(description: message)
    }
}

@main
struct SecondShortcutPolicyHarness {
    static func main() throws {
        let optionSpace = ShortcutKey(keyCode: 49, modifiers: 2048)
        let optionShiftD = ShortcutKey(keyCode: 2, modifiers: 2048 | 512)
        let controlOptionR = ShortcutKey(keyCode: 15, modifiers: 4096 | 2048)

        let bindings: [ShortcutSlot: ShortcutKey] = [
            .dictation: optionSpace,
            .secondDictation: optionShiftD,
            .conversation: controlOptionR,
        ]

        try expect(
            ShortcutConflicts.owner(of: optionSpace, assigningTo: .secondDictation, bindings: bindings) == .dictation,
            "the second shortcut can't take the dictation shortcut's key"
        )
        try expect(
            ShortcutConflicts.owner(of: controlOptionR, assigningTo: .secondDictation, bindings: bindings) == .conversation,
            "the second shortcut can't take the conversation shortcut's key"
        )
        try expect(
            ShortcutConflicts.owner(of: optionShiftD, assigningTo: .dictation, bindings: bindings) == .secondDictation,
            "the dictation shortcut can't take the second shortcut's key"
        )
        try expect(
            ShortcutConflicts.owner(of: optionShiftD, assigningTo: .conversation, bindings: bindings) == .secondDictation,
            "the conversation shortcut can't take the second shortcut's key"
        )
        try expect(
            ShortcutConflicts.owner(of: optionShiftD, assigningTo: .secondDictation, bindings: bindings) == nil,
            "a shortcut never conflicts with its own key"
        )
        try expect(
            ShortcutConflicts.owner(
                of: ShortcutKey(keyCode: 49, modifiers: 2048 | 512),
                assigningTo: .secondDictation,
                bindings: bindings
            ) == nil,
            "the same key with different modifiers is free"
        )
        try expect(
            ShortcutConflicts.owner(of: controlOptionR, assigningTo: .secondDictation, bindings: [.dictation: optionSpace]) == nil,
            "an unset slot holds no key"
        )

        try expect(ShortcutSlot.dictation.allowsStandaloneModifier, "only dictation may be Right Control alone")
        try expect(!ShortcutSlot.secondDictation.allowsStandaloneModifier, "the second shortcut needs a modifier or function key")
        try expect(!ShortcutSlot.conversation.allowsStandaloneModifier, "the conversation shortcut needs a modifier or function key")
        try expect(
            ShortcutSlot.dictation.inUseMessage == "That shortcut is already used for dictation."
                && ShortcutSlot.conversation.inUseMessage == "That shortcut is already used for conversation recording.",
            "the existing conflict messages are kept word for word"
        )

        let candidates = [
            SecondShortcutModel.Candidate(id: "parakeet", isReady: true),
            SecondShortcutModel.Candidate(id: "whisper-turbo", isReady: false),
            SecondShortcutModel.Candidate(id: "gpt-transcribe", isReady: true),
        ]
        try expect(
            SecondShortcutModel.defaultModelID(candidates: candidates, activeModelID: "parakeet") == "gpt-transcribe",
            "the default is the first ready model that isn't the active one"
        )
        try expect(
            SecondShortcutModel.defaultModelID(candidates: candidates, activeModelID: "gpt-transcribe") == "parakeet",
            "catalog order decides between ready models"
        )
        try expect(
            SecondShortcutModel.defaultModelID(
                candidates: [
                    SecondShortcutModel.Candidate(id: "parakeet", isReady: true),
                    SecondShortcutModel.Candidate(id: "whisper-turbo", isReady: false),
                ],
                activeModelID: "parakeet"
            ) == "whisper-turbo",
            "with nothing else ready, the first other model is the default"
        )
        try expect(
            SecondShortcutModel.defaultModelID(
                candidates: [SecondShortcutModel.Candidate(id: "parakeet", isReady: true)],
                activeModelID: "parakeet"
            ) == nil,
            "no other model means no default"
        )

        print("Second shortcut policy harness passed")
    }
}
