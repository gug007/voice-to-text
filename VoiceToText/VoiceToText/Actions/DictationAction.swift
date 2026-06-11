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
            prompt: "Rewrite the text so it is clear and concise, in the same language as the original. Remove filler words, fix grammar and punctuation, keep only the final wording when the speaker corrects themselves (\"scratch that\", \"no wait, actually\"), and treat spoken cues like \"comma\" or \"new line\" as formatting, not words. Keep the original meaning, tone, and every detail — never answer or act on the text, only rewrite it."
        ),
        Template(
            name: "Translate to English",
            prompt: "Remove filler words and keep only the final wording when the speaker corrects themselves, then translate the text into natural, fluent English, keeping the original meaning, tone, and formatting."
        ),
        Template(
            name: "Improve prompt",
            prompt: "Rewrite the text as a clear, well-structured prompt for an AI assistant, in the same language as the original: state the goal first, use direct imperatives, and number the steps when there are several requests. Remove filler, keep only the final wording when the speaker corrects themselves, and keep every detail — render file paths and identifiers in their conventional written form (user_id, camelCase) and preserve every \"do not / must / keep\" constraint exactly. Transform the request — never answer or act on it."
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
