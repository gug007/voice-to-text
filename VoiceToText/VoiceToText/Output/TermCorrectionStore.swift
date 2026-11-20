import Foundation
import Observation

/// The user's corrections and whether the review card offers to remember
/// the fixes they make on it.
/// JSON-encoded into UserDefaults (same pattern as `ActionsStore`).
@Observable
@MainActor
final class TermCorrectionStore {
    static let shared = TermCorrectionStore()

    private enum Keys {
        static let list = "corrections.list.v1"
        static let learnsFromEdits = "corrections.learnsFromEdits"
    }

    private(set) var corrections: [TermCorrection]

    /// Whether fixing a term on the review card gets an offer to remember
    /// the fix. Corrections already in the list are made either way.
    var learnsFromEdits: Bool {
        didSet { UserDefaults.standard.set(learnsFromEdits, forKey: Keys.learnsFromEdits) }
    }

    private init() {
        let defaults = UserDefaults.standard
        learnsFromEdits = defaults.object(forKey: Keys.learnsFromEdits) as? Bool ?? true
        let stored = defaults.data(forKey: Keys.list)
        if let stored, let decoded = try? JSONDecoder().decode([TermCorrection].self, from: stored) {
            corrections = decoded
        } else {
            corrections = []
            if stored != nil {
                // Keep an unreadable blob recoverable by a future version
                // instead of overwriting it with the first correction stored.
                defaults.set(stored, forKey: Keys.list + ".unreadable-backup")
            }
        }
    }

    /// What the user typed over on the review card would change in the
    /// list, for the card to ask about. Stores nothing. Nil when learning is
    /// off or nothing would change.
    func proposal(from edits: [TermEdit]) -> TermCorrectionLearner.Outcome? {
        guard learnsFromEdits, !edits.isEmpty else { return nil }
        let outcome = TermCorrectionLearner.propose(edits, to: corrections, isKnownWord: { KnownWords.contains($0) })
        return outcome.changes ? outcome : nil
    }

    /// Makes the change the user said yes to, in the list as it is now:
    /// Settings may have changed it while the card was asking.
    func accept(_ proposal: TermCorrectionLearner.Outcome) {
        set(proposal.applied(to: corrections))
    }

    /// Adds a correction typed into Settings under `id`, or changes the one
    /// that has it.
    func save(heard: String, replacement: String, id: UUID) {
        var saved = TermCorrection(id: id, heard: heard, replacement: replacement)
        guard saved.isUsable else { return }
        if let existing = corrections.first(where: { $0.id == id }) {
            // Edited by hand, it is the user's own from here on.
            saved.isLearned = existing.isLearned
                && existing.heard == saved.heard && existing.replacement == saved.replacement
        }
        set(TermCorrections.placing(saved, in: corrections))
    }

    func remove(id: UUID) {
        set(corrections.filter { $0.id != id })
    }

    /// Puts the list back as it was: the Undo for a removal in Settings and
    /// for a change the user has just accepted on the review card.
    func restore(_ previous: [TermCorrection]) {
        set(previous)
    }

    private func set(_ updated: [TermCorrection]) {
        guard updated != corrections else { return }
        corrections = updated
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: Keys.list)
    }
}
