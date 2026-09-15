import Foundation
import Observation

/// One instruction the user has typed at a transcript ("rewrite this as meeting
/// minutes"), kept so it can be offered back for one-tap reuse.
///
/// The id is stable across re-runs of the same instruction — see
/// `InsightPromptList.remembering` — so a list row keeps its identity (and its
/// swipe state, and its place in an animation) when using it moves it to the
/// front.
nonisolated struct InsightPrompt: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let instruction: String
    /// When it was last run. The sort key, and the only thing a re-run of an
    /// instruction already in the list changes.
    let lastUsed: Date

    init(id: UUID = UUID(), instruction: String, lastUsed: Date) {
        self.id = id
        self.instruction = instruction
        self.lastUsed = lastUsed
    }
}

/// The list arithmetic behind `InsightPromptStore`, as a pure function.
///
/// Separated from the store for the same reason `TranscriptEditor` is separated
/// from `RecordingHistoryStore`: the interesting part is the dedupe rule and the
/// cap, and neither should only be verifiable by launching the app and typing
/// the same sentence nine times. This half compiles standalone, so the harness
/// pins it down.
nonisolated enum InsightPromptList {
    /// How many instructions are remembered. Small on purpose: this is a
    /// convenience list under a text field, not a library. Past eight the user
    /// scans a list instead of typing the sentence again, which is the thing
    /// the list was supposed to save them.
    static let maxPrompts = 8

    /// What "the same instruction" means. Trimmed and case-folded, so
    /// "Translate to Russian" typed again with a capital T is the same request,
    /// not a second entry. Diacritics are deliberately *kept*: unlike a dedupe
    /// of model output, these are the user's own words in their own language,
    /// and folding them would make two genuinely different instructions collide.
    static func key(_ instruction: String) -> String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The list after `instruction` has been run, most recent first.
    ///
    /// An instruction already in the list moves to the front and refreshes its
    /// timestamp rather than appearing twice — a user who reformats five
    /// recordings the same way would otherwise fill the whole list with one
    /// sentence and push out everything else they use. A blank instruction
    /// changes nothing. `id` is only consumed when the instruction is new.
    static func remembering(
        _ instruction: String,
        in prompts: [InsightPrompt],
        id: UUID,
        now: Date
    ) -> [InsightPrompt] {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return prompts }
        let folded = key(trimmed)
        let existing = prompts.first { key($0.instruction) == folded }
        // The freshly typed spelling wins over the stored one (the user may
        // have fixed a typo or a capital), but the id does not: reusing it is
        // what makes this a move rather than a delete-and-insert.
        let head = InsightPrompt(id: existing?.id ?? id, instruction: trimmed, lastUsed: now)
        let rest = prompts.filter { key($0.instruction) != folded }
        return Array(([head] + rest).prefix(maxPrompts))
    }
}

/// The instructions the user has typed at their transcripts, newest first,
/// offered back under the "format with AI" field for one-tap reuse.
///
/// JSON in UserDefaults, exactly like `ActionsStore` and `HotkeyStore`.
///
/// Deliberately *not* `ActionsStore`. The dictation actions list drives the
/// chips in the review HUD, so writing these there would silently add chips to
/// a completely different surface the user never asked to change — a sentence
/// typed once at one recording turning into a permanent button beside every
/// dictation. Two lists, two jobs.
@Observable
@MainActor
final class InsightPromptStore {
    static let shared = InsightPromptStore()

    private enum Keys {
        static let list = "insightPrompts.list.v1"
    }

    /// Most recent first, at most `maxPrompts`.
    private(set) var prompts: [InsightPrompt]

    nonisolated static let maxPrompts = InsightPromptList.maxPrompts

    private init() {
        let stored = UserDefaults.standard.data(forKey: Keys.list)
        let decoded = stored.flatMap { try? JSONDecoder().decode([InsightPrompt].self, from: $0) }
        // Re-capped on load rather than trusted: a build that shipped a larger
        // cap, or a hand-edited defaults blob, must not leave a list the UI
        // cannot lay out.
        prompts = Array((decoded ?? []).prefix(Self.maxPrompts))
    }

    /// Records that the user just ran `instruction`. Called once a request is
    /// actually being sent, not once one succeeds: a sentence that failed on a
    /// timeout or a network blip is exactly the one the user most needs offered
    /// back, and nothing else in the app still holds a copy of it — the form it
    /// was typed in closes before the job starts, and a failed run stores no
    /// result to keep it on. The refusals that cost nothing (a blank
    /// instruction, no API key, the cap, an empty transcript) never get this
    /// far, so the list is not filled with sentences that were never used.
    func remember(_ instruction: String) {
        let updated = InsightPromptList.remembering(
            instruction,
            in: prompts,
            id: UUID(),
            now: Date()
        )
        guard updated != prompts else { return }
        prompts = updated
        persist()
    }

    func forget(id: UUID) {
        guard prompts.contains(where: { $0.id == id }) else { return }
        prompts.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        UserDefaults.standard.set(data, forKey: Keys.list)
    }
}
