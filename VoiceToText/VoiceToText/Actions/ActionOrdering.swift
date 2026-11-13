import Foundation

/// Order rules for the action list: moves, the ⌘ numbers the Actions pane and
/// the review card read off that order, and putting a deleted action back
/// where it was.
nonisolated enum ActionOrdering {
    /// The review card binds ⌘1–⌘9; actions past the ninth have no shortcut.
    static let maxShortcuts = 9

    /// Moves one action so it lands before whatever sat at `offset` in the
    /// original list (`offset == count` puts it last) — the same convention as
    /// SwiftUI's `move(fromOffsets:toOffset:)`.
    static func moving(_ id: UUID, toOffset offset: Int, in actions: [DictationAction]) -> [DictationAction] {
        guard let from = actions.firstIndex(where: { $0.id == id }) else { return actions }
        var result = actions
        let action = result.remove(at: from)
        let to = offset > from ? offset - 1 : offset
        result.insert(action, at: max(0, min(to, result.count)))
        return result
    }

    /// Drops `id` beside `targetID`: just before it, or just after it.
    static func moving(_ id: UUID, besides targetID: UUID, after: Bool, in actions: [DictationAction]) -> [DictationAction] {
        guard let target = actions.firstIndex(where: { $0.id == targetID }) else { return actions }
        return moving(id, toOffset: after ? target + 1 : target, in: actions)
    }

    /// Whether dropping `id` beside `targetID` would change the order at all.
    static func reorders(_ id: UUID, besides targetID: UUID, after: Bool, in actions: [DictationAction]) -> Bool {
        guard let from = actions.firstIndex(where: { $0.id == id }),
              let target = actions.firstIndex(where: { $0.id == targetID }) else { return false }
        let offset = after ? target + 1 : target
        return offset != from && offset != from + 1
    }

    static func movingUp(_ id: UUID, in actions: [DictationAction]) -> [DictationAction] {
        swapping(id, withNeighbourAt: -1, in: actions)
    }

    static func movingDown(_ id: UUID, in actions: [DictationAction]) -> [DictationAction] {
        swapping(id, withNeighbourAt: 1, in: actions)
    }

    private static func swapping(_ id: UUID, withNeighbourAt step: Int, in actions: [DictationAction]) -> [DictationAction] {
        guard let index = actions.firstIndex(where: { $0.id == id }),
              actions.indices.contains(index + step) else { return actions }
        var result = actions
        result.swapAt(index, index + step)
        return result
    }

    /// The ⌘ number each action answers to on the review card: its place among
    /// the enabled actions, counted from 1. Absent when it is off or past ⌘9.
    static func shortcutNumbers(in actions: [DictationAction]) -> [UUID: Int] {
        let numbered = actions.lazy.filter(\.isEnabled).prefix(maxShortcuts).map(\.id)
        return Dictionary(zip(numbered, 1...), uniquingKeysWith: { first, _ in first })
    }

    /// Undo for a delete: back at the index it was removed from, or last when
    /// the list has since shrunk below it.
    static func restoring(_ action: DictationAction, at index: Int, in actions: [DictationAction]) -> [DictationAction] {
        guard !actions.contains(where: { $0.id == action.id }) else { return actions }
        var result = actions
        result.insert(action, at: max(0, min(index, result.count)))
        return result
    }
}
