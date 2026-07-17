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
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(selectedTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.09 : 0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
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
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    if let header = section.header {
                        Text(header.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.top, index == 0 ? 2 : 8)
                            .padding(.bottom, 1)
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
            .padding(6)
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
    }
}

// MARK: - Row

private struct DropdownRow: View {
    let title: String
    let detail: String?
    let caption: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
        }
    }

    private var rowFill: Color {
        if isHovering { return Color.primary.opacity(0.08) }
        if isSelected { return Color.accentColor.opacity(0.10) }
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
