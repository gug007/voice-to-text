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

    private var hasFavorites: Bool { store.entries.contains { $0.isFavorited } }

    /// Recordings to show: all, or just favorites when the filter is on. The
    /// filter self-disables when nothing is favorited, so it can't strand an
    /// empty list.
    private var visibleEntries: [RecordingHistoryEntry] {
        (favoritesOnly && hasFavorites) ? store.entries.filter(\.isFavorited) : store.entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LargeTitleHeader(
                    title: "History",
                    subtitle: "Your past recordings and transcriptions, saved on this Mac."
                )

                saveToggleSection

                if store.entries.isEmpty {
                    emptyState
                } else {
                    recordingsSection
                }
            }
            .padding(32)
            .animation(.easeInOut(duration: 0.18), value: store.entries)
        }
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

    // MARK: - Save toggle

    private var saveToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InsetCard {
                HStack {
                    Text("Save recordings")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $store.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            GroupFooter(text: store.isEnabled
                        ? "New dictations are saved here automatically."
                        : "New dictations won't be saved. Existing history is kept until you clear it.")
        }
    }

    // MARK: - Recordings

    private var recordingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupCaption(text: countLabel) {
                HStack(spacing: 12) {
                    if hasFavorites {
                        FavoritesFilterButton(isOn: $favoritesOnly)
                    }
                    if store.totalDiskUsageBytes > 0 {
                        Text("\(store.totalDiskUsageBytes.formattedDiskSize) on disk")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Button("Clear All") { confirmingClear = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            RecordingsList(
                entries: visibleEntries,
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
                }
            )
        }
    }

    private var countLabel: String {
        if favoritesOnly && hasFavorites {
            let count = visibleEntries.count
            return count == 1 ? "1 favorite" : "\(count) favorites"
        }
        let count = store.entries.count
        return count == 1 ? "1 recording" : "\(count) recordings"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        InsetCard {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No recordings yet")
                    .font(.system(size: 14, weight: .medium))
                Text("Your dictations and conversations will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
        }
    }
}
