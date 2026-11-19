import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings pane for conversation recording: capture a long conversation (mic +
/// system audio) in the background, then transcribe it on stop and save it to
/// History. The recorder card on top, its options folded under it, then the
/// recorded conversations under date headers.
struct MeetingsPane: View {
    @Bindable private var controller = MeetingController.shared
    @Bindable private var store = RecordingHistoryStore.shared
    @Bindable private var player = HistoryAudioPlayer.shared
    @Bindable private var registry = ModelRegistry.shared
    @Bindable private var hotkeyStore = HotkeyStore.shared
    @State private var screenGranted = ScreenCapturePermission.isGranted
    /// Which insight tab each conversation row is showing. Owned here: rows
    /// are lazy, so a row's own `@State` would not survive scrolling.
    @State private var insightTabs: [UUID: InsightTab] = [:]
    /// The one open conversation row.
    @State private var expandedID: UUID?
    /// True while a drag from Finder is hovering over the pane. Only turns into a
    /// visible drop affordance when the controller is idle (see `isDropActive`).
    @State private var isDropTargeted = false
    /// Whether Recording Options is open. Remembered, folded by default: its
    /// settings are set once and left.
    @AppStorage("conversation.optionsExpanded") private var optionsExpanded = false
    /// The same key `ConversationHUDPanel` watches, so a change lands at once —
    /// on a recording already running too.
    @AppStorage(ConversationHUDSetting.defaultsKey)
    private var hudSetting: ConversationHUDSetting = ConversationHUDSetting.defaultValue
    @AppStorage(ConversationSilenceTrimmer.defaultsKey) private var removeSilence = false
    @AppStorage(ConversationSilenceTrimmer.keepOriginalDefaultsKey) private var keepOriginal = false
    /// The microphone a conversation will record from, for the recorder's
    /// inputs line. Re-read when the preference announces a change.
    @State private var micPreference = MicrophonePreference.stored(in: .standard)
    private let inputMonitor = InputDeviceMonitor.shared
    @Environment(\.motion) private var motion

    /// Types the drop is registered for. A Finder drag arrives as a plain
    /// `public.file-url` provider that does *not* conform to the media content
    /// types, so `.fileURL` must be present or the pane never becomes a drop
    /// target. The media types are kept so promised-content drags from other
    /// apps still register. The file's actual kind is validated on drop.
    private let acceptedDropTypes: [UTType] = [.fileURL] + MediaFileImport.acceptedContentTypes

    /// Show the "drop to transcribe" overlay only when a drag is hovering *and*
    /// we're free to take it.
    private var isDropActive: Bool { isDropTargeted && !controller.isBusy }

    /// Hovering, but the pane is mid-job — the drop will bounce, so say why.
    private var isDropBlocked: Bool { isDropTargeted && controller.isBusy }

    /// Saved conversation recordings, newest first.
    private var conversations: [RecordingHistoryEntry] {
        store.entries.filter { $0.source == .meeting }
    }

    /// How many conversations the Recent group shows before handing off to
    /// History.
    private static let recentLimit = 10

    var body: some View {
        PaneScaffold {
            if !screenGranted && !controller.isBusy {
                permissionCard
            }

            VStack(alignment: .leading, spacing: FormMetrics.groupLabelGap) {
                stateCard
                SettingsGroupFooter("Records your microphone and everything playing on this Mac. Stop & Save keeps the audio so you can transcribe it later.")
            }

            recordingOptionsGroup

            if controller.state == .idle, let summary = controller.lastSavedSummary {
                savedBanner(summary)
            }

            conversationsList
        }
        .animation(motion.layout, value: controller.state)
        .animation(motion.layout, value: conversations)
        // The whole pane is a drop target for a single audio/video file.
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
        // Device listeners only while idle: during a recording they would
        // contend with the capture's audio graph, and the line shows the
        // last known name anyway.
        .task(id: controller.isBusy) {
            guard !controller.isBusy else { return }
            await inputMonitor.observe()
        }
        .onReceive(NotificationCenter.default.publisher(for: MicrophonePreference.didChangeNotification)) { _ in
            micPreference = MicrophonePreference.stored(in: .standard)
        }
        // Don't strand a stale error message, or keep a clip playing, when the
        // user navigates away (dismissError is a no-op while busy).
        .onDisappear {
            controller.dismissError()
            player.stop()
        }
        .overlay { UndoDeletionBar(store: store) }
    }

    // MARK: - Recorded conversations

    /// The latest conversations in one group of compact rows that open on
    /// click; "Show All" on its header opens History filtered to
    /// conversations, where search and filters live.
    @ViewBuilder
    private var conversationsList: some View {
        // One scan of History per pass: the pane re-renders at meter rate
        // while recording.
        let conversations = conversations
        if conversations.isEmpty {
            // While the first one records or transcribes, the session card's
            // progress is the state; "nothing yet" would contradict it.
            if !controller.isBusy {
                LibraryEmptyState(
                    systemImage: "person.2.wave.2",
                    title: "No conversations yet",
                    message: "Record a call, or drop an audio or video file here. Transcripts appear in this list and in History."
                )
                .transition(.opacity)
            }
        } else {
            RecordingSectionsList(
                sections: [HistorySection(id: "recent", title: "Recent", entries: Array(conversations.prefix(Self.recentLimit)))],
                showsTypeBadge: false,
                insightTabs: $insightTabs,
                expandedID: $expandedID,
                headerLink: .init(
                    title: conversations.count > Self.recentLimit
                        ? "Show All (\(conversations.count))"
                        : "Open in History",
                    help: "Open History showing every conversation, with search and filters",
                    action: {
                        HistoryPane.pendingFilter = .conversations
                        SettingsRouter.shared.pendingSection = .history
                    }
                )
            )
        }
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

    // MARK: - Recording options

    /// The transcription model, Remove silence and the Recording HUD, folded
    /// to one row that says what the next recording will use. The summary
    /// shows only while folded; open, the rows say it themselves.
    private var recordingOptionsGroup: some View {
        SettingsGroup {
            recordingOptionsDisclosure

            if optionsExpanded {
                if !controller.isBusy {
                    transcriptionModelRow
                }
                SettingsRow(
                    "Remove silence",
                    caption: "Cuts stretches with no speech out of the saved audio before transcribing.",
                    isOn: $removeSilence
                )
                if removeSilence {
                    SettingsRow(
                        "Keep original",
                        caption: "Also saves the full recording next to the trimmed one.",
                        isOn: $keepOriginal
                    )
                }
                hudRow
            }
        }
        .animation(motion.layout, value: optionsExpanded)
        .animation(motion.layout, value: controller.isBusy)
        .animation(motion.layout, value: removeSilence)
    }

    /// The whole row is the disclosure button, chevron on the leading side.
    private var recordingOptionsDisclosure: some View {
        Button {
            optionsExpanded.toggle()
        } label: {
            HStack(spacing: Space.s4) {
                Image(systemName: "chevron.right")
                    .font(Typo.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
                    .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    .frame(width: Space.s5)
                    .accessibilityHidden(true)
                Text("Recording Options")
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize()
                Spacer(minLength: Space.s5)
                if !optionsExpanded {
                    recordingOptionsSummaryText
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .settingsRowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(optionsExpanded ? "Hide recording options" : "Show recording options")
        .accessibilityLabel("Recording options")
        .accessibilityValue(optionsExpanded ? "Expanded" : "Collapsed, \(recordingOptionsSummary)")
    }

    /// "☁ GPT Transcribe · OpenAI · Small HUD" — the one place the folded pane
    /// names the model, with where it runs.
    private var recordingOptionsSummaryText: Text {
        guard let model = registry.conversationModel else { return Text(recordingOptionsSummary) }
        return Text(Image(systemName: model.sourceSymbol)) + Text(" \(model.nameWithSource) · \(optionsSummaryTail)")
    }

    /// "GPT Transcribe · OpenAI · Small HUD" — what the next recording will use.
    private var recordingOptionsSummary: String {
        let model = registry.conversationModel?.nameWithSource ?? "No model"
        return "\(model) · \(optionsSummaryTail)"
    }

    /// "Small HUD", or "Small HUD · Silence removed".
    private var optionsSummaryTail: String {
        let hud = hudSetting == .off ? "HUD off" : "\(hudSetting.title) HUD"
        return removeSilence ? "\(hud) · Silence removed" : hud
    }

    /// A transcription model for conversations, independent of dictation's.
    /// Only while idle — it has no bearing on a recording in flight. Streaming
    /// models are excluded: they're built for live mic input.
    private var transcriptionModelRow: some View {
        SettingsRow("Transcription model", caption: conversationModelLocation) {
            MinimalDropdown(
                selection: conversationModelBinding,
                sections: conversationModelSections,
                title: "Transcription model",
                tooltip: "The model that transcribes conversations and imported files"
            )
        }
    }

    /// Off / Small / Medium / Large — the card that floats over every app while
    /// a conversation records. One row, no preview: the HUD family is previewed
    /// on General, and this plate should not push the recordings off screen.
    private var hudRow: some View {
        SettingsRow("Conversation HUD", caption: hudCaption) {
            Picker("Conversation HUD", selection: $hudSetting) {
                ForEach(ConversationHUDSetting.allCases) { setting in
                    Text(setting.title).tag(setting)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var hudCaption: String {
        switch hudSetting {
        case .off: return "No floating card; the menu bar shows the recording."
        case .small: return "Floats over every app: meter, clock and the two Stop buttons."
        case .medium: return "Floats over every app: one row with Stop & Save and Stop & Transcribe."
        case .large: return "Floats over every app: wide meter, clock, Stop & Save and Stop & Transcribe."
        }
    }

    /// Where the audio goes, for the model a conversation will actually use —
    /// a cloud model uploads an hour of someone's meeting.
    private var conversationModelLocation: String {
        guard let model = registry.conversationModel else {
            return "Used for recordings and uploaded files."
        }
        if let provider = model.backend.cloudProvider {
            return "Audio is uploaded to \(provider.displayName) to transcribe it."
        }
        return "Transcribed on this Mac; audio never leaves it."
    }

    /// The catalog minus streaming/realtime engines, which don't apply to
    /// buffered file transcription.
    private var selectableConversationModels: [ModelDescriptor] {
        ModelCatalog.all.filter { !$0.isRealtime }
    }

    /// A lead "Same as dictation" option (the model it actually transcribes
    /// with as its detail), then the models grouped "On this Mac" / by provider.
    private var conversationModelSections: [DropdownSection<String?>] {
        var sections: [DropdownSection<String?>] = [
            DropdownSection(items: [
                DropdownItem<String?>(
                    value: nil,
                    title: "Same as dictation",
                    detail: sameAsDictationDetail
                )
            ])
        ]
        sections += DropdownSection.models(selectableConversationModels, value: { Optional($0.id) })
        return sections
    }

    /// Names the model "Same as dictation" really uses. A live dictation model
    /// never transcribes recordings — `ModelRegistry.conversationModel` swaps in
    /// a batch one — so the line says which, and why.
    private var sameAsDictationDetail: String? {
        guard let used = registry.dictationModelForConversations else { return nil }
        let name = used.model.sectionedDisplayName
        guard used.model.id != registry.activeModel?.id else { return name }
        return used.needsDownload ? "\(name) (download needed)" : "\(name) (dictation model is live)"
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
    // One plate for the whole record → transcribe cycle. At rest it is two
    // lines: what will be captured, and the two ways to start. Recording adds
    // the clock and the live meter in place; stopping freezes the meter and
    // hands the row to the transcription progress.

    private var isRecording: Bool { controller.state == .recording }
    private var isTranscribing: Bool { controller.state == .transcribing }

    private var sessionCard: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s5) {
                sessionHeader

                if isRecording || isTranscribing {
                    LevelBars(
                        samples: controller.levelHistory,
                        tint: Palette.ink,
                        isFrozen: !isRecording
                    )
                    .frame(height: 44)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                }

                sessionActions

                if case .error(let message) = controller.state {
                    sessionError(message)
                }
            }
        }
    }

    /// "● Ready" on one baseline, the inputs and model under it — all on the
    /// card's one leading edge, with the buttons and the shortcut below.
    private var sessionHeader: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(alignment: .center, spacing: Space.s3) {
                    if isTranscribing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        SessionDot(isLive: isRecording, restingTone: restingTone)
                    }
                    Text(sessionTitle)
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    if isTranscribing, controller.totalChunks > 1 {
                        Text("\(controller.transcribedChunks)/\(controller.totalChunks)")
                            .typo(.mono)
                            .foregroundStyle(Palette.inkMuted)
                            .contentTransition(.numericText())
                    }
                }
                sessionDetail
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: Space.s4)

            // Counts while recording, holds the length while it is transcribed.
            if isRecording || isTranscribing {
                Text(controller.elapsed.formattedClock)
                    .font(Typo.clockLarge)
                    .foregroundStyle(isRecording ? Palette.ink : Palette.inkMuted)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Elapsed \(controller.elapsed.formattedClock)")
            }
        }
    }

    /// The app-wide ready green when a recording can start; attention when
    /// something is in the way (no Screen Recording access, a failed start).
    private var restingTone: AppStatus.Tone {
        if case .error = controller.state { return .attention }
        return screenGranted ? .ready : .attention
    }

    private var sessionTitle: String {
        switch controller.state {
        case .recording: return "Recording"
        case .transcribing:
            if controller.isRemovingSilence { return "Removing silence…" }
            return controller.isSavingWithoutTranscript ? "Saving…" : "Transcribing…"
        case .idle, .error, .importing: return "Ready"
        }
    }

    /// What will be captured: "MacBook Pro Microphone + system audio". The
    /// model is named once, in Recording Options. While transcribing, what is
    /// happening instead.
    private var sessionDetail: Text {
        if isTranscribing { return Text(transcribingDetail) }
        let mic = microphoneName ?? "Microphone"
        return Text(screenGranted
            ? "\(mic) + system audio"
            : "\(mic) · system audio needs Screen Recording access")
    }

    /// The pinned microphone while it is connected, otherwise the system
    /// default the recorder will fall back to.
    private var microphoneName: String? {
        let menu = MicrophoneMenu(
            storedUID: micPreference.uid,
            lastKnownName: micPreference.lastKnownName,
            snapshot: inputMonitor.snapshot
        )
        if let uid = menu.selection,
           let row = menu.devices.first(where: { $0.value == uid }),
           row.detail == nil {
            return row.title
        }
        return inputMonitor.snapshot?.defaultInputName ?? micPreference.lastKnownName
    }

    @ViewBuilder
    private var sessionActions: some View {
        switch controller.state {
        case .idle, .error:
            actionRow(verb: "in any app") {
                Button {
                    Task { await controller.start() }
                } label: {
                    Label("Start Conversation", systemImage: "record.circle")
                }
                .buttonTier(.primary)
                .help(startRecordingHelp)

                Button {
                    MediaFileImport.chooseAndImport()
                } label: {
                    Label("Transcribe File…", systemImage: "waveform.badge.plus")
                }
                .buttonTier(.secondary)
                .help("Transcribe an audio or video file already on this Mac. You can also drop one on this pane.")
            }
        case .recording:
            actionRow(verb: "to stop and transcribe") {
                Button {
                    Task { await controller.stop() }
                } label: {
                    Label("Stop & Transcribe", systemImage: "stop.fill")
                }
                .buttonTier(.primary)

                Button {
                    Task { await controller.stopAndSave() }
                } label: {
                    Label("Stop & Save", systemImage: "square.and.arrow.down")
                }
                .buttonTier(.secondary)
                .help("Stop and keep the audio without transcribing it. Transcribe it later from this list or from History.")

                // Apart from the two that keep the recording: this one
                // throws it away.
                Spacer(minLength: Space.s4)

                Button("Cancel") {
                    Task { await controller.cancel() }
                }
                .buttonTier(.secondary)
                .help("Stop and discard this recording")
            }
        case .transcribing, .importing:
            EmptyView()
        }
    }

    /// The buttons, and under them the shortcut as one caption line.
    private func actionRow<Buttons: View>(
        verb: String,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s4) { buttons() }
            conversationShortcutHint(verb: verb)
        }
    }

    private func sessionError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typo.caption)
                .foregroundStyle(Palette.signalWarn)
                .accessibilityHidden(true)
            Text(message)
                .typo(.caption)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            // Only when the recording reached History: after a failed start or
            // a too-short stop there is nothing there to show.
            if controller.erroredRecording != nil {
                Button("Show in History") { WindowOpener.shared.showMain(section: .history) }
                    .buttonStyle(TextLinkButtonStyle(font: Typo.captionMedium))
                    .fixedSize()
            }
            Button("Dismiss") { controller.dismissError() }
                .buttonTier(.secondary)
                .controlSize(.small)
                .fixedSize()
        }
    }

    /// The shortcut, printed as keycaps. Background recording is meant to be
    /// started and left alone, so the key that does it from another app sits
    /// next to the button that does it here — and when there isn't one, the
    /// way to set it.
    @ViewBuilder
    private func conversationShortcutHint(verb: String) -> some View {
        if let binding = hotkeyStore.meetingBinding {
            HStack(spacing: Space.s2) {
                Text("Or press")
                Keycap(keys: binding.displayKeys, size: .small)
                Text("\(verb).")
            }
            .typo(.caption)
            .foregroundStyle(Palette.inkMuted)
            .fixedSize()
        } else if !isRecording {
            Button("Set a Shortcut…") {
                SettingsRouter.shared.pendingSection = .hotkey
            }
            .buttonStyle(TextLinkButtonStyle(font: Typo.caption))
            .help("Set a shortcut to start a conversation from any app")
            .fixedSize()
        }
    }

    private var startRecordingHelp: String {
        let base = "Record a conversation — your mic plus everything you hear"
        guard let binding = hotkeyStore.meetingBinding else { return base }
        return "\(base) (\(Keycap.spokenName(for: binding.displayKeys)) from any app)"
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

        guard let typeID = provider.registeredTypeIdentifiers.first(where: MediaFileImport.isMediaType) else {
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
        guard MediaFileImport.isSupportedMedia(url) else {
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

    private var transcribingDetail: String {
        if controller.isRemovingSilence {
            return "Cutting the stretches with no speech out of the recording."
        }
        if controller.isSavingWithoutTranscript {
            return "Filing the recording in History, without a transcript."
        }
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
        case .transcribing: return controller.isRemovingSilence ? "Removing silence…" : "Transcribing…"
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
            .padding(.horizontal, FormMetrics.rowHorizontalPadding)
            .transition(.opacity)
    }
}

/// The session card's state dot. Live: softly pulsing `signalLive`, the
/// standard "recording now" affordance. At rest: still, in `inkFaint`. One
/// view for both so the swap animates in place with the rest of the card.
/// Under Reduce Motion the live dot holds at 0.85 opacity instead of looping.
private struct SessionDot: View {
    let isLive: Bool
    var restingTone: AppStatus.Tone = .ready
    @State private var on = false
    @Environment(\.motion) private var motion

    var body: some View {
        Group {
            if isLive {
                Circle()
                    .fill(Palette.signalLive)
                    .frame(width: 10, height: 10)
                    .opacity(liveOpacity)
            } else {
                StatusDot(restingTone, size: 10)
            }
        }
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
