import Foundation

/// Whether a missing API key is worth a warning: only when something the user
/// chose runs on it. Insights are left out; they say so where they are asked for.
nonisolated enum ProviderKeyNeed: Equatable, Sendable {
    case neutral
    case needed(Reason)

    enum Reason: Equatable, Sendable {
        case dictationModel(name: String)
        case conversations
        case secondShortcut
        case actions
    }

    static func evaluate(
        provider: CloudProvider,
        hasKey: Bool,
        dictationModelProvider: CloudProvider?,
        dictationModelName: String?,
        conversationModelProvider: CloudProvider?,
        secondShortcutModelProvider: CloudProvider?,
        enabledActionCount: Int
    ) -> ProviderKeyNeed {
        guard !hasKey else { return .neutral }
        if dictationModelProvider == provider {
            return .needed(.dictationModel(name: dictationModelName ?? "dictation"))
        }
        if conversationModelProvider == provider { return .needed(.conversations) }
        if secondShortcutModelProvider == provider { return .needed(.secondShortcut) }
        if provider == .openAI, enabledActionCount > 0 { return .needed(.actions) }
        return .neutral
    }

    var isNeeded: Bool {
        if case .needed = self { return true }
        return false
    }

    /// "Needed for GPT Transcribe", "Needed for conversations", "Needed for
    /// the second shortcut", "Needed for Actions"; nil when neutral.
    var statusText: String? {
        guard case .needed(let reason) = self else { return nil }
        switch reason {
        case .dictationModel(let name): return "Needed for \(name)"
        case .conversations: return "Needed for conversations"
        case .secondShortcut: return "Needed for the second shortcut"
        case .actions: return "Needed for Actions"
        }
    }
}
