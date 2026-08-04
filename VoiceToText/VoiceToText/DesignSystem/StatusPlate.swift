import SwiftUI

// MARK: - Status, as data
//
// The General pane used to carry three near-identical hand-built permission
// cards (glyph + title + subtitle + optional button, each in its own card), and
// the Cloud / Conversations / Actions / Updates panes each invented their own
// variant of the same block. `StatusItem` makes it data and `StatusPlate`
// renders N of them inside ONE `Plate`, so diagnostics read as one group rather
// than as three settings.

/// One row of a `StatusPlate`. The level picks both the glyph and the tint, so
/// no pane can invent its own green.
struct StatusItem: Identifiable {
    let id: String
    var level: StatusLevel
    var title: String
    var message: String?
    /// The fix. Omit both and the row renders without a trailing control.
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        id: String,
        level: StatusLevel,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.level = level
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
}

/// A group of `StatusRow`s in one `Plate`, hairline-separated. Empty input
/// renders nothing, so a pane can hand it a filtered array without guarding.
struct StatusPlate: View {
    let items: [StatusItem]

    init(_ items: [StatusItem]) {
        self.items = items
    }

    var body: some View {
        if !items.isEmpty {
            Plate {
                VStack(alignment: .leading, spacing: Space.s5) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { PlateDivider(leadingInset: 0) }
                        StatusRow(item.level, title: item.title, message: item.message) {
                            if let actionTitle = item.actionTitle, let action = item.action {
                                Button(actionTitle, action: action)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("StatusPlate") {
    StatusPlate([
        StatusItem(id: "hotkey", level: .ready, title: "Global hotkey",
                   message: "⌥Space is registered and will work from any app."),
        StatusItem(id: "mic", level: .ready, title: "Microphone",
                   message: PermissionCopy.microphoneGranted),
        StatusItem(id: "a11y", level: .warning, title: "Accessibility",
                   message: PermissionCopy.accessibilityPurpose,
                   actionTitle: PermissionCopy.openSettingsShortButton) {}
    ])
    .padding(Space.s7)
    .frame(width: 520)
    .background(Palette.canvas)
    .motionEnvironment()
}
#endif
