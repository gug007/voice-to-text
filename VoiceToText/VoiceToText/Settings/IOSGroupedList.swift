import AppKit
import SwiftUI

/// Shared building blocks for the History and Conversations panes: the
/// date-grouped recordings list, the list plate itself, and the empty state.

// MARK: - Date-grouped list

/// Recordings under Title Case date headers ("Today", "This Week",
/// "October 2026"), one plate per section. Rows under a dated header show only
/// what the header doesn't: the time, the weekday, or the day.
///
/// Owns the store and player wiring both panes share, so each pane only says
/// what to show.
struct RecordingSectionsList: View {
    let sections: [HistorySection]
    /// Hidden in Conversations, where every row is the same type.
    var showsTypeBadge: Bool = true
    /// History's live search query, so rows mark their matches.
    var highlight: String = ""
    /// History's selection hooks per row; nil in Conversations.
    var selection: ((RecordingHistoryEntry) -> RecordingRowSelection)? = nil
    /// Which tab each row shows, keyed by recording id — see `RecordingsList`.
    @Binding var insightTabs: [UUID: InsightTab]
    /// The one open row, if any.
    @Binding var expandedID: UUID?
    /// A link on the first section's header line ("Show All (14)" on
    /// Conversations' Recent).
    var headerLink: HeaderLink? = nil

    struct HeaderLink {
        let title: String
        let help: String
        let action: () -> Void
    }

    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared

    var body: some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: FormMetrics.groupLabelGap) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    SettingsGroupHeader(section.title)
                    Spacer(minLength: Space.s4)
                    if let headerLink, section.id == sections.first?.id {
                        Button(headerLink.title, action: headerLink.action)
                            .buttonTier(.tertiary)
                            .help(headerLink.help)
                    }
                }
                .padding(.horizontal, FormMetrics.rowHorizontalPadding)

                RecordingsList(
                    entries: section.entries,
                    showsTypeBadge: showsTypeBadge,
                    dateStyle: .forSection(id: section.id),
                    highlight: highlight,
                    selection: selection,
                    isPlaying: { player.playingID == $0.id },
                    onPlay: { entry in
                        player.toggle(url: store.audioURL(for: entry), id: entry.id)
                    },
                    onDelete: { entry in
                        if player.playingID == entry.id { player.stop() }
                        store.delete(id: entry.id)
                    },
                    onToggleFavorite: { entry in store.toggleFavorite(id: entry.id) },
                    onRemoveTranscript: { entry, variantID in
                        store.removeTranscriptVariant(entryID: entry.id, variantID: variantID)
                    },
                    onRenameSpeakers: { entry, names in
                        store.setSpeakerNames(entryID: entry.id, names: names)
                    },
                    insightTabs: $insightTabs,
                    expandedID: $expandedID,
                    onToggleActionItem: { entry, itemID in
                        store.toggleActionItem(entryID: entry.id, itemID: itemID)
                    },
                    onRemoveInsight: { entry, kind in
                        store.removeInsight(entryID: entry.id, kind: kind)
                        // Forget the tab that pointed at it: a remembered
                        // `.summary` would re-activate the moment a later
                        // generation *starts*, pulling the user off the
                        // transcript onto a spinner.
                        if insightTabs[entry.id] == kind.tab { insightTabs[entry.id] = nil }
                    }
                )
            }
        }
    }
}

// MARK: - Recordings list

/// One plate of recordings, rows divided by hairlines that start at the rows'
/// text column. Lazy, so a long History only lays out the rows on screen.
struct RecordingsList: View {
    let entries: [RecordingHistoryEntry]
    var showsTypeBadge: Bool = true
    var dateStyle: RecordingRowDateStyle = .full
    var highlight: String = ""
    var selection: ((RecordingHistoryEntry) -> RecordingRowSelection)? = nil
    let isPlaying: (RecordingHistoryEntry) -> Bool
    let onPlay: (RecordingHistoryEntry) -> Void
    let onDelete: (RecordingHistoryEntry) -> Void
    let onToggleFavorite: (RecordingHistoryEntry) -> Void
    let onRemoveTranscript: (RecordingHistoryEntry, UUID) -> Void
    let onRenameSpeakers: (RecordingHistoryEntry, [String: String]) -> Void
    /// Which insight tab each row is showing, keyed by recording id. Lives in
    /// the pane because rows are lazy: a row scrolled out of view is torn down
    /// with its `@State`. An absent key means Transcript.
    @Binding var insightTabs: [UUID: InsightTab]
    /// The one open row. Pane-owned for the same reason as `insightTabs`.
    @Binding var expandedID: UUID?
    let onToggleActionItem: (RecordingHistoryEntry, UUID) -> Void
    let onRemoveInsight: (RecordingHistoryEntry, InsightKind) -> Void

    var body: some View {
        FlushPlate(
            data: entries,
            leadingInset: FormMetrics.rowHorizontalPadding + RecordingRow.textColumnInset
        ) { entry in
            RecordingRow(
                entry: entry,
                isPlaying: isPlaying(entry),
                showsTypeBadge: showsTypeBadge,
                dateStyle: dateStyle,
                highlight: highlight,
                selection: selection?(entry),
                isExpanded: expandedBinding(for: entry),
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

    private func expandedBinding(for entry: RecordingHistoryEntry) -> Binding<Bool> {
        Binding(
            get: { expandedID == entry.id },
            set: { open in
                if open {
                    expandedID = entry.id
                } else if expandedID == entry.id {
                    expandedID = nil
                }
            }
        )
    }

    private func tabBinding(for entry: RecordingHistoryEntry) -> Binding<InsightTab> {
        Binding(
            get: { insightTabs[entry.id] ?? .transcript },
            set: { insightTabs[entry.id] = $0 }
        )
    }
}

// MARK: - Empty library

/// The centred "nothing here" state of a library pane, with an optional way
/// out (Clear Search, Show All).
struct LibraryEmptyState<Action: View>: View {
    let systemImage: String
    let title: String
    let message: String?
    @ViewBuilder var action: Action

    init(
        systemImage: String,
        title: String,
        message: String? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
                .accessibilityHidden(true)
            Text(title)
                .typo(.title)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action
                .padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .accessibilityElement(children: .contain)
    }
}

extension LibraryEmptyState where Action == EmptyView {
    init(systemImage: String, title: String, message: String? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

// MARK: - History folder

enum HistoryFolder {
    /// Opens the History folder in Finder. On a fresh install nothing has been
    /// saved yet and the folder doesn't exist, so it is created first rather
    /// than the click doing nothing.
    static func reveal() {
        let directory = RecordingHistoryStore.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
