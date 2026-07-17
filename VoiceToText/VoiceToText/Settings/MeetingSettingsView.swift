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
    @Bindable private var registry = ModelRegistry.shared
    @State private var screenGranted = ScreenCapturePermission.isGranted
    @State private var favoritesOnly = false
    /// True while a drag from Finder is hovering over the pane. Only turns into a
    /// visible drop affordance when the controller is idle (see `isDropActive`).
    @State private var isDropTargeted = false

    /// Content types a dropped file must conform to — the same family the
    /// "Upload File…" open panel accepts. Restricting the drop registration to
    /// these means a hovering non-media drag never lights up the overlay.
    private let acceptedDropTypes: [UTType] = [.audiovisualContent, .audio, .movie]

    /// Show the drop overlay only when a valid drag is hovering *and* we're free
    /// to take it. While busy the drop is inert, so no overlay.
    private var isDropActive: Bool { isDropTargeted && !controller.isBusy }

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

                transcriptionModelCard

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
        // The whole pane is a drop target for a single audio/video file. The
        // registration is scoped to media types, so `isDropTargeted` only flips
        // for a plausible file — invalid drags never trigger the overlay.
        .onDrop(of: acceptedDropTypes, isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            dropOverlay
                .animation(.easeInOut(duration: 0.18), value: isDropActive)
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
        // Floating Undo toast for the few-seconds grace window after a delete.
        .overlay { UndoDeletionBar(store: store) }
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

    // MARK: - Transcription model selector

    /// Lets the user pick a transcription model for conversations independently
    /// of the dictation model. Only shown while idle — it has no bearing on an
    /// in-flight recording/transcription. Streaming models are excluded: they're
    /// built for live mic input, not archived-file transcription.
    @ViewBuilder
    private var transcriptionModelCard: some View {
        if !controller.isBusy {
            InsetCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcription model")
                            .font(.system(size: 13, weight: .medium))
                        Text("Used for conversations and uploaded files.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Picker("", selection: conversationModelBinding) {
                        Text(sameAsDictationLabel).tag(String?.none)
                        ForEach(selectableConversationModels) { model in
                            Text(model.displayName).tag(String?.some(model.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(16)
            }
        }
    }

    /// The catalog minus streaming/realtime engines, which don't apply to
    /// buffered file transcription.
    private var selectableConversationModels: [ModelDescriptor] {
        ModelCatalog.all.filter { !$0.isRealtime }
    }

    /// "Same as dictation (<current dictation model>)" so the follow option
    /// shows what it currently resolves to.
    private var sameAsDictationLabel: String {
        if let active = registry.activeModel {
            return "Same as dictation (\(active.displayName))"
        }
        return "Same as dictation"
    }

    private var conversationModelBinding: Binding<String?> {
        Binding(
            // A stored id no longer in the catalog resolves as "same as
            // dictation" — surface that instead of a selection no tag matches.
            get: {
                guard let id = registry.conversationModelId,
                      ModelCatalog.model(for: id) != nil else { return nil }
                return id
            },
            set: { registry.setConversationModel($0) }
        )
    }

    private var idleCard: some View {
        InsetCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.26), Color.accentColor.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 50, height: 50)
                .shadow(color: Color.accentColor.opacity(0.18), radius: 6, x: 0, y: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Record a conversation")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Keeps recording in the background while you work in other apps — or drop an audio or video file here to transcribe it.")
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
            .padding(20)
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

    // MARK: - Drag-and-drop import

    /// Minimal drop affordance shown while a valid file hovers the pane: a
    /// material-dimmed, dashed accent border with an icon and two lines of copy.
    /// Non-interactive so it can never swallow the drag itself.
    @ViewBuilder
    private var dropOverlay: some View {
        if isDropActive {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                VStack(spacing: 10) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    VStack(spacing: 3) {
                        Text("Drop to transcribe")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Audio or video file")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Loads the first dropped file URL off the (arbitrary-queue) item provider,
    /// hops to the main actor, revalidates, and hands it to the controller. Rejects
    /// the drop outright while busy or when nothing loadable is present.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !controller.isBusy else { return false }
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                let controller = MeetingController.shared
                // Re-check on the main actor: state may have changed since the
                // drop, and the extension is a cheap guard against a stray type.
                guard !controller.isBusy, Self.isSupportedMedia(url) else { return }
                await controller.importMedia(url: url)
            }
        }
        return true
    }

    /// Whether a URL points at audio or video we can import — mirrors the open
    /// panel's accepted content types.
    private static func isSupportedMedia(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return type.conforms(to: .audio)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
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
        Text("Record a conversation or upload an existing audio or video file — either way the audio and transcript are saved on this Mac in History. Long recordings are transcribed in segments with the transcription model chosen above.")
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
