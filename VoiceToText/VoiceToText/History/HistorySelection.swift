import Foundation

/// The History pane's multi-select state and the rules its bottom bar reads:
/// which rows are selected, the anchor a ⇧-click extends from, and the
/// labels and clipboard text the batch actions produce. Foundation-only so
/// the harness can drive it without SwiftUI.
nonisolated struct HistorySelection: Equatable {
    private(set) var selected: Set<UUID> = []
    /// The row a ⇧-click extends from: the last one toggled.
    private(set) var anchor: UUID?

    var count: Int { selected.count }

    func contains(_ id: UUID) -> Bool { selected.contains(id) }

    mutating func toggle(_ id: UUID) {
        if selected.remove(id) == nil { selected.insert(id) }
        anchor = id
    }

    /// Adds every row from the anchor to `id`, inclusive, in the order the list
    /// shows them. Without an anchor still on screen it is a plain toggle.
    mutating func extend(to id: UUID, over ordered: [UUID]) {
        guard let anchor,
              let from = ordered.firstIndex(of: anchor),
              let to = ordered.firstIndex(of: id)
        else {
            toggle(id)
            return
        }
        selected.formUnion(ordered[min(from, to)...max(from, to)])
    }

    mutating func selectAll(_ ordered: [UUID]) {
        selected = Set(ordered)
    }

    /// Drops whatever a filter, a search or a deletion elsewhere took off screen.
    mutating func prune(toVisible visible: [UUID]) {
        let visibleSet = Set(visible)
        selected.formIntersection(visibleSet)
        if let anchor, !visibleSet.contains(anchor) { self.anchor = nil }
    }

    mutating func clear() {
        selected = []
        anchor = nil
    }

    // MARK: - Bar copy

    static func countLabel(_ count: Int) -> String {
        count == 0 ? "Select recordings" : "\(count) selected"
    }

    /// The Favorite button unstars only when every selected row already wears
    /// a star; a mixed selection stars the rest.
    static func unfavorites(_ favoriteFlags: [Bool]) -> Bool {
        !favoriteFlags.isEmpty && favoriteFlags.allSatisfy { $0 }
    }

    static func favoriteTitle(_ favoriteFlags: [Bool]) -> String {
        unfavorites(favoriteFlags) ? "Unfavorite" : "Favorite"
    }

    static func deletionTitle(count: Int) -> String {
        count == 1 ? "1 recording deleted" : "\(count) recordings deleted"
    }

    struct CopyItem {
        let createdAt: Date
        let dateLine: String
        /// Nil for a row with no transcript of its own.
        let transcript: String?
    }

    /// Oldest first, each transcript under its date line, a blank line between
    /// them. Rows with nothing to copy are skipped; nil when none are left.
    static func copyText(_ items: [CopyItem]) -> String? {
        let blocks = items.enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt
                    ? lhs.offset < rhs.offset
                    : lhs.element.createdAt < rhs.element.createdAt
            }
            .compactMap { _, item -> String? in
                guard let text = item.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                return "\(item.dateLine)\n\(text)"
            }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
    }
}
