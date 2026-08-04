import AppKit
import SwiftUI

// MARK: - Sidebar
//
// The sidebar used to be `List(Section.allCases)` — eight rows in enum
// declaration order, which is to say in no order at all. It is two labelled
// groups now, driven by an explicit array:
//
//   DICTATE    — General, Conversations, History     (what you do)
//   CONFIGURE  — Shortcut, Models, Actions, Cloud, Updates (how it behaves)
//
// Selection is one accent capsule at 28pt row height that *slides* between rows
// via `matchedGeometryEffect` on `Motion.select`, and a 44pt pinned footer
// carries the app mark and the version string.
//
// WHY NOT `List(selection:)`: macOS draws the sidebar selection highlight in the
// NSTableView row view, below anything `.listRowBackground` can reach, so a List
// cannot host a custom capsule — the two highlights would stack. Rows are
// therefore buttons, which also means `\.backgroundProminence` (a List-provided
// value) has nothing to report; the icon/label recolour is derived from
// `isSelected` in exactly one place instead, which is the same guarantee.
// Arrow-key navigation, which the List gave for free, is re-implemented below.

/// One labelled block of sidebar rows.
struct SidebarGroup: Identifiable {
    let title: String
    let sections: [SettingsView.Section]
    var id: String { title }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsView.Section

    @Namespace private var selectionPill
    @FocusState private var isFocused: Bool
    @Environment(\.motion) private var motion

    /// Flattened row order — what the arrow keys walk.
    private var orderedSections: [SettingsView.Section] {
        SettingsView.sidebarGroups.flatMap(\.sections)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    ForEach(SettingsView.sidebarGroups) { group in
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(group.title.uppercased())
                                .typo(.micro)
                                .foregroundStyle(Palette.inkFaint)
                                .padding(.horizontal, Space.s4)
                                .padding(.bottom, Space.s2)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.sections) { section in
                                SidebarRow(
                                    section: section,
                                    isSelected: selection == section,
                                    namespace: selectionPill
                                ) {
                                    selection = section
                                    // Clicking a row hands focus to the column
                                    // so the arrow keys keep working from there.
                                    isFocused = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s5)
                .animation(motion.select, value: selection)
            }

            SidebarFooter()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
        .accessibilityLabel("Settings sections")
    }

    private func move(by delta: Int) -> KeyPress.Result {
        let all = orderedSections
        guard let index = all.firstIndex(of: selection) else { return .ignored }
        let next = index + delta
        guard all.indices.contains(next) else { return .handled }
        selection = all[next]
        return .handled
    }
}

// MARK: - Row

private struct SidebarRow: View {
    let section: SettingsView.Section
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    /// Radius.sidebarRow (28) is the row *height* the capsule is built from —
    /// a capsule's radius is half its height, so one number defines both.
    private let rowHeight = Radius.sidebarRow

    @State private var isHovering = false
    @Environment(\.motion) private var motion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s4) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .center)
                Text(section.title)
                    .typo(.body)
                Spacer(minLength: 0)
            }
            // Icon and label share one derived colour — nothing in this view
            // tracks the selection tint by hand.
            .foregroundStyle(isSelected ? Palette.accent : Palette.ink)
            .padding(.horizontal, Space.s4)
            .frame(height: rowHeight)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Palette.accent.opacity(0.16))
                        // ONE pill for the whole sidebar: it slides between
                        // rows rather than fading out and in somewhere else.
                        .matchedGeometryEffect(id: "sidebar.selection", in: namespace)
                } else if isHovering {
                    Capsule(style: .continuous)
                        .fill(Palette.wellFill)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(motion.hover) { isHovering = hovering }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(section.title)
    }
}

// MARK: - Footer

/// 44pt, pinned to the bottom of the column, hairline above: the app mark on
/// the left, the version on the right. The mark is one of only two places the
/// brand gradient is allowed to appear — no text sits on it, so the 2.9:1 the
/// gradient scores against white never matters here.
private struct SidebarFooter: View {
    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(short ?? "0.0")"
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)

            HStack(spacing: Space.s4) {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(Palette.brandGradient)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                Spacer(minLength: Space.s4)

                Text(versionText)
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint)
                    .accessibilityLabel("Version \(versionText)")
            }
            .padding(.horizontal, Space.s5)
            .frame(height: 44)
        }
    }
}
