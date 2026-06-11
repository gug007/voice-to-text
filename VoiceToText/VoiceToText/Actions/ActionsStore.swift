import Foundation
import Observation

/// Persisted list of dictation actions, each individually toggleable.
/// JSON-encoded into UserDefaults (same pattern as `HotkeyStore`).
@Observable
@MainActor
final class ActionsStore {
    static let shared = ActionsStore()

    private enum Keys {
        static let list = "actions.list.v1"
        static let seededTemplates = "actions.seededTemplates.v1"
    }

    private(set) var actions: [DictationAction]

    private init() {
        let stored = UserDefaults.standard.data(forKey: Keys.list)
        let decoded = stored.flatMap { try? JSONDecoder().decode([DictationAction].self, from: $0) }

        if let decoded {
            // Reconcile with the catalog so template changes shipped in code
            // reach this install (user-edited and deleted actions excluded).
            let outcome = ActionCatalogSync.sync(
                stored: decoded,
                seededTemplateIds: UserDefaults.standard.stringArray(forKey: Keys.seededTemplates),
                templates: ActionCatalog.defaults
            )
            actions = outcome.actions
            if outcome.changed {
                persist()
                UserDefaults.standard.set(outcome.seededTemplateIds, forKey: Keys.seededTemplates)
            }
            return
        }

        // First launch (or unreadable blob): seed the built-in defaults so
        // the feature is discoverable with working examples — disabled, so
        // nothing changes in the review panel until the user opts in. A list
        // the user emptied on purpose persists as "[]" and stays empty.
        actions = ActionCatalog.defaults.map { $0.makeAction(isEnabled: false) }
        if stored != nil {
            // Keep an unreadable blob recoverable by a future version
            // instead of silently overwriting it with the reseed.
            UserDefaults.standard.set(stored, forKey: Keys.list + ".unreadable-backup")
        }
        // Persist the seed now so memory and disk never diverge.
        persist()
        UserDefaults.standard.set(ActionCatalog.defaults.map(\.id), forKey: Keys.seededTemplates)
    }

    /// The actions shown as chips in the review HUD, in list order.
    /// ⌘1–⌘9 index into this list, not the full one.
    var enabledActions: [DictationAction] {
        actions.filter(\.isEnabled)
    }

    /// Whether the review HUD should show the action chips row. Requires at
    /// least one enabled action and an OpenAI key (actions run on the
    /// OpenAI API regardless of the transcription model).
    var showsInReview: Bool {
        !enabledActions.isEmpty && OpenAIAPIKeyStore.shared.hasKey
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[index].isEnabled = enabled
        persist()
    }

    func add(_ action: DictationAction) {
        actions.append(action)
        persist()
    }

    func update(_ action: DictationAction) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        var updated = action
        // The edit sheet doesn't know about template linkage — carry it over,
        // and mark real edits so catalog updates stop overwriting this action.
        updated.templateId = actions[index].templateId
        updated.isUserEdited = actions[index].isUserEdited
            || actions[index].name != action.name
            || actions[index].prompt != action.prompt
        actions[index] = updated
        persist()
    }

    func remove(id: UUID) {
        actions.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        UserDefaults.standard.set(data, forKey: Keys.list)
    }
}
