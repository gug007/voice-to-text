import SwiftUI

// MARK: - Icon-only controls
//
// Every glyph-only button in the window goes through these: a 28×28pt hit
// area, a hover / pressed fill, the glyph in `inkMuted` (7:1), and a label
// that is both the tooltip and the VoiceOver name. A bare `Image` in a
// `.plain` button is not allowed.

/// A glyph-only button.
///
/// ```swift
/// IconButton("doc.on.doc", label: "Copy transcript") { copy() }
/// IconButton("trash", label: "Delete recording", role: .destructive) { delete() }
/// IconButton("star.fill", label: "Remove from favorites", tint: Palette.favorite) { … }
/// ```
struct IconButton: View {
    let systemImage: String
    let label: String
    var role: ButtonRole?
    var tint: Color?
    let action: () -> Void

    init(
        _ systemImage: String,
        label: String,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.role = role
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(IconButtonStyle(tint: tint))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// An on/off glyph button (favorite, pin) whose glyph, tint and label follow
/// its state, so VoiceOver and the tooltip say what a click will do.
///
/// ```swift
/// IconToggle(
///     isOn: $entry.isFavorited,
///     on: ("star.fill", "Remove from Favorites"),
///     off: ("star", "Add to Favorites"),
///     onTint: Palette.favorite
/// )
/// ```
struct IconToggle: View {
    @Binding var isOn: Bool
    let on: (systemImage: String, label: String)
    let off: (systemImage: String, label: String)
    var onTint: Color?

    var body: some View {
        let state = isOn ? on : off
        IconButton(state.systemImage, label: state.label, tint: isOn ? onTint : nil) {
            isOn.toggle()
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The style behind `IconButton`; usable directly on a `Button` whose label is
/// an `Image` — but then add `.help` and `.accessibilityLabel` yourself.
struct IconButtonStyle: ButtonStyle {
    var tint: Color?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.minimum, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? (tint ?? Palette.inkMuted) : Palette.inkFaint)
            // Never smaller than 28×28, whatever the glyph.
            .frame(minWidth: FormMetrics.iconButton, minHeight: FormMetrics.iconButton)
            .background(shape.fill(fill(isPressed: configuration.isPressed)))
            .contentShape(Rectangle())
            .onHover { isHovering = isEnabled && $0 }
            .animation(motion.hover, value: isHovering)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return Palette.ink.opacity(0.14) }
        return isHovering ? Palette.wellFill : .clear
    }
}

/// A glyph-only pull-down menu (the row "⋯" menu) with the same 28×28 hit
/// area, hover fill and labelling as `IconButton`.
///
/// ```swift
/// IconMenu(label: "More actions") {
///     Button("Copy") { … }
///     Button("Show in Finder") { … }
///     Divider()
///     Button("Delete", role: .destructive) { … }
/// }
/// ```
struct IconMenu<Content: View>: View {
    var systemImage: String = "ellipsis"
    let label: String
    @ViewBuilder var content: Content

    init(_ systemImage: String = "ellipsis", label: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.label = label
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: systemImage)
        }
        .menuStyle(.button)
        .buttonStyle(IconButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help(label)
        .accessibilityLabel(label)
    }
}
