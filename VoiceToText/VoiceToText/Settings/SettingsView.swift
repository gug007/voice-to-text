import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Bindable var registry: ModelRegistry
    @State private var selection: Section = .general
    @Bindable private var router = SettingsRouter.shared
    @Environment(\.motion) private var motion

    /// The sidebar, as data. Enum declaration order used to decide what the
    /// sidebar looked like; these two groups decide it now, and the enum is
    /// free to be in whatever order the routing wants.
    static let sidebarGroups: [SidebarGroup] = [
        SidebarGroup(title: "Dictate", sections: [.general, .meetings, .history]),
        SidebarGroup(title: "Configure", sections: [.hotkey, .models, .actions, .corrections, .cloud, .iphone, .updates])
    ]

    enum Section: String, CaseIterable, Identifiable {
        case general, meetings, history, hotkey, models, actions, corrections, cloud, iphone, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .models: return "Models"
            case .hotkey: return "Shortcut"
            case .actions: return "Actions"
            case .corrections: return "Corrections"
            case .meetings: return "Conversations"
            case .history: return "History"
            case .cloud: return "Cloud"
            case .iphone: return "iPhone"
            case .general: return "General"
            case .updates: return "Updates"
            }
        }
        var icon: String {
            switch self {
            case .models: return "waveform"
            case .hotkey: return "command"
            case .actions: return "wand.and.stars"
            case .corrections: return "character.book.closed"
            case .meetings: return "person.2.wave.2"
            case .history: return "clock.arrow.circlepath"
            case .cloud: return "cloud"
            case .iphone: return "iphone"
            case .general: return "slider.horizontal.3"
            case .updates: return "arrow.down.circle"
            }
        }
        /// What a dot beside the row's title stands for, or nil for no dot.
        /// Updates has one because an update found by a background check
        /// doesn't prompt, so this and the menu bar item are where it waits.
        /// iPhone has one while a phone is hearing the conversation live.
        var badge: String? {
            switch self {
            case .updates:
                return AppUpdater.shared.indicatedVersion.map { "Version \($0) available" }
            case .iphone:
                return RemoteControlController.shared.liveListeners > 0 ? "iPhone listening" : nil
            case .general, .meetings, .history, .hotkey, .models, .actions, .corrections, .cloud:
                return nil
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 188, ideal: 208, max: 260)
        } detail: {
            // The pane swap is the one place `Motion.layout` shows itself in the
            // window: the arriving pane fades up 4pt, the leaving one just
            // fades. The sidebar is outside this scope on purpose — its capsule
            // slides on `Motion.select` and must never cross-fade with it.
            ZStack(alignment: .topLeading) {
                detailView
                    .transition(.paneSwap)
                    .id(selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(motion.layout, value: selection)
            // The canvas sits under the plates so white groups separate from
            // the page in light mode; it runs under the toolbar too.
            .background(Palette.canvas.ignoresSafeArea())
            // The toolbar names the pane; panes carry no in-content title.
            .navigationTitle(selection.title)
        }
        .frame(minWidth: 720, minHeight: 480)
        .containerBackground(Palette.canvas, for: .window)
        .modifier(SoftToolbarEdge())
        // Two arrivals to cover: the window was already open (onChange), or it
        // was just created for this request (task).
        .task { consumePendingSection() }
        .onChange(of: router.pendingSection) { _, _ in consumePendingSection() }
    }

    private func consumePendingSection() {
        guard let pending = router.pendingSection else { return }
        selection = pending
        router.pendingSection = nil
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .models: ModelsPane(registry: registry, onShowCloudSettings: { selection = .cloud })
        case .hotkey: HotkeyPane()
        case .actions: ActionsPane(onShowCloudSettings: { selection = .cloud })
        case .corrections: CorrectionsPane()
        case .meetings: MeetingsPane()
        case .history: HistoryPane()
        case .cloud: CloudPane()
        case .iphone: IPhonePane()
        case .general: GeneralPane()
        case .updates: UpdatesPane()
        }
    }
}

/// The toolbar draws no backing or separator; `PaneScaffold` fades content
/// into the canvas just below it instead (`ToolbarFade`), so scrolled text
/// dissolves under the pane title rather than being sliced at a hairline.
private struct SoftToolbarEdge: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Retired pane description. Panes open straight on their first group (the
/// judges read the one-line descriptions as filler); anything a pane still
/// needs to say goes in a group footer. Renders nothing; kept so call sites
/// compile until they are removed.
struct PaneHeader: View {
    var title: String = ""
    let subtitle: String

    var body: some View {
        EmptyView()
    }
}

struct HotkeyPane: View {
    @Bindable private var store = HotkeyStore.shared
    @State private var capturing: CaptureTarget?
    @State private var monitor: Any?
    @State private var errorMessage: String?
    /// The row an error belongs to, so it shows under the shortcut it is about.
    @State private var errorTarget: CaptureTarget?
    @State private var captureSession = HotkeyCaptureSession()
    @State private var pendingUndo: PendingUndo?
    private var registry: ModelRegistry { .shared }

    /// Which shortcut a live capture belongs to. Only one can be capturing at
    /// a time — there is a single local event monitor.
    private enum CaptureTarget {
        case dictation
        case second
        case meeting

        var slot: ShortcutSlot {
            switch self {
            case .dictation: return .dictation
            case .second: return .secondDictation
            case .meeting: return .conversation
            }
        }

        var title: String {
            switch self {
            case .dictation: return "Dictation shortcut"
            case .second: return "Second shortcut"
            case .meeting: return "Conversation shortcut"
            }
        }
    }

    /// The trailing geometry every shortcut row shares: the keys, a slot for
    /// the row's clear or reset glyph, then Change / Set / Cancel. Fixed
    /// widths, so keys and buttons line up whichever row they're in.
    private static let accessorySlotWidth: CGFloat = 64
    private static let primaryButtonWidth: CGFloat = 64

    var body: some View {
        PaneScaffold {
            VStack(alignment: .leading, spacing: FormMetrics.groupLabelGap) {
                SettingsGroup("Dictation") {
                    shortcutRow(.dictation)
                    shortcutRow(.second)
                    SettingsRow("Recording mode", caption: "Applies to both dictation shortcuts.") {
                        Picker("Recording mode", selection: modeBinding) {
                            ForEach(RecordingShortcutMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    SettingsRow(
                        "Esc cancels dictation",
                        caption: "Cancels while recording or reviewing. Turn off if Esc clashes with another app.",
                        isOn: escapeCancelsDictationBinding
                    )
                    .help("While recording, Esc cancels from any app; while transcribing or reviewing, from the app you're dictating into. Esc typed on the card itself always works.")
                }
                modifierRuleFooter
            }

            SettingsGroup("Conversations") {
                shortcutRow(.meeting)
            }

            VStack(alignment: .leading, spacing: FormMetrics.groupLabelGap) {
                SettingsGroup("In the Review Card") {
                    referenceRow("Paste", detail: "Pastes the text where you were typing.", keys: store.binding.displayKeys)
                    referenceRow("Resume", detail: "Records more and inserts it at the text cursor.", keys: ["⌘", "R"])
                    referenceRow("Copy", detail: "Copies the text and closes the card.", keys: ["⇧", "⌘", "C"])
                    referenceRow("Actions", detail: "Runs the numbered action on the card.", keys: ["⌘", "1–9"])
                    referenceRow("Cancel", detail: "Closes the card without pasting.", keys: ["Esc"])
                }
                reviewCardFooter
            }
        }
        .onDisappear { stopCapture(cancelled: true) }
        .overlay { UndoRemovalBar(pending: $pendingUndo) }
    }

    // MARK: - Shortcut rows

    /// Title and caption, then the shared trailing geometry: the keys (or
    /// "Not set", or the live capture prompt), the clear / reset glyph slot,
    /// and Change / Set / Cancel on the trailing edge.
    private func shortcutRow(_ target: CaptureTarget) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s4) {
                rowLabel(for: target)
                    .frame(maxWidth: .infinity, alignment: .leading)
                shortcutKeys(for: target)
                    .padding(.leading, Space.s4)
                // A fixed slot even when empty, so the keys stay put.
                Color.clear
                    .frame(width: Self.accessorySlotWidth, height: FormMetrics.linkHitHeight)
                    .overlay(alignment: .trailing) { accessoryButton(for: target) }
                primaryButton(for: target)
            }
            if errorTarget == target, let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .typo(.caption)
                    .foregroundStyle(Palette.signalWarn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .settingsRowPadding()
        .accessibilityElement(children: .contain)
    }

    private func binding(for target: CaptureTarget) -> HotkeyBinding? {
        switch target {
        case .dictation: return store.binding
        case .second: return store.secondBinding
        case .meeting: return store.meetingBinding
        }
    }

    @ViewBuilder
    private func shortcutKeys(for target: CaptureTarget) -> some View {
        if capturing == target {
            capturePrompt
        } else if let binding = binding(for: target) {
            Keycap(keys: binding.displayKeys, style: .editable)
        } else {
            Text("Not set")
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private func primaryButton(for target: CaptureTarget) -> some View {
        let title: String
        if capturing == target {
            title = "Cancel"
        } else {
            title = binding(for: target) == nil ? "Set" : "Change"
        }
        return Button {
            if capturing == target {
                stopCapture(cancelled: true)
            } else {
                startCapture(target)
            }
        } label: {
            Text(title)
                .frame(width: Self.primaryButtonWidth)
        }
        .buttonTier(.secondary)
        .keyboardShortcut(primaryShortcut(for: target))
        .accessibilityLabel(capturing == target ? "Cancel" : "\(title) \(target.title.lowercased())")
    }

    /// Return confirms the dictation change only while nothing is capturing,
    /// and Esc cancels whichever capture is live — so two buttons can never
    /// both claim Esc or Return.
    private func primaryShortcut(for target: CaptureTarget) -> KeyboardShortcut? {
        if capturing == target { return .cancelAction }
        if target == .dictation, capturing == nil { return .defaultAction }
        return nil
    }

    /// "Clear" for a shortcut that can be removed (with Undo; Set brings it
    /// back), "Reset" for a changed dictation shortcut: plain bordered buttons
    /// like Change, in their own slot.
    @ViewBuilder
    private func accessoryButton(for target: CaptureTarget) -> some View {
        if capturing != target {
            switch target {
            case .dictation:
                if store.binding != .defaultBinding {
                    Button("Reset") { resetDictationShortcut() }
                        .buttonTier(.secondary)
                        .help("Reset to Option-Space")
                        .accessibilityLabel("Reset dictation shortcut to Option-Space")
                }
            case .second:
                if store.secondBinding != nil {
                    Button("Clear") { removeSecondShortcut() }
                        .buttonTier(.secondary)
                        .help("Remove the second shortcut")
                        .accessibilityLabel("Clear second shortcut")
                }
            case .meeting:
                if store.meetingBinding != nil {
                    Button("Clear") { removeMeetingBinding() }
                        .buttonTier(.secondary)
                        .help("Remove the conversation shortcut")
                        .accessibilityLabel("Clear conversation shortcut")
                }
            }
        }
    }

    /// Title, then what the shortcut does. The second shortcut shows its own
    /// model picker; the dictation model is the sidebar chip's.
    @ViewBuilder
    private func rowLabel(for target: CaptureTarget) -> some View {
        if capturing == target || target != .second {
            SettingsRowLabel(title: target.title, caption: caption(for: target))
        } else {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(target.title)
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: Space.s2) {
                    Text("Dictates with")
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                    MinimalDropdown(
                        selection: secondModelBinding,
                        sections: secondModelSections,
                        placeholder: "Choose a model",
                        title: "Model for the second shortcut",
                        tooltip: store.secondBinding == nil
                            ? "Set a second shortcut first."
                            : "The model this shortcut dictates with"
                    )
                    .controlSize(.small)
                    .disabled(store.secondBinding == nil)
                }
                // Says why the picker is dimmed, at full caption contrast.
                if store.secondBinding == nil {
                    Text("Set a second shortcut first.")
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
        }
    }

    private func caption(for target: CaptureTarget) -> String {
        if capturing == target {
            return target == .dictation
                ? "Press a key combination, or Right Control alone. Esc cancels."
                : "Press a key combination. Esc cancels."
        }
        switch target {
        case .dictation, .second:
            return "Starts and stops dictation from any app."
        case .meeting:
            return "Starts or stops a conversation recording from any app."
        }
    }

    /// A read-only, single-line row: the card's button name, what it does,
    /// and its key — tighter than a setting row, since nothing here is edited.
    private func referenceRow(_ title: String, detail: String, keys: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            // A fixed title column, so the explanations start on one edge.
            Text(title)
                .typo(.body)
                .foregroundStyle(Palette.ink)
                .frame(width: 72, alignment: .leading)
            Text(detail)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .lineLimit(1)
            Spacer(minLength: Space.s4)
            Keycap(keys: keys)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .padding(.vertical, Space.s4)
        .padding(.horizontal, FormMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footers

    /// The modifier rule, with the modifiers drawn as SF Symbols — the text
    /// ⌃ renders as a raised caret.
    private var modifierRuleFooter: some View {
        Text("A shortcut needs Control \(Image(systemName: "control")), Option \(Image(systemName: "option")), Shift \(Image(systemName: "shift")) or Command \(Image(systemName: "command")), or a function key.")
            .typo(.caption)
            .foregroundStyle(Palette.inkMuted)
            .padding(.horizontal, FormMetrics.rowHorizontalPadding)
            .accessibilityLabel("A shortcut needs Control, Option, Shift or Command, or a function key.")
    }

    /// "Choose when the review card opens in General › Review before
    /// pasting.", the pane name a link that goes there.
    private var reviewCardFooter: some View {
        HStack(spacing: Space.s1) {
            Text("Choose when the review card opens in")
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
            Button("General › Review before pasting") {
                SettingsRouter.shared.pendingSection = .general
            }
            .buttonStyle(TextLinkButtonStyle(font: Typo.caption))
            .accessibilityHint("Opens the General pane")
        }
        .padding(.horizontal, FormMetrics.rowHorizontalPadding)
    }

    // MARK: - Second shortcut model

    /// Exactly what the shortcut will use: with no model stored (or one the
    /// catalog dropped) the picker shows "Choose a model", never a default
    /// the shortcut wouldn't actually dictate with.
    private var secondModelBinding: Binding<String> {
        Binding(
            get: { store.secondModelId ?? "" },
            set: { store.updateSecondModel(to: $0) }
        )
    }

    /// Every model, grouped as the conversation model picker groups them: "On
    /// this Mac", then each cloud provider. One that can't run yet says why on
    /// the right; a press then downloads it or asks for the key, as it would
    /// for the dictation model.
    private var secondModelSections: [DropdownSection<String>] {
        DropdownSection<String>.models(ModelCatalog.all, value: \.id) { model in
            switch registry.readiness(for: model.id) {
            case .installed: return nil
            case .preparing: return "Downloading"
            case .notInstalled, .failed: return model.isCloud ? "No API key" : "Not downloaded"
            }
        }
    }

    /// What a newly set second shortcut dictates with.
    private var defaultSecondModelId: String? {
        SecondShortcutModel.defaultModelID(
            candidates: ModelCatalog.all.map {
                SecondShortcutModel.Candidate(id: $0.id, isReady: registry.readiness(for: $0.id).isInstalled)
            },
            activeModelID: registry.activeModelId
        )
    }

    private func removeSecondShortcut() {
        guard let removed = store.secondBinding else { return }
        let removedModelId = store.secondModelId
        store.clearSecondShortcut()
        pendingUndo = PendingUndo(title: "Shortcut removed") {
            guard store.secondBinding == nil, isFree(removed, for: .second) else { return }
            store.updateSecondModel(to: removedModelId)
            store.updateSecondBinding(to: removed)
        }
    }

    private func removeMeetingBinding() {
        guard let removed = store.meetingBinding else { return }
        store.clearMeetingBinding()
        pendingUndo = PendingUndo(title: "Shortcut removed") {
            // Not over a shortcut set since, nor onto a key another took.
            guard store.meetingBinding == nil, isFree(removed, for: .meeting) else { return }
            store.updateMeetingBinding(to: removed)
        }
    }

    private func resetDictationShortcut() {
        if let owner = conflictingSlot(for: .defaultBinding, target: .dictation) {
            errorMessage = owner.inUseMessage
            errorTarget = .dictation
            return
        }
        errorMessage = nil
        store.resetToDefault()
    }

    /// What each shortcut is bound to now, for collisions.
    private var currentKeys: [ShortcutSlot: ShortcutKey] {
        var keys: [ShortcutSlot: ShortcutKey] = [.dictation: store.binding.shortcutKey]
        keys[.secondDictation] = store.secondBinding?.shortcutKey
        keys[.conversation] = store.meetingBinding?.shortcutKey
        return keys
    }

    private func conflictingSlot(for binding: HotkeyBinding, target: CaptureTarget) -> ShortcutSlot? {
        ShortcutConflicts.owner(of: binding.shortcutKey, assigningTo: target.slot, bindings: currentKeys)
    }

    private func isFree(_ binding: HotkeyBinding, for target: CaptureTarget) -> Bool {
        conflictingSlot(for: binding, target: target) == nil
    }

    /// The outline shown in place of the key caps while a capture is live.
    private var capturePrompt: some View {
        Text("Press a shortcut…")
            .typo(.captionMedium)
            .foregroundStyle(Palette.inkMuted)
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 1.5)
            )
    }

    private var modeBinding: Binding<RecordingShortcutMode> {
        Binding(
            get: { store.mode },
            set: { store.updateMode(to: $0) }
        )
    }

    private var escapeCancelsDictationBinding: Binding<Bool> {
        Binding(
            get: { store.escapeCancelsDictation },
            set: { store.updateEscapeCancelsDictation($0) }
        )
    }

    private func startCapture(_ target: CaptureTarget) {
        // Starting one capture drops whichever was live: a single monitor.
        stopCapture(cancelled: true)
        captureSession = makeCaptureSession(for: target)
        capturing = target
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event: event)
            return nil
        }
    }

    /// Only the dictation shortcut can take standalone Right Control
    /// (dictation's event tap owns it). Keys another shortcut already holds
    /// are refused as they're captured (`ShortcutConflicts`).
    private func makeCaptureSession(for target: CaptureTarget) -> HotkeyCaptureSession {
        HotkeyCaptureSession(allowsStandaloneModifier: target.slot.allowsStandaloneModifier)
    }

    private func handle(event: NSEvent) {
        guard let target = capturing else { return }
        switch captureSession.handle(event: event) {
        case .ignored, .pendingStandaloneModifier:
            break
        case .cancelled:
            stopCapture(cancelled: true)
        case .captured(let candidate):
            if let owner = conflictingSlot(for: candidate, target: target) {
                // Still listening: the user can press another key straight away.
                errorMessage = owner.inUseMessage
                errorTarget = target
                captureSession.reset()
                return
            }
            errorMessage = nil
            switch target {
            case .dictation: store.update(to: candidate)
            case .second:
                if store.secondModelId == nil {
                    store.updateSecondModel(to: defaultSecondModelId)
                }
                store.updateSecondBinding(to: candidate)
            case .meeting: store.updateMeetingBinding(to: candidate)
            }
            stopCapture(cancelled: false)
        case .rejected(let message):
            errorMessage = message
            errorTarget = target
        }
    }

    private func stopCapture(cancelled: Bool) {
        capturing = nil
        captureSession.reset()
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if cancelled { errorMessage = nil }
    }
}

struct GeneralPane: View {
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var listenEventGranted = ListenEventPermission.isGranted
    @State private var micStatus = MicPermission.status
    @State private var hotkeyRegistrationRefreshID = 0
    @State private var permissionAlert: PermissionAlert?
    @Bindable private var dictation = DictationController.shared
    @Bindable private var loginItem = LoginItemController.shared
    @Bindable private var presence = AppPresenceController.shared
    @Bindable private var appearance = AppearanceController.shared
    private var registry: ModelRegistry { .shared }

    enum PermissionAlert: String, Identifiable {
        case microphone
        case accessibility

        var id: String { rawValue }

        var title: String {
            switch self {
            case .microphone: return PermissionCopy.microphoneAlertTitle
            case .accessibility: return PermissionCopy.accessibilityAlertTitle
            }
        }

        /// Both bodies are assembled from `PermissionCopy`, so a card subtitle
        /// and its alert can never disagree about where the setting lives.
        var message: String {
            switch self {
            case .microphone: return PermissionCopy.microphoneAlertBody
            case .accessibility: return PermissionCopy.accessibilityAlertBody
            }
        }

        func openSystemSettings() {
            switch self {
            case .microphone:
                MicPermission.openSystemSettings()
            case .accessibility:
                AccessibilityPermission.promptForPermission()
                AccessibilityPermission.openSystemSettings()
            }
        }
    }

    var body: some View {
        // The thing you came here to do and what shapes it first, then how the
        // app behaves, then the diagnostics — which quiet themselves down to
        // one row as soon as they are green.
        PaneScaffold {
            SettingsGroup("Dictation") {
                dictationRow
                MicrophoneRow()
                ReviewBeforePasteRow()
                HUDSizeRow()
            }

            SettingsGroup("App", footer: AppAPIRow.footer) {
                launchAtLoginRow
                SettingsRow(
                    "Show in Dock",
                    caption: "Turn off to keep VoiceToText in the menu bar only.",
                    isOn: dockIconBinding
                )
                SettingsRow("Show in menu bar", caption: menuBarSubtitle) {
                    // Disabled and visibly dimmed while it can't be changed; the
                    // caption says why.
                    SettingsSwitch(title: "Show in menu bar", isOn: $presence.menuBarIconSetting)
                        .disabled(presence.isMenuBarIconLocked)
                        .opacity(presence.isMenuBarIconLocked ? 0.45 : 1)
                        .help(presence.isMenuBarIconLocked ? "Turn on Show in Dock to change this." : "")
                }
                appearanceRow
                AppAPIRow()
            }

            // `.id` forces a rebuild after a hotkey re-registration, whose
            // result `HotkeyManager` publishes imperatively.
            PermissionsGroup(items: permissionItems)
                .id(hotkeyRegistrationRefreshID)
        }
        .onAppear {
            refreshPermissions()
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .alert(
            permissionAlert?.title ?? "",
            isPresented: Binding(
                get: { permissionAlert != nil },
                set: { if !$0 { permissionAlert = nil } }
            ),
            presenting: permissionAlert
        ) { alert in
            Button(PermissionCopy.openSystemSettingsButton) { alert.openSystemSettings() }
            Button("Cancel", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    private func refreshPermissions() {
        let wasAccessibilityGranted = accessibilityGranted
        let wasListenEventGranted = listenEventGranted
        accessibilityGranted = AccessibilityPermission.isGranted
        listenEventGranted = ListenEventPermission.isGranted
        micStatus = MicPermission.status
        if accessibilityGranted && !wasAccessibilityGranted {
            retryHotkeyRegistration()
        }
        if HotkeyStore.shared.binding == .rightControlBinding,
           listenEventGranted,
           !wasListenEventGranted {
            retryHotkeyRegistration()
        }
    }

    private func retryHotkeyRegistration() {
        DictationController.shared.retryHotkeyRegistrationIfNeeded()
        MeetingController.shared.retryHotkeyRegistrationIfNeeded()
        hotkeyRegistrationRefreshID += 1
    }

    private func handleStartTap() {
        refreshPermissions()

        if MicPermission.isDenied {
            permissionAlert = .microphone
            return
        }

        if micStatus == .notDetermined {
            Task {
                let granted = await MicPermission.request()
                await MainActor.run {
                    micStatus = MicPermission.status
                    if granted {
                        dictation.toggle()
                    } else {
                        permissionAlert = .microphone
                    }
                }
            }
            return
        }

        if !accessibilityGranted {
            permissionAlert = .accessibility
            return
        }

        dictation.toggle()
    }

    /// The first row: start or stop a dictation, the shortcut that does the
    /// same from any app, and whether the dictation model is ready. The Start
    /// button is the pane's one filled control.
    private var dictationRow: some View {
        HStack(alignment: .center, spacing: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(recordingTitle)
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                dictationStatusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: handleStartTap) {
                Label {
                    Text(isRecording ? "Stop" : "Start")
                } icon: {
                    Image(systemName: isRecording ? "stop.fill" : "record.circle")
                        .foregroundStyle(isRecording ? Palette.signalLive : Palette.ink)
                        .contentTransition(.symbolEffect(.replace.downUp))
                }
            }
            .buttonTier(.secondary)
            .help(isRecording ? "Stop dictation" : "Start dictation")
        }
        .settingsRowPadding()
    }

    /// Idle: the same status line as the sidebar chip ("Ready · GPT
    /// Transcribe"). Otherwise what to do next, or the error.
    @ViewBuilder
    private var dictationStatusLine: some View {
        switch dictation.state {
        case .idle:
            // "● Ready · Press ⌥ Space in any app." The sidebar chip owns the
            // model, so it isn't repeated here.
            let status = AppStatus.current()
            HStack(spacing: Space.s2) {
                StatusDot(status.tone, size: 6)
                    .accessibilityHidden(true)
                Text("\(status.title) · Press")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                Keycap(keys: HotkeyStore.shared.binding.displayKeys, size: .small)
                Text("in any app.")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            .accessibilityElement(children: .combine)
        case .error(let message):
            Text(message)
                .typo(.caption)
                .foregroundStyle(Palette.signalWarn)
                .fixedSize(horizontal: false, vertical: true)
        case .preparing, .recording, .transcribing, .reviewing, .delivering:
            Text(recordingSubtitle)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isRecording: Bool { dictation.state == .recording }

    private var launchAtLoginRow: some View {
        SettingsRow("Launch at login", caption: "Starts VoiceToText in the background when you sign in.") {
            SettingsSwitch(title: "Launch at login", isOn: launchAtLoginBinding)
        } below: {
            if loginItem.requiresApproval {
                HStack(spacing: Space.s4) {
                    Text("Approval needed in System Settings.")
                        .typo(.caption)
                        .foregroundStyle(Palette.signalWarn)
                    Button("Open Login Items…") {
                        loginItem.openLoginItemsSettings()
                    }
                    .buttonStyle(TextLinkButtonStyle(font: Typo.caption))
                }
            } else if let err = loginItem.lastError {
                Text(err)
                    .typo(.caption)
                    .foregroundStyle(Palette.signalWarn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }

    // Dock / menu bar presence. Both rows read as "Show …" so the switches
    // share one polarity. They're coupled: turning the Dock icon off switches
    // the app to an accessory (menu-bar-only) process, so the menu bar icon is
    // forced on and locked — otherwise there'd be no way back to this window.

    /// Flipping the Dock icon changes the process's activation policy, which
    /// drops the app's active status (and, going back into the Dock, its menu
    /// bar). Re-activating so this window stays frontmost is a presentation
    /// concern, so it lives here rather than in the model — and it deliberately
    /// only activates: the window is already open, and re-opening the scene can
    /// bounce an accessory app back into the Dock.
    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { presence.showsDockIcon },
            set: {
                presence.showsDockIcon = $0
                DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
            }
        )
    }

    private var menuBarSubtitle: String {
        if presence.isMenuBarIconLocked {
            return "Always on while VoiceToText is hidden from the Dock."
        }
        return "Start dictation and reopen this window from the menu bar."
    }

    /// App-wide light/dark. `System` is the default and follows macOS, schedule
    /// included; the other two pin every window in the process — HUD, popovers
    /// and toasts included — no matter what the system does. The switch is here
    /// rather than in the token layer because nothing below `AppearanceController`
    /// needs to know: `Palette` re-resolves against whatever it pins.
    private var appearanceRow: some View {
        SettingsRow("Appearance", caption: appearanceSubtitle) {
            Picker("Appearance", selection: $appearance.mode) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var appearanceSubtitle: String {
        switch appearance.mode {
        case .system:
            return "Follows macOS, including its light/dark schedule."
        case .light:
            return "VoiceToText stays light even when macOS switches to dark."
        case .dark:
            return "VoiceToText stays dark even when macOS switches to light."
        }
    }

    // MARK: - Permissions, as data

    /// Hotkey registration, microphone and accessibility were three hand-built
    /// cards that differed only in their strings and their button's action.
    /// They are one array now; `StatusPlate` renders it.
    private var permissionItems: [StatusItem] {
        [hotkeyStatusItem, microphoneStatusItem, accessibilityStatusItem]
    }

    private var hotkeyStatusItem: StatusItem {
        let isRegistered = HotkeyManager.shared.isRegistered
        let meetingBinding = HotkeyStore.shared.meetingBinding
        // A conversation shortcut that failed to register is invisible
        // everywhere else — the app looks fine and the key just does nothing —
        // so this one row speaks for both shortcuts.
        let meetingIsRegistered = meetingBinding == nil || HotkeyManager.shared.isMeetingRegistered
        let allRegistered = isRegistered && meetingIsRegistered
        let usesStandaloneRightControl = HotkeyStore.shared.binding == .rightControlBinding
        let needsListenEventAccess = !isRegistered && usesStandaloneRightControl && !listenEventGranted

        return StatusItem(
            id: "hotkey",
            level: allRegistered ? .ready : .warning,
            title: "Global hotkey",
            message: hotkeyStatusMessage(
                isRegistered: isRegistered,
                meetingIsRegistered: meetingIsRegistered,
                meetingBinding: meetingBinding,
                usesStandaloneRightControl: usesStandaloneRightControl,
                listenEventGranted: listenEventGranted
            ),
            actionTitle: allRegistered
                ? nil
                : (needsListenEventAccess ? PermissionCopy.openSettingsShortButton : "Retry"),
            action: allRegistered ? nil : {
                if needsListenEventAccess {
                    _ = ListenEventPermission.request()
                    refreshPermissions()
                    if ListenEventPermission.isGranted {
                        retryHotkeyRegistration()
                    } else {
                        ListenEventPermission.openSystemSettings()
                    }
                } else {
                    retryHotkeyRegistration()
                    refreshPermissions()
                }
            }
        )
    }

    private var microphoneStatusItem: StatusItem {
        let granted = micStatus == .authorized
        return StatusItem(
            id: "microphone",
            level: granted ? .ready : .warning,
            title: PermissionCopy.microphoneTitle,
            message: micSubtitle,
            actionTitle: granted ? nil : micActionTitle,
            action: granted ? nil : { handleMicTap() }
        )
    }

    private var accessibilityStatusItem: StatusItem {
        StatusItem(
            id: "accessibility",
            level: accessibilityGranted ? .ready : .warning,
            title: PermissionCopy.accessibilityTitle,
            message: PermissionCopy.accessibilityPurpose,
            actionTitle: accessibilityGranted ? nil : PermissionCopy.openSettingsShortButton,
            action: accessibilityGranted ? nil : {
                AccessibilityPermission.promptForPermission()
                AccessibilityPermission.openSystemSettings()
            }
        )
    }

    private func hotkeyStatusMessage(
        isRegistered: Bool,
        meetingIsRegistered: Bool,
        meetingBinding: HotkeyBinding?,
        usesStandaloneRightControl: Bool,
        listenEventGranted: Bool
    ) -> String {
        if isRegistered && meetingIsRegistered {
            let dictation = "\(HotkeyStore.shared.binding.displayKeys.joined()) is registered and will work from any app."
            guard let meetingBinding else { return dictation }
            return "\(dictation) Conversation shortcut \(meetingBinding.displayKeys.joined()) is registered too."
        }
        // Dictation is fine, so the only thing that can have failed is the
        // conversation shortcut — usually a key another app already owns.
        if isRegistered, let meetingBinding {
            return "Conversation shortcut \(meetingBinding.displayKeys.joined()) could not be registered. Retry, or choose a different key in Shortcut."
        }
        if usesStandaloneRightControl && !listenEventGranted {
            return PermissionCopy.inputMonitoringNeeded
        }
        return "Hotkey registration failed. Retry, or check Accessibility permission."
    }

    private var micSubtitle: String {
        switch micStatus {
        case .authorized:
            return PermissionCopy.microphoneGranted
        case .notDetermined:
            return PermissionCopy.microphoneNotDetermined
        case .denied, .restricted:
            return PermissionCopy.microphoneDenied
        @unknown default:
            return "Unknown status."
        }
    }

    private var micActionTitle: String {
        switch micStatus {
        case .notDetermined: return PermissionCopy.microphoneRequestButton
        default: return PermissionCopy.openSettingsShortButton
        }
    }

    private func handleMicTap() {
        switch micStatus {
        case .notDetermined:
            Task {
                _ = await MicPermission.request()
                await MainActor.run { micStatus = MicPermission.status }
            }
        default:
            MicPermission.openSystemSettings()
        }
    }

    private var recordingTitle: String {
        switch dictation.state {
        case .idle, .error: return "Start dictation"
        case .preparing(let name): return "Loading \(name)…"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .reviewing: return "Review transcript"
        case .delivering: return "Pasting…"
        }
    }

    private var recordingSubtitle: String {
        let hk = HotkeyStore.shared.binding.displayKeys.joined()
        switch dictation.state {
        case .idle:
            return "Click Start, or use \(hk) from any app."
        case .preparing: return "Downloading or loading the active model."
        case .recording:
            // Esc only earns a mention while it actually cancels.
            let esc = HotkeyStore.shared.escapeCancelsDictation ? "press Esc to cancel, " : ""
            switch HotkeyStore.shared.mode {
            case .hold:
                return "Release the shortcut, \(esc)or click Stop."
            case .toggle:
                return "Press the shortcut again, \(esc)or click Stop."
            }
        case .transcribing: return "Waiting for transcription…"
        case .reviewing: return "Press \(hk) to paste, or Esc to cancel."
        case .delivering: return "Pasting into the app you were using."
        case .error(let message): return message
        }
    }
}

// MARK: - Permissions, self-quieting

/// The permission group, which demotes itself once it has nothing to say.
///
/// In the usual case — everything granted — it is one row: a green seal,
/// "All permissions granted", and a Show Details button that lists each
/// permission inline. Any regression re-expands it with no user action, and
/// a warning can't be collapsed out of sight.
private struct PermissionsGroup: View {
    let items: [StatusItem]

    @State private var isExpanded = false
    @Environment(\.motion) private var motion

    private var issueCount: Int { items.filter { $0.level != .ready }.count }
    private var allGranted: Bool { issueCount == 0 }
    private var showsDetail: Bool { !allGranted || isExpanded }

    var body: some View {
        SettingsGroup("Permissions") {
            summary
                .settingsRowPadding()

            if showsDetail {
                ForEach(items) { item in
                    StatusRow(item.level, title: item.title, message: item.message) {
                        if let actionTitle = item.actionTitle, let action = item.action {
                            Button(actionTitle, action: action)
                                .buttonTier(.secondary)
                        }
                    }
                    .settingsRowPadding()
                }
            }
        }
        .animation(motion.layout, value: showsDetail)
        .animation(motion.layout, value: issueCount)
        // Going green re-collapses the group, so a user who opened it to fix
        // something isn't left with the expanded diagnostics forever.
        .onChange(of: allGranted) { _, granted in
            if granted { isExpanded = false }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Image(systemName: allGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(allGranted ? Palette.signalReady : Palette.signalWarn)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(summaryTitle)
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if allGranted {
                    Text("Microphone, Accessibility and the global shortcut are working.")
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: Space.s4)

            if allGranted {
                Button(isExpanded ? "Hide Details" : "Show Details") {
                    withAnimation(motion.layout) { isExpanded.toggle() }
                }
                .buttonTier(.secondary)
                .controlSize(.small)
                .accessibilityLabel(isExpanded ? "Hide permission details" : "Show permission details")
            }
        }
    }

    private var summaryTitle: String {
        if allGranted { return "All permissions granted" }
        return issueCount == 1
            ? "1 permission needs attention"
            : "\(issueCount) permissions need attention"
    }
}
