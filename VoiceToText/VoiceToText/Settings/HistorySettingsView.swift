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
    /// Which insight tab each recording row is showing. Owned here rather than
    /// by the row: the rows are laid out lazily, so a row's own `@State` would
    /// not survive being scrolled out of view (see `RecordingsList`).
    @State private var insightTabs: [UUID: InsightTab] = [:]
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

    /// Recordings to show: all, or just favorites when the filter is on, then
    /// narrowed by the toolbar search field. The two compose rather than fight —
    /// the favourites filter picks the corpus, search narrows it — and the
    /// favourites filter self-disables when nothing is favorited, so it can't
    /// strand an empty list.
    ///
    /// The match is a linear in-memory scan (see `HistorySearch`). The store
    /// keeps a hard 200 plain dictations, plus whatever the user chose to keep,
    /// with no settings UI behind it, so an index would be slower than the scan
    /// it replaced.
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
        // Scan once per body pass: `sections` runs the whole filter, and every
        // use below would otherwise repeat it on each keystroke.
        let sections = sections
        let visibleIDs = Self.ids(in: sections)
        return PaneScaffold {
            PaneHeader(
                title: "History",
                subtitle: "Your past recordings and transcriptions, saved on this Mac."
            )

            saveToggleSection

            if store.entries.isEmpty {
                emptyState
            } else if sections.isEmpty || sections.allSatisfy(\.entries.isEmpty) {
                noResultsState
            } else {
                recordingsSection(sections)
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
        .onAppear { store.refreshDiskUsage() }
        // Clear the favorites filter once nothing is favorited, so it can't sit
        // stranded-on behind a hidden toggle and silently re-collapse the list.
        .onChange(of: hasFavorites) { _, has in
            if !has { favoritesOnly = false }
        }
        .onChange(of: visibleIDs) { _, ids in rowSelection.prune(toVisible: ids) }
        .onChange(of: store.entries.isEmpty) { _, isEmpty in
            if isEmpty { endSelecting() }
        }
        .onChange(of: rowSelection.count) { _, count in
            if isSelecting { announce(HistorySelection.countLabel(count)) }
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
            // Clear All leaves a dictation that is still being transcribed;
            // the dialog shouldn't promise otherwise.
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
        // Floating Undo toast for the few-seconds grace window after a delete.
        // While the selection bar is up the toast rides above it.
        .overlay {
            UndoDeletionBar(store: store)
                .padding(.bottom, isSelecting ? selectionBarHeight + Space.s4 : 0)
        }
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

    @ToolbarContentBuilder
    private var browsingToolbarContent: some ToolbarContent {
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
                Button("Select…") { beginSelecting() }
                    .disabled(store.entries.isEmpty)
                Divider()
                Toggle("Save recordings", isOn: $store.isEnabled)
                Divider()
                Button("Clear All…", role: .destructive) { confirmingClear = true }
                    // Rows still transcribing are spared (see `clearAll`).
                    .disabled(store.entries.allSatisfy { store.inFlightIDs.contains($0.id) })
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
                Toggle("Save recordings", isOn: $store.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, Space.s3)
            GroupFooter(text: store.isEnabled
                        ? "New dictations are saved here automatically."
                        : "New dictations won't be saved. One that fails to transcribe is still kept here, so you can transcribe it again.")
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
                        selection: rowSelectionHooks,
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
                        onToggleActionItem: { entry, itemID in
                            store.toggleActionItem(entryID: entry.id, itemID: itemID)
                        },
                        onRemoveInsight: { entry, kind in
                            store.removeInsight(entryID: entry.id, kind: kind)
                            // Forget the tab that pointed at it. The row already
                            // falls back to the transcript while the tab is gone,
                            // but a remembered `.summary` would re-activate the
                            // moment a later generation *starts* — yanking the
                            // user off the transcript onto a spinner they did not
                            // ask to watch, and back again if it fails.
                            if insightTabs[entry.id] == kind.tab { insightTabs[entry.id] = nil }
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

    // MARK: - Selection

    /// The rows on screen, in the order they are drawn — what a ⇧-click range
    /// and Select All run over.
    private var visibleIDs: [UUID] { Self.ids(in: sections) }

    private static func ids(in sections: [HistorySection]) -> [UUID] {
        sections.flatMap(\.entries).map(\.id)
    }

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
        return HStack(spacing: Space.s5) {
            Text(HistorySelection.countLabel(count))
                .typo(.headline)
                .foregroundStyle(count == 0 ? Palette.inkMuted : Palette.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: Space.s4)

            selectionBarButton("Select All", isDisabled: allVisibleSelected) {
                rowSelection.selectAll(visibleIDs)
            }
            .keyboardShortcut("a", modifiers: .command)
            .help("Select every recording shown")

            selectionBarButton(
                "Copy",
                systemImage: selectionCopied ? "checkmark" : "doc.on.doc",
                tint: selectionCopied ? Palette.signalReady : Palette.accent,
                isDisabled: !canCopy
            ) {
                copySelection(selected)
            }
            .help("Copy the selected transcripts")
            .accessibilityLabel(selectionCopied ? "Copied" : "Copy transcripts")

            selectionBarButton(HistorySelection.favoriteTitle(favoriteFlags), isDisabled: count == 0) {
                store.setFavorite(!HistorySelection.unfavorites(favoriteFlags), ids: rowSelection.selected)
            }

            Button {
                deleteSelection()
            } label: {
                Text("Delete")
                    .typo(.headline)
                    .fixedSize()
            }
            .buttonStyle(DestructiveTextButtonStyle())
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.4)
            .help("Delete the selected recordings")
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s5)
        .glassSurface(in: Capsule())
        .floatingShadow(reduceTransparency: reduceTransparency)
        .frame(maxWidth: 560)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
    }

    private func selectionBarButton(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = Palette.accent,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Typo.captionMedium)
                }
                Text(title)
                    .typo(.headline)
            }
            .foregroundStyle(tint)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
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
        LibraryEmptyState(
            systemImage: "waveform",
            title: "No recordings yet",
            message: "Your dictations and conversations will appear here."
        )
    }
}
