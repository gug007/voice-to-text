import AppKit
import SwiftUI

// MARK: - Sidebar
//
// Two groups driven by an explicit array (`SettingsView.sidebarGroups`),
// separated by a hairline rather than headers (the titles never fitted
// General or Updates):
//
//   General, Conversations, History
//   ───
//   Shortcut, Models, Actions, Cloud, Updates
//
// Selection is one accent capsule at 28pt row height that slides between rows
// via `matchedGeometryEffect` on `Motion.select`. The pinned footer is a live
// status chip ("Ready · GPT Transcribe") that opens Models.
//
// WHY NOT `List(selection:)`: macOS draws the sidebar selection highlight in the
// NSTableView row view, below anything `.listRowBackground` can reach, so a List
// cannot host a custom capsule — the two highlights would stack. Rows are
// therefore buttons; arrow-key navigation is re-implemented below.

/// One block of sidebar rows. `title` is only the block's identity and its
/// VoiceOver container label; it is not drawn.
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
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(Array(SettingsView.sidebarGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            RowHairline(leadingInset: 0)
                                .padding(.horizontal, Space.s4)
                        }
                        VStack(alignment: .leading, spacing: Space.s1) {
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
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(group.title)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s5)
                .animation(motion.select, value: selection)
            }
            .accessibilityLabel("Settings sections")

            SidebarStatusChip()
        }
        .background(Palette.sidebar.ignoresSafeArea())
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.downArrow) { move(by: 1) }
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
                if let badge = section.badge {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(badge)
                }
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

// MARK: - Footer: live status chip

/// The sidebar footer, the app's one labelled status readout:
///
///   ● Ready
///   ☁ Dictation · GPT Transcribe
///   💻 Conversations · Parakeet TDT v3   (only when it differs)
///
/// Clicking opens the dictation-model menu (`ActiveModelMenu`); "All Models…"
/// opens Models, where the conversation model is set.
private struct SidebarStatusChip: View {
    private var registry: ModelRegistry { .shared }
    @Environment(\.motion) private var motion

    /// The conversation model, when it isn't the dictation model.
    private var separateConversationModel: ModelDescriptor? {
        guard let conversation = registry.conversationModel,
              conversation.id != registry.activeModel?.id else { return nil }
        return conversation
    }

    var body: some View {
        let status = AppStatus.current()

        ActiveModelMenu(menuTitle: "Dictation model") {
            VStack(alignment: .leading, spacing: Space.s1) {
                // The chevron rides on the status line so the model lines
                // below get the chip's full width.
                HStack(spacing: Space.s3) {
                    StatusDot(status.tone)
                    Text(status.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
                RoleModelLine(role: "Dictation", model: registry.activeModel)
                if let conversation = separateConversationModel {
                    RoleModelLine(role: "Conversations", model: conversation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SidebarChipButtonStyle())
        .padding(.horizontal, Space.s3)
        .padding(.bottom, Space.s4)
        .padding(.top, Space.s2)
        .help("\(spokenLine(status)). Click to change the dictation model.")
        .accessibilityLabel("Status: \(spokenLine(status))")
        .animation(motion.layout, value: status)
    }

    private func spokenLine(_ status: AppStatus) -> String {
        var parts = [status.title]
        if let model = registry.activeModel { parts.append("Dictation: \(model.nameWithSource)") }
        if let conversation = separateConversationModel { parts.append("Conversations: \(conversation.nameWithSource)") }
        return parts.joined(separator: ". ")
    }
}

/// "☁ Dictation · GPT Transcribe": the source glyph, the role, the model.
private struct RoleModelLine: View {
    let role: String
    let model: ModelDescriptor?

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: model?.sourceSymbol ?? "questionmark.circle")
                .font(.system(size: 9, weight: .medium))
                .frame(width: 12)
                .accessibilityHidden(true)
            Text("\(role) · \(model?.sectionedDisplayName ?? "None")")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .typo(.caption)
        .foregroundStyle(Palette.inkMuted)
    }
}

/// The chip's surface: well fill at rest, deeper on hover and press.
private struct SidebarChipButtonStyle: ButtonStyle {
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        configuration.label
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3 + 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill(isPressed: configuration.isPressed)))
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 0.5))
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(motion.hover, value: isHovering)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return Palette.ink.opacity(0.12) }
        return isHovering ? Palette.ink.opacity(0.08) : Palette.wellFill
    }
}
