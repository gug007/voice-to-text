import AppKit
import SwiftUI

/// Settings pane listing past recordings — dictations and conversations alike —
/// each with its transcript and play / copy / delete. Mirrors the card-based
/// layout of the other panes: a single controls card, a slim list header, then
/// the recordings.
struct HistoryPane: View {
    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "History",
                    subtitle: "Your past recordings and transcriptions, saved on this Mac."
                )

                saveToggleCard

                if store.entries.isEmpty {
                    emptyState
                } else {
                    listHeader
                    LazyVStack(spacing: 8) {
                        ForEach(store.entries) { entry in
                            RecordingRow(
                                entry: entry,
                                isPlaying: player.playingID == entry.id,
                                onPlay: {
                                    player.toggle(url: store.audioURL(for: entry), id: entry.id)
                                },
                                onDelete: {
                                    if player.playingID == entry.id { player.stop() }
                                    store.delete(id: entry.id)
                                }
                            )
                        }
                    }
                }
            }
            .padding(32)
            .animation(.easeInOut(duration: 0.18), value: store.entries)
        }
        .onAppear { store.refreshDiskUsage() }
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
    }

    // MARK: - Save toggle

    private var saveToggleCard: some View {
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save recordings")
                        .font(.system(size: 14, weight: .medium))
                    Text(store.isEnabled
                         ? "New dictations are saved here automatically."
                         : "New dictations won't be saved. Existing history is kept until you clear it.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $store.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(18)
        }
    }

    // MARK: - List header

    private var listHeader: some View {
        HStack(spacing: 8) {
            Text(countLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
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
        .padding(.horizontal, 2)
    }

    private var countLabel: String {
        let count = store.entries.count
        return count == 1 ? "1 recording" : "\(count) recordings"
    }

    // MARK: - Empty state

    private var emptyState: some View {
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
