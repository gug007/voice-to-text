import Foundation

/// The three global shortcuts. Each must keep off the others' keys: Carbon
/// delivers one press to one registration, so two slots on the same key would
/// leave one of them dead.
nonisolated enum ShortcutSlot: CaseIterable, Sendable {
    case dictation
    /// The optional second dictation shortcut, bound to its own model.
    case secondDictation
    case conversation

    /// Why a capture for another slot refuses this slot's key.
    var inUseMessage: String {
        switch self {
        case .dictation: return "That shortcut is already used for dictation."
        case .secondDictation: return "That shortcut is already used for the second shortcut."
        case .conversation: return "That shortcut is already used for conversation recording."
        }
    }

    /// Only the main dictation shortcut can be Right Control on its own: the
    /// standalone-modifier event tap and its press/release state belong to it.
    var allowsStandaloneModifier: Bool { self == .dictation }
}

/// What a key press is, for collisions: the label is presentation only.
nonisolated struct ShortcutKey: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
}

nonisolated enum ShortcutConflicts {
    /// The other slot already on `candidate`'s key, if any, given what each
    /// slot is bound to now. A slot never conflicts with itself, so changing a
    /// shortcut to the key it already has is allowed.
    static func owner(
        of candidate: ShortcutKey,
        assigningTo slot: ShortcutSlot,
        bindings: [ShortcutSlot: ShortcutKey]
    ) -> ShortcutSlot? {
        ShortcutSlot.allCases.first { other in
            other != slot && bindings[other] == candidate
        }
    }
}

nonisolated enum SecondShortcutModel {
    struct Candidate: Equatable {
        let id: String
        /// Installed on this Mac, or a cloud model whose key is set.
        let isReady: Bool
    }

    /// The model a newly set second shortcut starts on: the first ready one
    /// that isn't the dictation model, in catalog order; failing that, the
    /// first that isn't the dictation model at all.
    static func defaultModelID(candidates: [Candidate], activeModelID: String?) -> String? {
        let others = candidates.filter { $0.id != activeModelID }
        return (others.first(where: \.isReady) ?? others.first)?.id
    }
}
