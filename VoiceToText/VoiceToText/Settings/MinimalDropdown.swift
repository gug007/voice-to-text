import SwiftUI

/// A modern, minimal replacement for `Picker(.menu)` whose stock NSMenu can't be
/// restyled to match the calm settings chrome. A compact rounded-rect control
/// opens a `.popover` panel of custom rows — optional section headers, a
/// secondary detail line and trailing caption per row, hover highlight, and an
/// accent checkmark on the current selection. The popover gives outside-click
/// and Esc dismissal for free and, unlike an in-view overlay, is never clipped by
/// an enclosing ScrollView.
///
/// `MinimalDropdown` is the two-way-bound select control. Callers that need a
/// different trigger (an icon button, an action list) can host `DropdownPopup`
/// from their own `.popover` for the same visual language — see the regenerate
/// control in `RecordingRow`.

// MARK: - Data model

/// One selectable row. `detail` is a quieter secondary line under the title;
/// `caption` is a trailing right-aligned note. `value` doubles as identity.
struct DropdownItem<Value: Hashable> {
    let value: Value
    let title: String
    var detail: String? = nil
    var caption: String? = nil
}

/// A group of rows under an optional small uppercase header (e.g. "On this Mac",
/// "OpenAI"). A `nil` header renders the rows with no heading.
struct DropdownSection<Value: Hashable> {
    var header: String? = nil
    let items: [DropdownItem<Value>]
}

// MARK: - Bound select control

struct MinimalDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let sections: [DropdownSection<Value>]
    /// Shown on the collapsed control only if the selection matches no item.
    var placeholder: String = "Select"
    var popupWidth: CGFloat = 280
    var maxPopupHeight: CGFloat = 360

    @Environment(\.motion) private var motion

    @State private var isOpen = false
    @State private var isHovering = false

    private var selectedTitle: String {
        for section in sections {
            if let item = section.items.first(where: { $0.value == selection }) {
                return item.title
            }
        }
        return placeholder
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)

        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: Space.s3) {
                Text(selectedTitle)
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(shape.fill(Palette.ink.opacity(isHovering ? 0.09 : 0.05)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
        .animation(motion.hover, value: isHovering)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            DropdownPopup(
                sections: sections,
                selected: selection,
                width: popupWidth,
                maxHeight: maxPopupHeight
            ) { value in
                selection = value
                isOpen = false
            }
        }
    }
}

// MARK: - Popup panel

/// The scrolling row list rendered inside a `.popover`. Sizes its width to the
/// caller's fixed value and its height to the content, capped at `maxHeight` —
/// only then does it scroll, so short lists never show a scroller. Reusable on
/// its own for triggers that aren't the bound select control.
///
/// This is glass surface #4 of the inventory in `GlassSurface.swift` — one call
/// site covering both popovers on the list (the dropdown's own popup and the
/// `RecordingRow` regenerate menu). It is filled edge to edge with a
/// `Rectangle`, not a rounded shape: the popover already clips its content to
/// the system's corner radius, so a rounded fill would only leak the chrome
/// behind it at the corners. The point of routing it through `glassSurface` is
/// that Reduce Transparency now flattens the popup exactly when it flattens the
/// HUD and the toast, instead of leaving two of the four surfaces translucent.
struct DropdownPopup<Value: Hashable>: View {
    let sections: [DropdownSection<Value>]
    /// The value drawn with a checkmark, or `nil` for none.
    let selected: Value?
    var width: CGFloat = 280
    var maxHeight: CGFloat = 360
    let onSelect: (Value) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    if let header = section.header {
                        Text(header)
                            .typo(.micro)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.inkFaint)
                            .padding(.horizontal, Space.s4)
                            .padding(.top, index == 0 ? Space.s1 : Space.s4)
                            .padding(.bottom, Space.s1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(section.items, id: \.value) { item in
                        DropdownRow(
                            title: item.title,
                            detail: item.detail,
                            caption: item.caption,
                            isSelected: selected == item.value
                        ) {
                            onSelect(item.value)
                        }
                    }
                }
            }
            .padding(Space.s3)
            // macOS 15 geometry observer: MainActor-friendly (avoids the
            // @Sendable preference-closure friction under Swift 6 isolation).
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: min(max(contentHeight, 1), maxHeight))
        .glassSurface(in: Rectangle())
    }
}

// MARK: - Row

private struct DropdownRow: View {
    let title: String
    let detail: String?
    let caption: String?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.motion) private var motion

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)

        Button(action: action) {
            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(title)
                        .typo(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s4)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .typo(.mono)
                        .foregroundStyle(Palette.inkFaint)
                }
                Image(systemName: "checkmark")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.accent)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: Space.s5)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(rowFill))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(motion.hover, value: isHovering)
    }

    private var rowFill: Color {
        if isHovering { return Palette.ink.opacity(0.08) }
        if isSelected { return Palette.accent.opacity(0.10) }
        return .clear
    }
}

// MARK: - Presentation helpers

extension ModelDescriptor {
    /// Display name with a trailing " (Provider)" removed — for showing a model
    /// under a provider section header, where the suffix would be redundant.
    /// Presentation-only; the catalog is never mutated. Local models (no cloud
    /// provider) are returned unchanged.
    var sectionedDisplayName: String {
        guard let provider = backend.cloudProvider else { return displayName }
        let suffix = " (\(provider.displayName))"
        return displayName.hasSuffix(suffix)
            ? String(displayName.dropLast(suffix.count))
            : displayName
    }
}
