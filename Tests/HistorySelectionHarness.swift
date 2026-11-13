import Foundation

struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String
) throws {
    if actual != expected {
        throw HarnessFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

@main
struct HistorySelectionHarness {
    static let ids = (0..<6).map { _ in UUID() }

    static func main() throws {
        try testToggle()
        try testExtendForward()
        try testExtendBackwardAddsToSelection()
        try testExtendWithoutAnchorToggles()
        try testExtendAfterAnchorFilteredOut()
        try testSelectAllAndOrder()
        try testPrune()
        try testLabels()
        try testFavoriteRule()
        try testCopyText()
        print("HistorySelectionHarness: all checks passed")
    }

    private static func testToggle() throws {
        var selection = HistorySelection()
        try expect(selection.count, 0, "starts empty")
        selection.toggle(ids[1])
        try expect(selection.contains(ids[1]), true, "toggle selects")
        try expect(selection.anchor, ids[1], "toggle sets the anchor")
        selection.toggle(ids[1])
        try expect(selection.contains(ids[1]), false, "second toggle deselects")
        try expect(selection.anchor, ids[1], "deselecting still moves the anchor")
    }

    private static func testExtendForward() throws {
        var selection = HistorySelection()
        selection.toggle(ids[1])
        selection.extend(to: ids[4], over: ids)
        try expect(selection.selected, Set(ids[1...4]), "extends from anchor to target inclusive")
        try expect(selection.anchor, ids[1], "extending keeps the anchor")
    }

    private static func testExtendBackwardAddsToSelection() throws {
        var selection = HistorySelection()
        selection.toggle(ids[5])
        selection.toggle(ids[3])
        selection.extend(to: ids[0], over: ids)
        try expect(selection.selected, Set(ids[0...3] + [ids[5]]), "backward range adds to what was selected")
    }

    private static func testExtendWithoutAnchorToggles() throws {
        var selection = HistorySelection()
        selection.extend(to: ids[2], over: ids)
        try expect(selection.selected, [ids[2]], "no anchor: a plain toggle")
        try expect(selection.anchor, ids[2], "and it becomes the anchor")
    }

    private static func testExtendAfterAnchorFilteredOut() throws {
        var selection = HistorySelection()
        selection.toggle(ids[0])
        let visible = Array(ids[2...5])
        selection.prune(toVisible: visible)
        try expect(selection.anchor, nil, "an anchor filtered off screen is forgotten")
        selection.extend(to: ids[4], over: visible)
        try expect(selection.selected, [ids[4]], "then ⇧-click toggles")
        selection.extend(to: ids[2], over: visible)
        try expect(selection.selected, Set(ids[2...4]), "range is taken over the visible list only")
    }

    private static func testSelectAllAndOrder() throws {
        var selection = HistorySelection()
        selection.selectAll(Array(ids[0...2]))
        try expect(selection.count, 3, "select all takes the visible list")
        selection.clear()
        try expect(selection, HistorySelection(), "clear resets everything")
    }

    private static func testPrune() throws {
        var selection = HistorySelection()
        selection.selectAll(ids)
        selection.toggle(ids[3])
        selection.toggle(ids[3])
        selection.prune(toVisible: [ids[1], ids[3]])
        try expect(selection.selected, [ids[1], ids[3]], "prune keeps only visible ids")
        try expect(selection.anchor, ids[3], "a visible anchor survives")
        selection.prune(toVisible: [])
        try expect(selection.count, 0, "an empty list empties the selection")
    }

    private static func testLabels() throws {
        try expect(HistorySelection.countLabel(0), "Select recordings", "nothing selected")
        try expect(HistorySelection.countLabel(1), "1 selected", "one")
        try expect(HistorySelection.countLabel(12), "12 selected", "many")
        try expect(HistorySelection.deletionTitle(count: 3), "3 recordings deleted", "batch toast")
        try expect(HistorySelection.deletionTitle(count: 1), "1 recording deleted", "singular toast")
    }

    private static func testFavoriteRule() throws {
        try expect(HistorySelection.favoriteTitle([]), "Favorite", "empty selection reads Favorite")
        try expect(HistorySelection.favoriteTitle([false, true]), "Favorite", "mixed reads Favorite")
        try expect(HistorySelection.favoriteTitle([true, true]), "Unfavorite", "all starred reads Unfavorite")
        try expect(HistorySelection.unfavorites([true]), true, "single starred unfavorites")
        try expect(HistorySelection.unfavorites([false]), false, "single unstarred favorites")
    }

    private static func testCopyText() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            HistorySelection.CopyItem(createdAt: base.addingTimeInterval(120), dateLine: "C", transcript: "third"),
            HistorySelection.CopyItem(createdAt: base, dateLine: "A", transcript: "  first \n"),
            HistorySelection.CopyItem(createdAt: base.addingTimeInterval(60), dateLine: "B", transcript: nil),
            HistorySelection.CopyItem(createdAt: base.addingTimeInterval(90), dateLine: "B2", transcript: "   "),
            HistorySelection.CopyItem(createdAt: base.addingTimeInterval(120), dateLine: "C2", transcript: "fourth"),
        ]
        try expect(
            HistorySelection.copyText(items),
            "A\nfirst\n\nC\nthird\n\nC2\nfourth",
            "oldest first, date lines, blank-line separated, empties skipped, ties keep order"
        )
        try expect(
            HistorySelection.copyText([HistorySelection.CopyItem(createdAt: base, dateLine: "A", transcript: nil)]),
            nil,
            "nothing to copy is nil"
        )
    }
}
