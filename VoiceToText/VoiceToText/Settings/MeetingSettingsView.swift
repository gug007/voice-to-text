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
    @Bindable private var hotkeyStore = HotkeyStore.shared
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
                subtitle: "Your mic plus everything you hear, transcribed when you stop."
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

    // Start Recording and Upload File… are not toolbar items. They live in the
    // session card, which is on screen in every state — the card *is* the
    // recorder, and both actions are disabled whenever it is busy. (They were
    // toolbar items while the idle card vanished on state change; see the
    // session card's note for why it no longer does.)

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
        case .idle, .error, .recording, .transcribing:
            sessionCard
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

    // MARK: - Session card
    //
    // One plate for the whole record → transcribe cycle. Ready is the recording
    // card at rest: a grey dot where the live one pulses, the clock at zero, a
    // flat meter, and Start Recording in the slot Stop & Transcribe will take.
    // Starting a recording changes the card's contents in place rather than
    // swapping one card for another, so the geometry never jumps and the eye
    // stays where it was. Stopping freezes the meter and hands the clock to the
    // transcription chunk counter in the same row.

    private var isRecording: Bool { controller.state == .recording }
    private var isTranscribing: Bool { controller.state == .transcribing }

    private var sessionCard: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                sessionHeader

                // Faint and flat until recording starts; desaturates in place
                // when it stops. The same freeze the dictation HUD uses.
                LevelBars(
                    samples: controller.levelHistory,
                    tint: Palette.ink,
                    isFrozen: !isRecording
                )
                .frame(height: 56)

                sessionActions

                if case .error(let message) = controller.state {
                    sessionError(message)
                }
            }
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: Space.s5) {
            if isTranscribing {
                ProgressView()
                    .controlSize(.small)
            } else {
                SessionDot(isLive: isRecording)
            }
            Text(sessionTitle)
                .typo(.headline)
                .foregroundStyle(Palette.ink)
            if isTranscribing, controller.totalChunks > 1 {
                Text("\(controller.transcribedChunks)/\(controller.totalChunks)")
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
            }
            Spacer()
            // The clock reads zero at rest, counts while recording, and holds
            // the recording's length while it is transcribed.
            Text(sessionClock)
                .font(Typo.clockLarge)
                .foregroundStyle(isRecording ? Palette.ink : Palette.inkFaint)
                .contentTransition(.numericText())
        }
    }

    private var sessionTitle: String {
        switch controller.state {
        case .recording: return "Recording"
        case .transcribing: return "Transcribing…"
        case .idle, .error, .importing: return "Ready"
        }
    }

    private var sessionClock: String {
        switch controller.state {
        case .recording, .transcribing: return controller.elapsed.formattedClock
        case .idle, .error, .importing: return TimeInterval(0).formattedClock
        }
    }

    @ViewBuilder
    private var sessionActions: some View {
        switch controller.state {
        case .idle, .error:
            HStack(spacing: Space.s5) {
                CapsuleActionButton(
                    title: "Start Recording",
                    systemImage: "record.circle"
                ) {
                    Task { await controller.start() }
                }
                .help(startRecordingHelp)

                CapsuleActionButton(
                    title: "Upload File…",
                    systemImage: "waveform.badge.plus",
                    style: .secondary,
                    tint: Palette.ink
                ) {
                    chooseAndImportFile()
                }
                .help("Transcribe an audio or video file already on this Mac")

                Spacer(minLength: Space.s5)
                conversationShortcutHint(verb: "from any app")
            }
        case .recording:
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

                Spacer(minLength: Space.s5)
                conversationShortcutHint(verb: "to stop")
            }
        case .transcribing:
            Text(transcribingDetail)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                // Holds the capsule row's height so the card doesn't shrink
                // for the few seconds this state lasts.
                .frame(maxWidth: .infinity, minHeight: Space.s8, alignment: .leading)
        case .importing:
            EmptyView()
        }
    }

    private func sessionError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Text(message)
                .typo(.caption)
                .foregroundStyle(Palette.signalWarn)
                .fixedSize(horizontal: false, vertical: true)
            Button("Dismiss") { controller.dismissError() }
                .buttonStyle(.plain)
                .typo(.captionMedium)
                .foregroundStyle(Palette.accent)
        }
    }

    /// The shortcut, at the trailing end of the action row. Background
    /// recording is meant to be started and then left alone, so the key that
    /// does it from another app sits next to the button that does it here —
    /// and when there isn't one, the way to set it.
    @ViewBuilder
    private func conversationShortcutHint(verb: String) -> some View {
        if let binding = hotkeyStore.meetingBinding {
            HStack(spacing: Space.s3) {
                Text("or press")
                KeyCap(keys: binding.displayKeys)
                Text(verb)
            }
            .typo(.caption)
            .foregroundStyle(Palette.inkMuted)
            .fixedSize()
        } else if !isRecording {
            Button("Set a shortcut to start from any app") {
                SettingsRouter.shared.pendingSection = .hotkey
            }
            .buttonStyle(.plain)
            .typo(.caption)
            .foregroundStyle(Palette.accent)
        }
    }

    private var startRecordingHelp: String {
        let base = "Record a conversation — your mic plus everything you hear"
        guard let binding = hotkeyStore.meetingBinding else { return base }
        return "\(base) (\(binding.displayKeys.joined()) from any app)"
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

    /// Hands the dropped file to the controller. Two provider shapes arrive
    /// here, and the drop has to survive both:
    ///
    ///   • A `public.file-url` provider — what a Finder drag yields when the
    ///     drop registers `.fileURL` alone. `loadObject(ofClass: URL.self)`
    ///     returns the original path.
    ///   • A content-type-only provider (`public.aiff-audio`, `public.mpeg-4`…).
    ///     Because the drop also registers the media types, macOS 26+ keeps
    ///     only the most specific matching representation and drops the file
    ///     URL, so `canLoadObject(ofClass: URL.self)` is false. That was the
    ///     whole bug: a URL-only filter found no provider and returned false —
    ///     overlay, accepted drag, then nothing. `loadItem` for that type still
    ///     yields the original file URL for a Finder drag, and raw data for an
    ///     app that drags content rather than a file, which is staged in a
    ///     temp file for the import.
    ///
    /// Every rejection that isn't self-evident says why. Busy is the one silent
    /// case — the drag visibly bounces, and `rejectImport` deliberately won't
    /// disturb a recording in flight.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !controller.isBusy else { return false }
        guard let provider = providers.first else { return false }
        guard providers.count == 1 else {
            controller.rejectImport("Drop one audio or video file at a time.")
            return false
        }
        // Captured up front: the completion closures below are @Sendable and
        // must not hold the provider itself.
        let name = provider.suggestedName ?? "That file"

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    guard let url else {
                        MeetingController.shared.rejectImport("Couldn't read “\(name)”.")
                        return
                    }
                    await Self.importDropped(url: url, stagedCopy: false)
                }
            }
            return true
        }

        guard let typeID = provider.registeredTypeIdentifiers.first(where: Self.isMediaType) else {
            controller.rejectImport("“\(name)” isn't an audio or video file.")
            return false
        }
        provider.loadItem(forTypeIdentifier: typeID) { item, _ in
            let url = (item as? NSURL).map { $0 as URL }
            let data = (item as? NSData).map { Data(referencing: $0) }
            Task { @MainActor in
                if let url {
                    await Self.importDropped(url: url, stagedCopy: false)
                } else if let data, let staged = Self.stage(data, typeID: typeID, name: name) {
                    await Self.importDropped(url: staged, stagedCopy: true)
                } else {
                    MeetingController.shared.rejectImport("Couldn't read “\(name)”.")
                }
            }
        }
        return true
    }

    /// Revalidates on the main actor — state may have changed since the drop
    /// landed — then runs the import. A staged temp copy is removed afterwards.
    private static func importDropped(url: URL, stagedCopy: Bool) async {
        defer { if stagedCopy { try? FileManager.default.removeItem(at: url) } }
        let controller = MeetingController.shared
        guard !controller.isBusy else { return }
        guard isSupportedMedia(url) else {
            controller.rejectImport("“\(url.lastPathComponent)” isn't an audio or video file.")
            return
        }
        await controller.importMedia(url: url)
    }

    /// Writes dragged content that arrived as bytes to a temp file the extractor
    /// can open, named with the type's extension so AVFoundation can sniff it.
    private static func stage(_ data: Data, typeID: String, name: String) -> URL? {
        let ext = UTType(typeID)?.preferredFilenameExtension
            ?? (name.contains(".") ? URL(fileURLWithPath: name).pathExtension : "bin")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceToText-drop-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Pure and nonisolated: called from the nonisolated provider closures.
    nonisolated private static func isMediaType(_ identifier: String) -> Bool {
        UTType(identifier).map(isMedia) ?? false
    }

    nonisolated private static func isMedia(_ type: UTType) -> Bool {
        type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    /// Whether a URL points at audio or video we can import — mirrors the open
    /// panel's accepted content types.
    private static func isSupportedMedia(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        return type.map(isMedia) ?? false
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

/// The session card's state dot. Live: softly pulsing `signalLive`, the
/// standard "recording now" affordance. At rest: still, in `inkFaint`. One
/// view for both so the swap animates in place with the rest of the card.
/// Under Reduce Motion the live dot holds at 0.85 opacity instead of looping.
private struct SessionDot: View {
    let isLive: Bool
    @State private var on = false
    @Environment(\.motion) private var motion

    var body: some View {
        Circle()
            .fill(isLive ? Palette.signalLive : Palette.inkFaint)
            .frame(width: 10, height: 10)
            .opacity(liveOpacity)
            .onAppear { syncPulse() }
            .onChange(of: isLive) { _, _ in syncPulse() }
    }

    private var liveOpacity: Double {
        guard isLive else { return 1 }
        guard motion.repeatsAllowed else { return 0.85 }
        return on ? 1.0 : 0.35
    }

    /// Starts the pulse when the dot goes live and parks it when it doesn't.
    /// `on` has to return to false without animation so the next live flip
    /// has a state change to animate — `repeatForever` on a no-op is no pulse.
    private func syncPulse() {
        if isLive && motion.repeatsAllowed {
            withAnimation(.smooth(duration: 0.9).repeatForever(autoreverses: true)) {
                on = true
            }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { on = false }
        }
    }
}
