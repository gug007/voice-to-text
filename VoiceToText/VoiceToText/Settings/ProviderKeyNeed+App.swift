import Foundation

extension ProviderKeyNeed {
    /// `evaluate` fed from the app's own settings: the dictation model, the
    /// conversation model as `ConversationModelResolver` resolves it, the
    /// second shortcut's model while that shortcut is set, and the enabled
    /// Actions.
    @MainActor
    static func current(for provider: CloudProvider, registry: ModelRegistry? = nil) -> ProviderKeyNeed {
        let registry = registry ?? ModelRegistry.shared
        let dictation = registry.activeModel
        let hotkeys = HotkeyStore.shared
        let secondShortcutModel = hotkeys.secondBinding == nil
            ? nil
            : hotkeys.secondModelId.flatMap { ModelCatalog.model(for: $0) }
        return evaluate(
            provider: provider,
            hasKey: provider.hasAPIKey,
            dictationModelProvider: dictation?.backend.cloudProvider,
            dictationModelName: dictation?.sectionedDisplayName,
            conversationModelProvider: registry.conversationModel?.backend.cloudProvider,
            secondShortcutModelProvider: secondShortcutModel?.backend.cloudProvider,
            enabledActionCount: ActionsStore.shared.enabledActions.count
        )
    }
}
