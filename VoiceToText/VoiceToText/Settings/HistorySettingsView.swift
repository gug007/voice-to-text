import AppKit
import SwiftUI

/// Settings pane listing past recordings — dictations and conversations alike —
/// each with its transcript and play / copy / delete. Styled as an iOS
/// inset-grouped list: a large title, a grouped toggle section, then the
/// recordings in a single hairline-separated card.
struct HistoryPane: View {
    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared
    @State private var confirmingClear = false
    @State private var favoritesOnly = false
    @State private var searchQuery = ""
    @Environment(\.motion) private var motion

    private var hasFavorites: Bool { store.entries.contains { $0.isFavorited } }

    /// Recordings to show: all, or just favorites when the filter is on, then
    /// narrowed by the toolbar search field. The two compose rather than fight —
    /// the favourites filter picks the corpus, search narrows it — and the
    /// favourites filter self-disables when nothing is favorited, so it can't
    /// strand an empty list.
    ///
    /// The match is a linear in-memory scan (see `HistorySearch`). The store's
    /// retention cap is a hard 200 with no settings UI behind it, so an index
    /// would be slower than the scan it replaced.
    private var visibleEntries: [RecordingHistoryEntry] {
        let corpus = (favoritesOnly && hasFavorites)
            ? store.entries.filter(\.isFavorited)
            : store.entries
        return HistorySearch.filter(corpus, query: searchQuery)
    }

    private var isSearching: Bool { HistorySearch.isActive(searchQuery) }

    /// How the visible rows are broken up. Date sections by default — the thing
    /// that makes a 200-row library readable. A search or a favourites filter
    /// collapses them into one labelled run, because "TODAY / YESTERDAY" over
    /// six scattered hits describes the library, not the result.
    private var sections: [HistorySection] {
        let entries = visibleEntries
        if isSearching {
            return [HistorySection(id: "results", title: "Results · \(entries.count)", entries: entries)]
        }
        if favoritesOnly && hasFavorites {
            return [HistorySection(id: "favorites", title: "Favorites · \(entries.count)", entries: entries)]
        }
        return HistoryDateGrouping.sections(of: entries)
    }

    var body: some View {
        PaneScaffold {
            PaneHeader(
                title: "History",
                subtitle: "Your past recordings and transcriptions, saved on this Mac."
            )

            saveToggleSection

            // Scan once per body pass, not once per branch: `sections` runs the
            // whole filter, and asking it three times would triple the work on
            // every keystroke.
            let sections = sections
            if store.entries.isEmpty {
                emptyState
            } else if sections.isEmpty || sections.allSatisfy(\.entries.isEmpty) {
                noResultsState
            } else {
                recordingsSection(sections)
            }
        }
        .animation(motion.layout, value: store.entries)
        .searchable(text: $searchQuery, prompt: "Search transcripts")
        .toolbar { toolbarContent }
        .onAppear { store.refreshDiskUsage() }
        // Clear the favorites filter once nothing is favorited, so it can't sit
        // stranded-on behind a hidden toggle and silently re-collapse the list.
        .onChange(of: hasFavorites) { _, has in
            if !has { favoritesOnly = false }
        }
        // Bind playback to the pane's lifetime: leaving History (or closing
        // Settings) shouldn't leave a clip playing with no visible control.
        .onDisappear { player.stop() }
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                player.stop()
                store.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved recording and its transcript from this Mac.")
        }
        // Floating Undo toast for the few-seconds grace window after a delete.
        .overlay { UndoDeletionBar(store: store) }
    }

    // MARK: - Toolbar
    //
    // Search is the new affordance; the favourites filter and Clear All were
    // smuggled into a `GroupCaption` trailing slot, which is a section header,
    // not a control bar. Both have a real home now. `.searchToolbarBehavior`
    // is not applied: `SearchToolbarBehavior.minimize` is explicitly
    // `@available(macOS, unavailable)` even in the macOS 26 SDK — it is an
    // iOS/visionOS affordance — so on macOS the field is always expanded.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $favoritesOnly) {
                Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .disabled(!hasFavorites)
            .help(favoritesOnly ? "Show all recordings" : "Show favorites only")
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle("Save recordings", isOn: $store.isEnabled)
                Divider()
                Button("Clear All…", role: .destructive) { confirmingClear = true }
                    .disabled(store.entries.isEmpty)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("More history options")
        }
    }

    // MARK: - Save toggle

    private var saveToggleSection: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("Save recordings")
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Toggle("", isOn: $store.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, Space.s3)
            GroupFooter(text: store.isEnabled
                        ? "New dictations are saved here automatically."
                        : "New dictations won't be saved. Existing history is kept until you clear it.")
        }
    }

    // MARK: - Recordings

    private func recordingsSection(_ sections: [HistorySection]) -> some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            // The caption is a caption again: the library's own size, and the
            // disk figure. What's *shown* is the section headers' job — so the
            // two never say the same thing twice.
            GroupCaption(text: countLabel) {
                if store.totalDiskUsageBytes > 0 {
                    Text("\(store.totalDiskUsageBytes.formattedDiskSize) on disk")
                        .typo(.captionMedium)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            ForEach(sections) { section in
                PaneSection(section.title) {
                    RecordingsList(
                        entries: section.entries,
                        highlight: searchQuery,
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
                        }
                    )
                }
            }
        }
    }

    private var countLabel: String {
        let count = store.entries.count
        return count == 1 ? "1 recording" : "\(count) recordings"
    }

    // MARK: - Empty states

    /// Distinct from `emptyState`: there ARE recordings, the filters just hid
    /// them all. Offers the way back out rather than implying the library is
    /// empty.
    private var noResultsState: some View {
        VStack(spacing: Space.s5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
            Text(isSearching ? "No results for “\(searchQuery)”" : "No favorites yet")
                .typo(.title)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if isSearching {
                Text("Search looks at transcripts, speaker names, the model and the date.")
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    .multilineTextAlignment(.center)
            }
            Button(isSearching ? "Clear search" : "Show all recordings") {
                searchQuery = ""
                favoritesOnly = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s5) {
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Palette.inkFaint)
            Text("No recordings yet")
                .typo(.title)
                .foregroundStyle(Palette.ink)
            Text("Your dictations and conversations will appear here.")
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}
