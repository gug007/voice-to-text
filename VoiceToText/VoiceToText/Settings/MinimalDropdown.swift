import AppKit
import SwiftUI

// MARK: - The one in-row picker
//
// `MinimalDropdown` is the app's single in-row choice control: a native
// `NSPopUpButton` (bordered pop-up, system up/down chevron), so the
// microphone, model and every other in-row picker look the same and match
// the native menus in the toolbars. AppKit rather than `Picker(.menu)` for one
// reason: a menu item's `detail` / `caption` go in its subtitle, so the open
// menu explains each choice while the closed control shows just the title.
//
// `DropdownPopup` (below) is a separate custom action list hosted from a
// caller's own `.popover` — see the regenerate control in `RecordingRow`.

// MARK: - Data model

/// One selectable item. `title` (and `systemImage`) show on the closed
/// control and in the menu; `detail` and `caption` appear only in the open
/// menu, as the item's subtitle ("Currently MacBook Pro Microphone",
/// "Not downloaded"). `value` doubles as identity.
struct DropdownItem<Value: Hashable> {
    let value: Value
    let title: String
    var detail: String? = nil
    var caption: String? = nil
    var systemImage: String? = nil

    /// The open menu's second line for this item, if any.
    var subtitle: String? {
        let parts = [detail, caption].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A group of items under an optional Title Case header (e.g. "On this Mac",
/// "OpenAI"). Sections without a header are separated by a divider.
struct DropdownSection<Value: Hashable> {
    var header: String? = nil
    let items: [DropdownItem<Value>]
}

extension DropdownSection {
    /// Models as picker sections: one per group (On this Mac, then each
    /// provider) with no headers, each item "Name · Provider" with its
    /// cloud / laptop glyph. `caption` adds a note such as "Not downloaded".
    ///
    /// ```swift
    /// MinimalDropdown(
    ///     selection: $modelID,
    ///     sections: .models(ModelCatalog.all, value: \.id) { readinessNote($0) }
    /// )
    /// ```
    static func models(
        _ models: [ModelDescriptor],
        value: (ModelDescriptor) -> Value,
        caption: (ModelDescriptor) -> String? = { _ in nil }
    ) -> [DropdownSection<Value>] {
        ModelGroup.sections(of: models).map { section in
            DropdownSection(items: section.models.map { model in
                DropdownItem(
                    value: value(model),
                    title: model.nameWithSource,
                    caption: caption(model),
                    systemImage: model.sourceSymbol
                )
            })
        }
    }
}

// MARK: - Bound select control

/// The native pop-up over `sections`, at most `maxWidth` wide (longer titles
/// truncate on the closed control only). Pass `title` — the row title — so
/// VoiceOver names the pop-up, and `tooltip` for its help text; SwiftUI's own
/// `.accessibilityLabel` / `.help` don't reach the AppKit control. `.disabled`
/// and `.controlSize` do.
///
/// ```swift
/// SettingsRow("Microphone", caption: caption) {
///     MinimalDropdown(selection: $uid, sections: sections, title: "Microphone")
/// }
/// ```
struct MinimalDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let sections: [DropdownSection<Value>]
    /// Shown only if the selection matches no item.
    var placeholder: String = "Select"
    /// Kept for source compatibility; the native menu sizes itself.
    var popupWidth: CGFloat = 280
    /// Kept for source compatibility; the native menu sizes itself.
    var maxPopupHeight: CGFloat = 360
    /// The pop-up's accessibility label (usually the row title).
    var title: String? = nil
    /// The pop-up's tooltip.
    var tooltip: String? = nil

    /// Widest a closed in-row picker gets.
    static var maxWidth: CGFloat { 240 }

    var body: some View {
        NativePopUp(
            selection: AnyHashable(selection),
            sections: sections.map { section in
                NativePopUp.Section(
                    header: section.header,
                    items: section.items.map {
                        NativePopUp.Item(
                            value: AnyHashable($0.value),
                            title: $0.title,
                            subtitle: $0.subtitle,
                            systemImage: $0.systemImage
                        )
                    }
                )
            },
            placeholder: placeholder,
            maxWidth: Self.maxWidth,
            title: title,
            tooltip: tooltip
        ) { picked in
            if let value = picked.base as? Value { selection = value }
        }
    }
}

/// `NSPopUpButton`, rebuilt only when its items change. Each item carries its
/// value boxed in `representedObject` (`DropdownValueBox`), so a pick from a
/// menu that was open across a rebuild still resolves to the item the user saw.
private struct NativePopUp: NSViewRepresentable {
    struct Item: Equatable {
        let value: AnyHashable
        let title: String
        let subtitle: String?
        let systemImage: String?
    }

    struct Section: Equatable {
        let header: String?
        let items: [Item]
    }

    let selection: AnyHashable
    let sections: [Section]
    let placeholder: String
    let maxWidth: CGFloat
    let title: String?
    let tooltip: String?
    let onPick: (AnyHashable) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.lineBreakMode = .byTruncatingTail
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPick = onPick

        // SwiftUI's environment doesn't flow into an AppKit control by itself.
        button.isEnabled = context.environment.isEnabled
        let size = Self.controlSize(context.environment.controlSize)
        if button.controlSize != size {
            button.controlSize = size
            button.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
        }
        button.setAccessibilityLabel(title)
        button.toolTip = tooltip

        let isListed = sections.contains { $0.items.contains { $0.value == selection } }
        if coordinator.sections != sections || coordinator.showsPlaceholder != !isListed {
            coordinator.sections = sections
            coordinator.showsPlaceholder = !isListed
            button.menu = makeMenu(showsPlaceholder: !isListed)
        }
        coordinator.selection = selection
        // The placeholder (when shown) is item 0.
        button.selectItem(at: button.indexOfItem(withBoxedValue: selection) ?? 0)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let ideal = nsView.intrinsicContentSize
        let available = proposal.width ?? .infinity
        let width = max(min(ideal.width, maxWidth, available), min(ideal.width, 80))
        return CGSize(width: width, height: ideal.height)
    }

    private static func controlSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: return .mini
        case .small: return .small
        case .large, .extraLarge: return .large
        default: return .regular
        }
    }

    private func makeMenu(showsPlaceholder: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if showsPlaceholder {
            let item = NSMenuItem(title: placeholder, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for (index, section) in sections.enumerated() {
            if index > 0 || showsPlaceholder { menu.addItem(.separator()) }
            if let header = section.header {
                menu.addItem(.sectionHeader(title: header))
            }
            for entry in section.items {
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.subtitle = entry.subtitle
                if let symbol = entry.systemImage {
                    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                item.representedObject = DropdownValueBox(entry.value)
                menu.addItem(item)
            }
        }
        return menu
    }

    final class Coordinator: NSObject {
        var sections: [Section] = []
        var showsPlaceholder = false
        var selection: AnyHashable?
        var onPick: (AnyHashable) -> Void = { _ in }

        @objc func picked(_ sender: NSPopUpButton) {
            // A menu opened before the control was locked must not slip a
            // pick through; put the shown item back instead.
            guard sender.isEnabled, let value = sender.selectedBoxedValue else {
                if let selection { sender.selectItem(at: sender.indexOfItem(withBoxedValue: selection) ?? 0) }
                return
            }
            onPick(value)
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
                            .font(Typo.sidebarHeader)
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
                        .typo(.caption)
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
