import AppKit
import SwiftUI

/// Settings pane for meeting recording: capture a long conversation (mic +
/// system audio) in the background, then transcribe it on stop and save it to
/// History. Minimal, state-driven chrome that matches the other panes.
struct MeetingsPane: View {
    @Bindable private var controller = MeetingController.shared
    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared
    @State private var screenGranted = ScreenCapturePermission.isGranted

    /// Saved conversation recordings, newest first.
    private var conversations: [RecordingHistoryEntry] {
        store.entries.filter { $0.source == .meeting }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
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
            VStack(alignment: .leading, spacing: 10) {
                Text(conversations.count == 1 ? "1 recorded conversation" : "\(conversations.count) recorded conversations")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                LazyVStack(spacing: 8) {
                    ForEach(conversations) { entry in
                        RecordingRow(
                            entry: entry,
                            isPlaying: player.playingID == entry.id,
                            showsTypeBadge: false,
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
    }

    // MARK: - Permission

    private var permissionCard: some View {
        RowCard {
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
        }
    }

    private var idleCard: some View {
        RowCard {
            HStack(spacing: 16) {
                ProviderIconTile(symbol: "mic.fill", tint: .accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Record a conversation")
                        .font(.system(size: 14, weight: .medium))
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
                Button {
                    Task { await controller.start() }
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controller.isBusy)
            }
            .padding(18)
        }
    }

    private var recordingCard: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    RecordingDot()
                    Text("Recording")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(controller.elapsed.formattedClock)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }

                LevelBars(samples: controller.levelHistory, tint: .primary)
                    .frame(height: 56)

                HStack(spacing: 10) {
                    Button {
                        Task { await controller.stop() }
                    } label: {
                        Label("Stop & Transcribe", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Cancel") {
                        Task { await controller.cancel() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Spacer()
                }
            }
            .padding(18)
        }
    }

    private var transcribingCard: some View {
        RowCard {
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
        Text("Recordings and transcripts are saved on this Mac in History. Long conversations are transcribed in segments with the model you picked in Models.")
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
