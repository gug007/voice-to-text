import Foundation

/// A user-defined transform applied to a transcript from the review HUD:
/// a display name plus the instruction sent to OpenAI alongside the text
/// (e.g. "Translate to English"). Each action toggles individually —
/// only enabled ones appear as chips in the review panel.
nonisolated struct DictationAction: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var prompt: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, prompt: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        // Lists persisted before per-action toggles lack this key; actions
        // stay opt-in, so they come back disabled rather than surprise-on.
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

/// Built-in action templates, seeded into the store on first launch so the
/// feature is discoverable with working examples — disabled, so nothing
/// changes in the review panel until the user opts in.
nonisolated enum ActionCatalog {
    struct Template: Identifiable {
        let name: String
        let prompt: String
        var id: String { name }

        func makeAction(isEnabled: Bool = true) -> DictationAction {
            DictationAction(name: name, prompt: prompt, isEnabled: isEnabled)
        }
    }

    static let defaults: [Template] = [
        Template(
            name: "Clean transcript",
            prompt: "Rewrite the text so it is clear and concise. Remove filler words, fix grammar and punctuation, and keep the original meaning and tone."
        ),
        Template(
            name: "Translate to English",
            prompt: "Translate the text into natural, fluent English. Keep the original meaning, tone, and formatting."
        ),
        Template(
            name: "Improve prompt",
            prompt: "Rewrite the text as a clear, well-structured prompt for an AI assistant. State the goal explicitly, keep every detail and constraint, and remove filler."
        ),
        Template(
            name: "Fix grammar",
            prompt: "Fix grammar, spelling, and punctuation. Keep the wording and tone unchanged otherwise."
        ),
        Template(
            name: "Summarize",
            prompt: "Summarize the text in one or two sentences, keeping the key points."
        ),
        Template(
            name: "Essentials only",
            prompt: "Reduce the text to its essential points. Cut all filler, repetition, and tangents; keep only what is needed to convey the message, in as few words as possible, without changing the meaning."
        ),
    ]
}
