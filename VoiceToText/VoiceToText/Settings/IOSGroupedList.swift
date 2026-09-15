import AppKit
import SwiftUI

/// Shared building blocks for the History and Conversations panes: the
/// recordings list, quiet section captions/footers, and the capsule buttons the
/// record card uses. These two screens read as the app's "library" (browsing
/// saved content); they aim for a calm, minimal look — hairlines and whitespace
/// over heavy chrome.
///
/// The pane title lives in `PaneHeader` (SettingsView.swift) — the 27pt bold
/// `LargeTitleHeader` that used to live here is gone, along with the app's only
/// use of bold.
///
/// The surface these panes sit on is `Plate`; the old `InsetCard` (radius 12,
/// primary @ 0.035, no stroke) is gone too.

// MARK: - Section captions

/// Small gray caption above a grouped section (an iOS list header). The
/// optional trailing slot carries section controls like "Clear All" or a
/// disk-usage figure.
struct GroupCaption<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s4) {
            Text(text)
                .typo(.captionMedium)
                .foregroundStyle(Palette.inkMuted)
            Spacer(minLength: Space.s4)
            trailing
        }
        .padding(.horizontal, Space.s3)
    }
}

extension GroupCaption where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text) { EmptyView() }
    }
}

/// Small gray explanatory text below a grouped section (an iOS list footer).
struct GroupFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .typo(.caption)
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s3)
    }
}

// MARK: - Recordings list

/// An inset-grouped list of saved recordings: one flush `Plate`, rows divided
/// by hairlines inset 14pt from the leading edge. Shared by History (all
/// recordings, with type badges) and Conversations (conversations only, badge
/// hidden).
struct RecordingsList: View {
    let entries: [RecordingHistoryEntry]
    var showsTypeBadge: Bool = true
    /// History's live search query, forwarded so each row can mark its matched
    /// substrings. Empty in Conversations, which has no search field.
    var highlight: String = ""
    let isPlaying: (RecordingHistoryEntry) -> Bool
    let onPlay: (RecordingHistoryEntry) -> Void
    let onDelete: (RecordingHistoryEntry) -> Void
    let onToggleFavorite: (RecordingHistoryEntry) -> Void
    let onRemoveTranscript: (RecordingHistoryEntry, UUID) -> Void
    let onRenameSpeakers: (RecordingHistoryEntry, [String: String]) -> Void
    /// Which insight tab each row is showing, keyed by recording id.
    ///
    /// The map lives in the *pane*, not in `RecordingRow`, because `FlushPlate`
    /// is lazy: a row scrolled out of view is torn down and any `@State` on it
    /// dies with it. A per-row `@State` tab would therefore snap silently back
    /// to Transcript every time the user scrolled past a summary they were
    /// reading. An absent key means Transcript, so an empty map is the correct
    /// initial state and nothing has to be seeded.
    @Binding var insightTabs: [UUID: InsightTab]
    let onToggleActionItem: (RecordingHistoryEntry, UUID) -> Void
    let onRemoveInsight: (RecordingHistoryEntry, InsightKind) -> Void

    var body: some View {
        // `FlushPlate` is lazy, so opening a long History doesn't lay out every
        // row's transcript and its two hidden measuring probes up front; only
        // rows scrolled into view are measured. It also owns the dividers.
        FlushPlate(data: entries) { entry in
            RecordingRow(
                entry: entry,
                isPlaying: isPlaying(entry),
                showsTypeBadge: showsTypeBadge,
                highlight: highlight,
                selectedTab: tabBinding(for: entry),
                onPlay: { onPlay(entry) },
                onDelete: { onDelete(entry) },
                onToggleFavorite: { onToggleFavorite(entry) },
                onRemoveTranscript: { onRemoveTranscript(entry, $0) },
                onRenameSpeakers: { onRenameSpeakers(entry, $0) },
                onToggleActionItem: { onToggleActionItem(entry, $0) },
                onRemoveInsight: { onRemoveInsight(entry, $0) }
            )
        }
    }

    /// One row's slot in the pane-owned map, as a binding the row can write to.
    private func tabBinding(for entry: RecordingHistoryEntry) -> Binding<InsightTab> {
        Binding(
            get: { insightTabs[entry.id] ?? .transcript },
            set: { insightTabs[entry.id] = $0 }
        )
    }
}

// MARK: - Favorites filter

/// A small star pill that toggles a "favorites only" filter — sits in a section
/// caption next to the count. Subtle when off, amber-tinted when on.
struct FavoritesFilterButton: View {
    @Binding var isOn: Bool

    /// The favourite amber, as a light/dark pair — `Color.yellow` is unreadable
    /// on a white plate in light appearance.
    static let tint = Palette.dynamic("favorite", light: 0xC99A00, dark: 0xFFD426)

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: isOn ? "star.fill" : "star")
                    .font(Typo.micro)
                Text("Favorites")
                    .typo(.captionMedium)
            }
            .foregroundStyle(isOn ? Self.tint : Palette.inkMuted)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(
                Capsule().fill(isOn ? Self.tint.opacity(0.16) : Palette.wellFill)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Show all recordings" : "Show favorites only")
    }
}

// MARK: - Capsule buttons

// `SplitCapsuleButton` (a filled capsule split into Start Recording + a chevron
// menu holding Upload File…) is gone. Both of its actions are toolbar items on
// the Conversations pane now — Start Recording as a prominent item, Upload File…
// in the system overflow — so the control had zero call sites left.

/// Filled or tinted capsule button in the iOS style — the primary affordance on
/// the Conversations record card (Start, Stop & Transcribe, Cancel).
///
/// `.primary` is the ink capsule: `Palette.action` fill with `Palette.onAction`
/// label, so it reads as the one solid object on the card. Hover steps the fill
/// back a notch — darker in light mode, dimmer in dark — and the step is what
/// the "lift" is; there is no shadow or scale.
struct CapsuleActionButton: View {
    enum Style { case primary, secondary }

    let title: String
    var systemImage: String? = nil
    var style: Style = .primary
    var tint: Color = Palette.action
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.motion) private var motion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Typo.headline)
                }
                Text(title)
                    .typo(.headline)
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s4)
            .foregroundStyle(style == .primary ? AnyShapeStyle(Palette.onAction) : AnyShapeStyle(tint))
            .background(Capsule().fill(fillColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            guard !isDisabled else { return }
            isHovering = hovering
        }
        .animation(motion.hover, value: isHovering)
    }

    private var fillColor: Color {
        switch style {
        case .primary: return tint.opacity(isHovering ? 0.86 : 1)
        case .secondary: return tint.opacity(isHovering ? 0.20 : 0.14)
        }
    }
}
