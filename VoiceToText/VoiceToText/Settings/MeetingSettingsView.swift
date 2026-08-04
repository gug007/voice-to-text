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
    @Environment(\.motion) private var motion

    /// Types the drop is registered for. A Finder drag arrives as a plain
    /// `public.file-url` provider that does *not* conform to the media content
    /// types, so `.fileURL` must be present or the pane never becomes a drop
    /// target. The media types are kept so promised-content drags from other
    /// apps still register. The file's actual kind is validated on drop, not
    /// here — so the overlay can light up for any file (see `handleDrop`).
    private let acceptedDropTypes: [UTType] = [.fileURL, .audiovisualContent, .audio, .movie]

    /// Show the "drop to transcribe" overlay only when a drag is hovering *and*
    /// we're free to take it.
    private var isDropActive: Bool { isDropTargeted && !controller.isBusy }

    /// Hovering, but the pane is mid-job — the drop will bounce, so say why.
    private var isDropBlocked: Bool { isDropTargeted && controller.isBusy }

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
        PaneScaffold {
            PaneHeader(
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
        .animation(motion.layout, value: controller.state)
        .animation(motion.layout, value: conversations)
        .toolbar { toolbarContent }
        // The whole pane is a drop target for a single audio/video file.
        // Because Finder drags register as `public.file-url`, the overlay flips
        // for any file hover; a non-media file is silently rejected by the
        // handler's revalidation rather than being filtered out up front.
        .onDrop(of: acceptedDropTypes, isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            // Keyed on the hover itself, not on `isDropActive` — the blocked
            // variant has to fade in and out on the same signal.
            dropOverlay
                .animation(motion.layout, value: isDropTargeted)
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

    // MARK: - Toolbar
    //
    // Start Recording was a `SplitCapsuleButton` wedged into the right edge of
    // the idle state card — where it disappeared the moment the card changed
    // state, and where its chevron menu was the only route to Upload File….
    // Start Recording is a prominent toolbar item now (flat `accent`, never the
    // brand gradient: white on #6194FF is 2.92:1).
    //
    // Upload File… was `.secondaryAction`, which on macOS means the system
    // overflow "⋯" — two clicks and no glyph for one of this pane's two ways in.
    // The idle card advertises file transcription ("or drop an audio or video
    // file here"), so the affordance it names has to be visible. It's a plain
    // `.primaryAction` bordered button now: declared first, so it sits to the
    // left of the prominent record button at the trailing edge.
    //
    // Its icon was `square.and.arrow.up` — the system *share* glyph, which reads
    // as "send this somewhere" and is exactly wrong for a local-only import that
    // uploads nothing anywhere. It's `waveform.badge.plus` now, the same glyph
    // the drop overlay uses, so the two routes to the same action look alike.
    //
    // NOT USED: `.visibilityPriority(1)`. It does not exist in the macOS 26.5
    // SDK this builds against — it is a macOS 27 API.

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                chooseAndImportFile()
            } label: {
                Label("Upload File…", systemImage: "waveform.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(controller.isBusy)
            .help("Transcribe an audio or video file already on this Mac")
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await controller.start() }
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    // Toolbar buttons default to icon-only on macOS. The pane's
                    // primary action does not get to be a mystery glyph.
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .disabled(controller.isBusy)
            .help("Record a conversation — your mic plus everything you hear")
        }
    }

    // MARK: - Recorded conversations

    @ViewBuilder
    private var conversationsList: some View {
        if !conversations.isEmpty {
            VStack(alignment: .leading, spacing: Space.s4) {
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
                    },
                    onRenameSpeakers: { entry, names in
                        store.setSpeakerNames(entryID: entry.id, names: names)
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
        StatusPlate([
            StatusItem(
                id: "screen-recording",
                level: .warning,
                title: PermissionCopy.screenRecordingTitle,
                message: PermissionCopy.screenRecordingPurpose,
                actionTitle: PermissionCopy.openSettingsShortButton
            ) {
                ScreenCapturePermission.request()
                ScreenCapturePermission.openSystemSettings()
            }
        ])
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
            VStack(alignment: .leading, spacing: 0) {
                PlateDivider(leadingInset: 0)
                HStack(spacing: Space.s5) {
                    Text("Transcription model")
                        .typo(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.s5)
                    MinimalDropdown(
                        selection: conversationModelBinding,
                        sections: conversationModelSections,
                        popupWidth: 300
                    )
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s5)
                PlateDivider(leadingInset: 0)
            }
        }
    }

    /// The catalog minus streaming/realtime engines, which don't apply to
    /// buffered file transcription.
    private var selectableConversationModels: [ModelDescriptor] {
        ModelCatalog.all.filter { !$0.isRealtime }
    }

    /// Rows for the transcription-model dropdown: a lead "Same as dictation"
    /// option (its resolved dictation model shown as the quiet secondary line),
    /// then the selectable models grouped "On this Mac" / by cloud provider.
    /// Provider suffixes are stripped for presentation under their headers.
    private var conversationModelSections: [DropdownSection<String?>] {
        var sections: [DropdownSection<String?>] = [
            DropdownSection(items: [
                DropdownItem<String?>(
                    value: nil,
                    title: "Same as dictation",
                    detail: registry.activeModel?.sectionedDisplayName
                )
            ])
        ]
        let models = selectableConversationModels
        let local = models.filter { !$0.isCloud }
        if !local.isEmpty {
            sections.append(DropdownSection(
                header: "On this Mac",
                items: local.map {
                    DropdownItem<String?>(value: $0.id, title: $0.sectionedDisplayName)
                }
            ))
        }
        for provider in [CloudProvider.openAI, .elevenLabs] {
            let group = models.filter { $0.backend.cloudProvider == provider }
            guard !group.isEmpty else { continue }
            sections.append(DropdownSection(
                header: provider.displayName,
                items: group.map {
                    DropdownItem<String?>(value: $0.id, title: $0.sectionedDisplayName)
                }
            ))
        }
        return sections
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
        Plate {
            HStack(spacing: Space.s5) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Palette.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Record a conversation")
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text("Keeps recording in the background while you work — or drop an audio or video file here.")
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .error(let message) = controller.state {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            Text(message)
                                .typo(.caption)
                                .foregroundStyle(Palette.signalWarn)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Dismiss") { controller.dismissError() }
                                .buttonStyle(.plain)
                                .typo(.captionMedium)
                                .foregroundStyle(Palette.accent)
                        }
                        .padding(.top, Space.s1)
                    }
                }
                Spacer(minLength: Space.s5)
                // Start Recording and Upload File… live in the toolbar now, so
                // they stay reachable in every state instead of vanishing with
                // this card.
            }
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

    /// Minimal drop affordance shown while a file hovers the pane: a
    /// material-dimmed, dashed border with an icon and two lines of copy.
    /// Non-interactive so it can never swallow the drag itself.
    ///
    /// Two variants. Accent + "Drop to transcribe" when we can take the file;
    /// muted + a reason when we can't, because a drag that hovers a busy pane
    /// used to get no overlay at all and then bounce back with no explanation.
    @ViewBuilder
    private var dropOverlay: some View {
        if isDropActive {
            dropPlate(
                icon: "waveform.badge.plus",
                title: "Drop to transcribe",
                detail: "Audio or video file",
                tint: Palette.accent
            )
        } else if isDropBlocked {
            dropPlate(
                icon: "hourglass",
                title: "Busy right now",
                detail: busyDropDetail,
                tint: Palette.inkMuted
            )
        }
    }

    private func dropPlate(
        icon: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
                .strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            VStack(spacing: Space.s5) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(spacing: Space.s2) {
                    Text(title)
                        .typo(.title)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(Space.s7)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// Why a hovering file can't be taken right now — the pane's current job.
    private var busyDropDetail: String {
        switch controller.state {
        case .recording: return "Stop the current recording first"
        case .transcribing: return "Wait for this transcript to finish"
        case .importing: return "A file is already being transcribed"
        case .idle, .error: return "Try again in a moment"
        }
    }

    /// Loads the dropped file URL off the (arbitrary-queue) item provider, hops
    /// to the main actor, revalidates, and hands it to the controller.
    /// `isSupportedMedia` is the *only* media gate — the drop registration
    /// accepts any file URL, so the overlay lights up for a PDF too.
    ///
    /// Every rejection that isn't self-evident now says why. Dropping a
    /// non-media file, or several files at once, used to hit a bare `return`:
    /// the overlay had just said "Drop to transcribe", the drag was accepted,
    /// and then nothing happened at all. Busy is the one silent case — the drag
    /// visibly bounces, and `rejectImport` deliberately won't disturb a
    /// recording in flight.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !controller.isBusy else { return false }
        let fileProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard let provider = fileProviders.first else { return false }
        guard fileProviders.count == 1 else {
            controller.rejectImport("Drop one audio or video file at a time.")
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                let controller = MeetingController.shared
                // Re-check on the main actor: state may have changed since the
                // drop landed.
                guard !controller.isBusy else { return }
                guard Self.isSupportedMedia(url) else {
                    controller.rejectImport("“\(url.lastPathComponent)” isn't an audio or video file.")
                    return
                }
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
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(spacing: Space.s5) {
                    RecordingDot()
                    Text("Recording")
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(controller.elapsed.formattedClock)
                        .font(Typo.clockLarge)
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                }

                LevelBars(samples: controller.levelHistory, tint: Palette.ink)
                    .frame(height: 56)

                HStack(spacing: Space.s5) {
                    CapsuleActionButton(
                        title: "Stop & Transcribe",
                        systemImage: "stop.fill"
                    ) {
                        Task { await controller.stop() }
                    }

                    CapsuleActionButton(
                        title: "Cancel",
                        style: .secondary,
                        tint: Palette.ink
                    ) {
                        Task { await controller.cancel() }
                    }

                    Spacer()
                }
            }
        }
    }

    private var transcribingCard: some View {
        Plate {
            HStack(spacing: Space.s6) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Transcribing…")
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(transcribingDetail)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer()
                if controller.totalChunks > 1 {
                    Text("\(controller.transcribedChunks)/\(controller.totalChunks)")
                        .typo(.mono)
                        .foregroundStyle(Palette.inkFaint)
                        .contentTransition(.numericText())
                }
            }
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
        Plate {
            HStack(spacing: Space.s6) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(importTitle)
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    // Name the subject. A long extraction used to say only
                    // "Reading the audio from your file" — true of any file, so
                    // it never confirmed the right one was picked up.
                    if let name = controller.importingFileName {
                        Text(name)
                            .typo(.mono)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                            // Middle truncation keeps the extension visible, so
                            // a clipped name still says what kind of file it is.
                            .truncationMode(.middle)
                            .help(name)
                    }
                    Text(importDetail)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkFaint)
                    if case .extracting(let fraction) = controller.importStage {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, Space.s1)
                    }
                }
                Spacer()
                importTrailingLabel
            }
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
                .typo(.mono)
                .foregroundStyle(Palette.inkFaint)
                .contentTransition(.numericText())
        case .transcribing:
            if controller.totalChunks > 1 {
                Text("\(controller.transcribedChunks)/\(controller.totalChunks)")
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
            }
        }
    }

    private func savedBanner(_ summary: String) -> some View {
        StatusLabel(level: .ready, text: summary)
            .padding(.horizontal, Space.s3)
            .transition(.opacity)
    }

    private var infoNote: some View {
        Text("Record a conversation or upload an existing audio or video file — either way the audio and transcript are saved on this Mac in History. Long recordings are transcribed in segments with the transcription model chosen above.")
            .typo(.caption)
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Softly pulsing dot in `signalLive` — the standard "recording now"
/// affordance. Under Reduce Motion it holds still at 0.85 opacity rather than
/// looping forever.
private struct RecordingDot: View {
    @State private var on = false
    @Environment(\.motion) private var motion

    var body: some View {
        Circle()
            .fill(Palette.signalLive)
            .frame(width: 10, height: 10)
            .opacity(motion.repeatsAllowed ? (on ? 1.0 : 0.35) : 0.85)
            .onAppear {
                guard motion.repeatsAllowed else { return }
                withAnimation(.smooth(duration: 0.9).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}
