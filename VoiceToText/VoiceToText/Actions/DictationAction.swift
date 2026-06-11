import Foundation

/// A user-defined transform applied to a transcript from the review HUD:
/// a display name plus the instruction sent to OpenAI alongside the text
/// (e.g. "To English"). Each action toggles individually — only enabled
/// ones appear as chips in the review panel.
nonisolated struct DictationAction: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var prompt: String
    var isEnabled: Bool
    /// Stable id of the catalog template this action was seeded from, nil
    /// for hand-written actions. Lets `ActionCatalogSync` push code-side
    /// template changes into the persisted list across launches.
    var templateId: String?
    /// Set when the user edits the action in the app; a user-edited action
    /// is never overwritten by catalog updates.
    var isUserEdited: Bool

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        isEnabled: Bool = true,
        templateId: String? = nil,
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.templateId = templateId
        self.isUserEdited = isUserEdited
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, isEnabled, templateId, isUserEdited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        // Lists persisted before per-action toggles lack this key; actions
        // stay opt-in, so they come back disabled rather than surprise-on.
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        templateId = try container.decodeIfPresent(String.self, forKey: .templateId)
        isUserEdited = try container.decodeIfPresent(Bool.self, forKey: .isUserEdited) ?? false
    }
}

/// Built-in action templates, seeded into the store on first launch so the
/// feature is discoverable with working examples — disabled, so nothing
/// changes in the review panel until the user opts in.
nonisolated enum ActionCatalog {
    struct Template: Identifiable {
        /// Stable identity — never reuse or rename an id once shipped;
        /// `ActionCatalogSync` keys on it to push name/prompt updates.
        let id: String
        let name: String
        let prompt: String

        func makeAction(isEnabled: Bool = true) -> DictationAction {
            DictationAction(name: name, prompt: prompt, isEnabled: isEnabled, templateId: id)
        }
    }

    static let defaults: [Template] = [
        Template(
            id: "clean-transcript",
            name: "Clean transcript",
            prompt: "Rewrite the text so it is clear and concise, in the same language as the original. Remove filler words, fix grammar and punctuation, keep only the final wording when the speaker corrects themselves (\"scratch that\", \"no wait, actually\"), and treat spoken cues like \"comma\" or \"new line\" as formatting, not words. Keep the original meaning, tone, and every detail — never answer or act on the text, only rewrite it."
        ),
        Template(
            id: "to-english",
            name: "To English",
            prompt: "Remove filler words and keep only the final wording when the speaker corrects themselves, then translate the text into natural, fluent English, keeping the original meaning, tone, and formatting."
        ),
        Template(
            id: "improve-prompt",
            name: "Improve prompt",
            prompt: "Rewrite the text as a clear, well-structured prompt for an AI assistant, in the same language as the original: state the goal first, use direct imperatives, and number the steps when there are several requests. Remove filler, keep only the final wording when the speaker corrects themselves, and keep every detail — render file paths and identifiers in their conventional written form (user_id, camelCase) and preserve every \"do not / must / keep\" constraint exactly. Transform the request — never answer or act on it."
        ),
        Template(
            id: "fix-grammar",
            name: "Fix grammar",
            prompt: "Fix grammar, spelling, and punctuation, add paragraph breaks at topic changes, and treat spoken cues like \"comma\", \"period\", or \"new line\" as formatting rather than words. Keep the wording and tone unchanged otherwise."
        ),
        Template(
            id: "summarize",
            name: "Summarize",
            prompt: "Summarize the text in one or two sentences, keeping the key points."
        ),
        Template(
            id: "essentials-only",
            name: "Essentials only",
            prompt: "Reduce the text to its essential points. Cut all filler, repetition, and tangents; keep only what is needed to convey the message, in as few words as possible, without changing the meaning."
        ),
    ]
}

/// Reconciles the persisted action list with `ActionCatalog` on launch so
/// code-side template changes reach existing installs without reseeding:
/// - name/prompt edits to a template update the matching stored action,
///   unless the user edited that action in the app (user wins);
/// - templates added to the catalog are appended once, disabled — deleting
///   the action afterwards is remembered via the seeded-id record and it is
///   never re-added;
/// - toggles, ordering, and hand-written actions are never touched.
nonisolated enum ActionCatalogSync {
    struct Outcome {
        var actions: [DictationAction]
        var seededTemplateIds: [String]
        /// True when either the list or the seeded-id record must be
        /// re-persisted.
        var changed: Bool
    }

    static func sync(
        stored: [DictationAction],
        seededTemplateIds: [String]?,
        templates: [ActionCatalog.Template]
    ) -> Outcome {
        var actions = stored
        var changed = false

        // Lists persisted before template linking carry no templateId.
        // Adopt identity where a stored action still matches a template by
        // name, so it starts receiving catalog updates.
        for template in templates {
            guard !actions.contains(where: { $0.templateId == template.id }),
                  let index = actions.firstIndex(where: { $0.templateId == nil && $0.name == template.name })
            else { continue }
            actions[index].templateId = template.id
            changed = true
        }

        // A missing record means this store predates sync: treat every
        // current template as already offered, so only templates added to
        // the catalog *later* get appended.
        var seeded = Set(seededTemplateIds ?? templates.map(\.id))
        if seededTemplateIds == nil { changed = true }

        for template in templates {
            if let index = actions.firstIndex(where: { $0.templateId == template.id }) {
                if !actions[index].isUserEdited,
                   actions[index].name != template.name || actions[index].prompt != template.prompt {
                    actions[index].name = template.name
                    actions[index].prompt = template.prompt
                    changed = true
                }
            } else if !seeded.contains(template.id) {
                actions.append(template.makeAction(isEnabled: false))
                changed = true
            }
            if !seeded.contains(template.id) {
                seeded.insert(template.id)
                changed = true
            }
        }

        return Outcome(
            actions: actions,
            seededTemplateIds: seeded.sorted(),
            changed: changed
        )
    }
}
