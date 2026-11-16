import AppKit
import SwiftUI

/// Which recordings the History list shows. View state only — not persisted.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case dictations
    case conversations
    case favorites
    case favoriteConversations

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All Recordings"
        case .dictations: return "Dictations"
        case .conversations: return "Conversations"
        case .favorites: return "Favorites"
        case .favoriteConversations: return "Favorite Conversations"
        }
    }

    func includes(_ entry: RecordingHistoryEntry) -> Bool {
        switch self {
        case .all: return true
        case .dictations: return (entry.source ?? .dictation) == .dictation
        case .conversations: return entry.source == .meeting
        case .favorites: return entry.isFavorited
        case .favoriteConversations: return entry.isFavorited && entry.source == .meeting
        }
    }
}

/// Past recordings — dictations and conversations alike — under date headers,
/// each with its transcript and an always-visible Copy · Favorite · ⋯.
struct HistoryPane: View {
    /// A filter another pane asks History to open with ("Show All in History"
    /// from Conversations). Read once on appear, then cleared.
    static var pendingFilter: HistoryFilter?

    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared
    @State private var confirmingClear = false
    @State private var filter: HistoryFilter = .all
    @State private var searchQuery = ""
    /// Which insight tab each row is showing. Owned here: rows are lazy, so a
    /// row's own `@State` would not survive being scrolled out of view.
    @State private var insightTabs: [UUID: InsightTab] = [:]
    /// The one open row; opening another closes it.
    @State private var expandedID: UUID?
    @State private var isSelecting = false
    @State private var rowSelection = HistorySelection()
    @State private var selectionCopied = false
    @State private var selectionCopyResetTask: Task<Void, Never>?
    /// The selection bar's own height, so the Undo toast can sit above it and
    /// the list can scroll its last row clear of it.
    @State private var selectionBarHeight: CGFloat = 0
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var hasFavorites: Bool { store.entries.contains { $0.isFavorited } }
    private var hasFavoriteConversations: Bool { store.entries.contains { $0.isFavorited && $0.source == .meeting } }

    /// The filter picks the corpus, search narrows it. The match is a linear
    /// in-memory scan (see `HistorySearch`) over at most a few hundred entries.
    private var visibleEntries: [RecordingHistoryEntry] {
        let corpus = filter == .all ? store.entries : store.entries.filter(filter.includes)
        return HistorySearch.filter(corpus, query: searchQuery)
    }

    private var isSearching: Bool { HistorySearch.isActive(searchQuery) }

    /// Date sections, or one flat run of results while searching — "Today /
    /// Yesterday" over six scattered hits describes the library, not the result.
    private var sections: [HistorySection] {
        let entries = visibleEntries
        if isSearching {
            let title = entries.count == 1 ? "1 Result" : "\(entries.count) Results"
            return [HistorySection(id: "results", title: title, entries: entries)]
        }
        return HistoryDateGrouping.sections(of: entries)
    }

    var body: some View {
        // Scan once per body pass: `sections` runs the whole filter.
        let sections = sections
        let visibleIDs = Self.ids(in: sections)
        return PaneScaffold {
            if !store.isEnabled {
                SettingsGroup {
                    SettingsRow(
                        "Saving new dictations is off",
                        caption: "Only dictations that fail to transcribe are kept, so you can transcribe them again."
                    ) {
                        Button("Turn On") { store.isEnabled = true }
                            .buttonTier(.secondary)
                    }
                }
            }

            if store.entries.isEmpty {
                LibraryEmptyState(
                    systemImage: "waveform",
                    title: "No recordings yet",
                    message: "Your dictations and conversations will appear here."
                )
            } else if visibleIDs.isEmpty {
                noResultsState
            } else {
                VStack(alignment: .leading, spacing: Space.section) {
                    RecordingSectionsList(
                        sections: sections,
                        highlight: searchQuery,
                        selection: rowSelectionHooks,
                        insightTabs: $insightTabs,
                        expandedID: $expandedID
                    )
                    SettingsGroupFooter(libraryFooter)
                        .padding(.top, FormMetrics.groupLabelGap - Space.section)
                }
            }

            if isSelecting {
                Color.clear
                    .frame(height: selectionBarHeight)
                    .accessibilityHidden(true)
            }
        }
        .animation(motion.layout, value: store.entries)
        .searchable(text: $searchQuery, prompt: "Search transcripts")
        .toolbar { toolbarContent }
        .onAppear {
            store.refreshDiskUsage()
            if let requested = Self.pendingFilter {
                filter = requested
                Self.pendingFilter = nil
            }
        }
        // Leave Favorites once nothing is favorited, rather than strand an
        // empty list behind it.
        .onChange(of: hasFavorites) { _, has in
            if !has, filter == .favorites || filter == .favoriteConversations { filter = .all }
        }
        .onChange(of: hasFavoriteConversations) { _, has in
            if !has, filter == .favoriteConversations { filter = .all }
        }
        .onChange(of: visibleIDs) { _, ids in rowSelection.prune(toVisible: ids) }
        .onChange(of: store.entries.isEmpty) { _, isEmpty in
            if isEmpty { endSelecting() }
        }
        .onChange(of: rowSelection.count) { _, count in
            if isSelecting { announce(HistorySelection.countLabel(count)) }
        }
        // Leaving History (or closing Settings) shouldn't leave a clip playing
        // with no visible control.
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
            // Clear All leaves a dictation that is still being transcribed.
            Text(store.inFlightIDs.isEmpty
                ? "This permanently removes every saved recording and its transcript from this Mac."
                : "This permanently removes every saved recording and its transcript from this Mac, except a dictation still being transcribed.")
        }
        .overlay {
            FloatingBottomBar(isPresented: isSelecting, animationValue: isSelecting) {
                selectionBar(visibleIDs: visibleIDs)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        selectionBarHeight = $0
                    }
            }
        }
        .overlay {
            UndoDeletionBar(store: store)
                .padding(.bottom, isSelecting ? selectionBarHeight + Space.s4 : 0)
        }
    }

    /// "12 recordings · 3 MB, saved on this Mac."
    private var libraryFooter: String {
        let count = store.entries.count == 1 ? "1 recording" : "\(store.entries.count) recordings"
        guard store.totalDiskUsageBytes > 0 else { return "\(count), saved on this Mac." }
        return "\(count) · \(store.totalDiskUsageBytes.formattedDiskSize), saved on this Mac."
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { endSelecting() }
                    .keyboardShortcut(.cancelAction)
                    .help("Stop selecting recordings")
            }
        } else {
            browsingToolbarContent
        }
    }

    /// A labelled filter that shows its current value, then the pane's ⋯ menu.
    /// `.searchToolbarBehavior(.minimize)` is unavailable on macOS, so the
    /// search field is always expanded.
    @ToolbarContentBuilder
    private var browsingToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Show", selection: $filter) {
                ForEach(HistoryFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Filter recordings")
            .accessibilityLabel("Filter recordings")
            .accessibilityValue(filter.title)
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Select…") { beginSelecting() }
                    .disabled(store.entries.isEmpty)
                Toggle("Save New Dictations", isOn: $store.isEnabled)
                Divider()
                Button("Show in Finder") { HistoryFolder.reveal() }
                Divider()
                Button("Clear All…", role: .destructive) { confirmingClear = true }
                    // Rows still transcribing are spared (see `clearAll`).
                    .disabled(store.entries.allSatisfy { store.inFlightIDs.contains($0.id) })
            } label: {
                Label("History Options", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("History options: select, save new dictations, show in Finder, clear all")
            .accessibilityLabel("History options")
        }
    }

    // MARK: - Selection

    private static func ids(in sections: [HistorySection]) -> [UUID] {
        sections.flatMap(\.entries).map(\.id)
    }

    /// The rows on screen, in the order they are drawn — what a ⇧-click range
    /// and Select All run over.
    private var visibleIDs: [UUID] { Self.ids(in: sections) }

    private func rowSelectionHooks(_ entry: RecordingHistoryEntry) -> RecordingRowSelection {
        RecordingRowSelection(
            isSelecting: isSelecting,
            isSelected: rowSelection.contains(entry.id),
            onToggle: {
                beginSelecting()
                rowSelection.toggle(entry.id)
            },
            onExtend: {
                beginSelecting()
                rowSelection.extend(to: entry.id, over: visibleIDs)
            }
        )
    }

    private func beginSelecting() {
        guard !isSelecting else { return }
        player.stop()
        rowSelection.clear()
        isSelecting = true
    }

    private func endSelecting() {
        isSelecting = false
        rowSelection.clear()
    }

    private var selectedEntries: [RecordingHistoryEntry] {
        store.entries.filter { rowSelection.contains($0.id) }
    }

    /// Same glass capsule, elevation and position as `UndoDeletionToast`.
    private func selectionBar(visibleIDs: [UUID]) -> some View {
        let selected = selectedEntries
        let count = rowSelection.count
        let favoriteFlags = selected.map(\.isFavorited)
        let canCopy = selected.contains { !$0.transcriptIsPlaceholder }
        let canDelete = selected.contains { !store.inFlightIDs.contains($0.id) }
        let allVisibleSelected = !visibleIDs.isEmpty && visibleIDs.allSatisfy(rowSelection.contains)
        let unfavorite = HistorySelection.unfavorites(favoriteFlags)
        @ViewBuilder func buttons() -> some View {
            Button { rowSelection.selectAll(visibleIDs) } label: {
                Label("Select All", systemImage: "checklist.checked")
            }
            .disabled(allVisibleSelected)
            .keyboardShortcut("a", modifiers: .command)
            .help("Select every recording shown")

            Button {
                copySelection(selected)
            } label: {
                Label(selectionCopied ? "Copied" : "Copy", systemImage: selectionCopied ? "checkmark" : "doc.on.doc")
            }
            .disabled(!canCopy)
            .help("Copy the selected transcripts")

            Button {
                store.setFavorite(!unfavorite, ids: rowSelection.selected)
            } label: {
                Label(HistorySelection.favoriteTitle(favoriteFlags), systemImage: unfavorite ? "star.slash" : "star")
            }
            .disabled(count == 0)
            .help(unfavorite ? "Remove the selected recordings from Favorites" : "Add the selected recordings to Favorites")

            Button(role: .destructive) { deleteSelection() } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonTier(.destructive)
            .disabled(!canDelete)
            .help("Delete the selected recordings")
        }
        let countLabel = Text(HistorySelection.countLabel(count))
            .typo(.headline)
            .foregroundStyle(count == 0 ? Palette.inkMuted : Palette.ink)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.updatesFrequently)
        // Titles where they fit; at the narrowest window the same buttons as
        // glyphs (each keeps its title as tooltip and VoiceOver name).
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s4) {
                countLabel
                Spacer(minLength: Space.s4)
                buttons().labelStyle(.titleOnly)
            }
            HStack(spacing: Space.s3) {
                countLabel
                Spacer(minLength: Space.s3)
                buttons().labelStyle(.iconOnly)
            }
        }
        .buttonTier(.secondary)
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s4)
        .glassSurface(in: Capsule())
        .floatingShadow(reduceTransparency: reduceTransparency)
        .frame(maxWidth: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
    }

    private func copySelection(_ entries: [RecordingHistoryEntry]) {
        let items = entries.map { entry in
            HistorySelection.CopyItem(
                createdAt: entry.createdAt,
                dateLine: RecordingDateFormat.rowLabel(entry.createdAt),
                transcript: entry.transcriptIsPlaceholder
                    ? nil
                    : SpeakerRelabeler.apply(names: entry.speakerNames ?? [:], to: entry.transcript)
            )
        }
        guard let text = HistorySelection.copyText(items) else { return }
        KeystrokeOutput.copyOnly(text)
        selectionCopied = true
        selectionCopyResetTask?.cancel()
        selectionCopyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            selectionCopied = false
        }
    }

    private func deleteSelection() {
        let ids = rowSelection.selected
        if let playing = player.playingID, ids.contains(playing) { player.stop() }
        store.delete(ids: ids)
        endSelecting()
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: - Empty states

    private var isFavoritesFilter: Bool { filter == .favorites || filter == .favoriteConversations }

    /// There ARE recordings; the search or the filter hid them all. Offers the
    /// way back out rather than implying the library is empty.
    @ViewBuilder
    private var noResultsState: some View {
        if isSearching {
            LibraryEmptyState(
                systemImage: "magnifyingglass",
                title: "No results for “\(searchQuery)”",
                message: filter == .all
                    ? "Search looks at transcripts, speaker names, the model and the date."
                    : "Searched \(filter.title.lowercased()) only."
            ) {
                Button("Clear Search") { searchQuery = "" }
                    .buttonTier(.secondary)
            }
        } else {
            LibraryEmptyState(
                systemImage: isFavoritesFilter ? "star" : "line.3.horizontal.decrease.circle",
                title: filter == .favorites ? "No favorites yet" : "No \(filter.title.lowercased()) yet",
                message: isFavoritesFilter ? "Star a recording to keep it here." : nil
            ) {
                Button("Show All Recordings") { filter = .all }
                    .buttonTier(.secondary)
            }
        }
    }
}
