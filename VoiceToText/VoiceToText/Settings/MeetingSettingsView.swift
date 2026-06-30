import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings pane for meeting recording: capture a long conversation (mic +
/// system audio) in the background, then transcribe it on stop and save it to
/// History. Minimal, state-driven chrome that matches the other panes.
struct MeetingsPane: View {
    @Bindable private var controller = MeetingController.shared
    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared
    @State private var screenGranted = ScreenCapturePermission.isGranted
    @State private var favoritesOnly = false

    /// Saved conversation recordings, newest first.
    private var conversations: [RecordingHistoryEntry] {
        store.entries.filter { $0.source == .meeting }
    }

    private var hasFavoriteConversations: Bool { conversations.contains { $0.isFavorited } }

    /// Conversations to show: all, or just favorites when the filter is on. The
    /// filter self-disables when nothing is favorited.
    private var visibleConversations: [RecordingHistoryEntry] {
        (favoritesOnly && hasFavoriteConversations) ? conversations.filter(\.isFavorited) : conversations
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LargeTitleHeader(
                    title: "Conversations",
                    subtitle: "Record a long conversation in the background — your mic and everyone you hear — then get a transcript."
                )

                if !screenGranted && !controller.isBusy {
                    permissionCard
                }

                stateCard

                if controller.state == .idle, let summary = controller.lastSavedSummary {
                    savedBanner(summary)
                }

                conversationsList

                infoNote
            }
            .padding(32)
            .animation(.easeInOut(duration: 0.2), value: controller.state)
            .animation(.easeInOut(duration: 0.18), value: conversations)
        }
        .onAppear { screenGranted = ScreenCapturePermission.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenGranted = ScreenCapturePermission.isGranted
        }
        // Clear the favorites filter once no conversation is favorited, so it
        // can't sit stranded-on behind a hidden toggle.
        .onChange(of: hasFavoriteConversations) { _, has in
            if !has { favoritesOnly = false }
        }
        // Don't strand a stale error message, or keep a clip playing, when the
        // user navigates away (dismissError is a no-op while busy).
        .onDisappear {
            controller.dismissError()
            player.stop()
        }
    }

    // MARK: - Recorded conversations

    @ViewBuilder
    private var conversationsList: some View {
        if !conversations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: conversationsCaption) {
                    if hasFavoriteConversations {
                        FavoritesFilterButton(isOn: $favoritesOnly)
                    }
                }
                RecordingsList(
                    entries: visibleConversations,
                    showsTypeBadge: false,
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
    }

    private var conversationsCaption: String {
        if favoritesOnly && hasFavoriteConversations {
            let count = visibleConversations.count
            return count == 1 ? "1 favorite" : "\(count) favorites"
        }
        return conversations.count == 1
            ? "1 recorded conversation"
            : "\(conversations.count) recorded conversations"
    }

    // MARK: - Permission

    private var permissionCard: some View {
        InsetCard {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.inset.filled.badge.record")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording permission needed")
                        .font(.system(size: 13, weight: .medium))
                    Text("Capturing other participants' audio uses Screen Recording. VoiceToText never records the screen — only the audio.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Open Settings…") {
                    ScreenCapturePermission.request()
                    ScreenCapturePermission.openSystemSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
        }
    }

    // MARK: - State-driven card

    @ViewBuilder
    private var stateCard: some View {
        switch controller.state {
        case .idle, .error:
            idleCard
        case .recording:
            recordingCard
        case .transcribing:
            transcribingCard
        case .importing:
            importingCard
        }
    }

    private var idleCard: some View {
        InsetCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Record a conversation")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Captures your mic and system audio. Keeps recording while you work in other apps; saved to History when you stop.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .error(let message) = controller.state {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Dismiss") { controller.dismissError() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tint)
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 12)
                SplitCapsuleButton(
                    title: "Start Recording",
                    systemImage: "record.circle",
                    isDisabled: controller.isBusy
                ) {
                    Task { await controller.start() }
                } menu: {
                    Button {
                        chooseAndImportFile()
                    } label: {
                        Label("Upload File…", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding(18)
        }
    }

    /// Lets the user pick an audio or video file, then transcribes it into the
    /// conversation list. The sandbox is off, so a plain open panel can read the
    /// chosen file directly.
    private func chooseAndImportFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audiovisualContent, .audio, .movie]
        panel.message = "Choose an audio or video file to transcribe."
        panel.prompt = "Transcribe"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await controller.importMedia(url: url) }
    }

    private var recordingCard: some View {
        InsetCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    RecordingDot()
                    Text("Recording")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(controller.elapsed.formattedClock)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                LevelBars(samples: controller.levelHistory, tint: .primary)
                    .frame(height: 56)

                HStack(spacing: 10) {
                    CapsuleActionButton(
                        title: "Stop & Transcribe",
                        systemImage: "stop.fill"
                    ) {
                        Task { await controller.stop() }
                    }

                    CapsuleActionButton(
                        title: "Cancel",
                        style: .secondary,
                        tint: .primary
                    ) {
                        Task { await controller.cancel() }
                    }

                    Spacer()
                }
            }
            .padding(18)
        }
    }

    private var transcribingCard: some View {
        InsetCard {
            HStack(spacing: 16) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcribing…")
                        .font(.system(size: 14, weight: .medium))
                    Text(transcribingDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.totalChunks > 1 {
                    Text("\(controller.transcribedChunks)/\(controller.totalChunks)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(18)
        }
    }

    private var transcribingDetail: String {
        if controller.totalChunks > 1 {
            return "Processing a long recording in segments — this can take a moment."
        }
        return "Turning the recording into text."
    }

    // MARK: - Importing an uploaded file

    @ViewBuilder
    private var importingCard: some View {
        InsetCard {
            HStack(spacing: 16) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 6) {
                    Text(importTitle)
                        .font(.system(size: 14, weight: .medium))
                    Text(importDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if case .extracting(let fraction) = controller.importStage {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, 2)
                    }
                }
                Spacer()
                importTrailingLabel
            }
            .padding(18)
        }
    }

    private var importTitle: String {
        switch controller.importStage {
        case .extracting: return "Extracting audio…"
        case .transcribing: return "Transcribing…"
        }
    }

    private var importDetail: String {
        switch controller.importStage {
        case .extracting: return "Reading the audio from your file."
        case .transcribing: return transcribingDetail
        }
    }

    @ViewBuilder
    private var importTrailingLabel: some View {
        switch controller.importStage {
        case .extracting(let fraction):
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        case .transcribing:
            if controller.totalChunks > 1 {
                Text("\(controller.transcribedChunks)/\(controller.totalChunks)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func savedBanner(_ summary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
            Text(summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.22))
        )
        .transition(.opacity)
    }

    private var infoNote: some View {
        Text("Record a conversation or upload an existing audio or video file — either way the audio and transcript are saved on this Mac in History. Long recordings are transcribed in segments with the model you picked in Models.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Softly pulsing red dot — the standard "recording now" affordance.
private struct RecordingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(on ? 1.0 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}
