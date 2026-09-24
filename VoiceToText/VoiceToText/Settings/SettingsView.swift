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
        SidebarGroup(title: "Configure", sections: [.hotkey, .models, .actions, .cloud, .updates])
    ]

    enum Section: String, CaseIterable, Identifiable {
        case general, meetings, history, hotkey, models, actions, cloud, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .models: return "Models"
            case .hotkey: return "Shortcut"
            case .actions: return "Actions"
            case .meetings: return "Conversations"
            case .history: return "History"
            case .cloud: return "Cloud"
            case .general: return "General"
            case .updates: return "Updates"
            }
        }
        var icon: String {
            switch self {
            case .models: return "waveform"
            case .hotkey: return "command"
            case .actions: return "wand.and.stars"
            case .meetings: return "person.2.wave.2"
            case .history: return "clock.arrow.circlepath"
            case .cloud: return "cloud"
            case .general: return "slider.horizontal.3"
            case .updates: return "arrow.down.circle"
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
        }
        // `.navigationTitle("")` and `.ignoresSafeArea(.container, edges: .top)`
        // are gone along with `.windowStyle(.hiddenTitleBar)` — the three were
        // one interlocking hack and only came out together. Each pane declares
        // a real `.toolbar`, and `PaneScaffold` owns the scroll-edge effect.
        .frame(minWidth: 720, minHeight: 480)
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
        case .meetings: MeetingsPane()
        case .history: HistoryPane()
        case .cloud: CloudPane()
        case .general: GeneralPane()
        case .updates: UpdatesPane()
        }
    }
}

/// The one pane title in the app: Display 26/semibold over a Body subtitle in
/// `inkMuted`. It replaces both the old 28/semibold `PaneHeader` and History's
/// 27/**bold** `LargeTitleHeader` — bold no longer exists anywhere.
struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .typo(.display)
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HotkeyPane: View {
    @Bindable private var store = HotkeyStore.shared
    @State private var capturing: CaptureTarget?
    @State private var monitor: Any?
    @State private var errorMessage: String?
    @State private var captureSession = HotkeyCaptureSession()

    /// Which of the two shortcuts a live capture belongs to. Only one can be
    /// capturing at a time — there is a single local event monitor.
    private enum CaptureTarget {
        case dictation
        case meeting
    }

    var body: some View {
        PaneScaffold {
            PaneHeader(
                title: "Shortcut",
                subtitle: "Keyboard shortcuts for dictation and conversation recording."
            )

            Plate {
                HStack(alignment: .center, spacing: Space.s6) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Dictation shortcut")
                            .typo(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(dictationSubtitle)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer()
                    if capturing == .dictation {
                        capturePrompt
                    } else {
                        KeyCap(keys: store.binding.displayKeys)
                    }
                    Button(capturing == .dictation ? "Cancel" : "Change") {
                        if capturing == .dictation {
                            stopCapture(cancelled: true)
                        } else {
                            startCapture(.dictation)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(dictationButtonShortcut)
                }
            }

            Plate {
                HStack(alignment: .center, spacing: Space.s6) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Recording mode")
                            .typo(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(modeSubtitle)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer()
                    Picker("Recording mode", selection: modeBinding) {
                        ForEach(RecordingShortcutMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }

            Plate {
                HStack(alignment: .center, spacing: Space.s6) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Conversation shortcut")
                            .typo(.headline)
                            .foregroundStyle(Palette.ink)
                        Text(meetingSubtitle)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer()
                    if capturing == .meeting {
                        capturePrompt
                    } else if let meetingBinding = store.meetingBinding {
                        KeyCap(keys: meetingBinding.displayKeys)
                    } else {
                        Text("Not set")
                            .typo(.captionMedium)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Button(meetingButtonTitle) {
                        if capturing == .meeting {
                            stopCapture(cancelled: true)
                        } else {
                            startCapture(.meeting)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(capturing == .meeting ? .cancelAction : nil)
                    if store.meetingBinding != nil && capturing != .meeting {
                        Button("Remove") { store.clearMeetingBinding() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            Plate {
                SettingsToggleRow(
                    title: "Esc cancels dictation",
                    subtitle: "While recording or transcribing, Esc discards the dictation instead of reaching the app you're in. Turn off if you often press Esc in other apps while dictating.",
                    isOn: escapeCancelsDictationBinding
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .typo(.caption)
                    .foregroundStyle(Palette.signalWarn)
            }

            HStack(spacing: Space.s5) {
                if store.binding != .defaultBinding {
                    Button("Reset to ⌥Space") { store.resetToDefault() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Text("Choose any key with at least one modifier (⌘ ⌥ ⌃ ⇧) or a function key. Right Control on its own works for dictation.")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .onDisappear { stopCapture(cancelled: true) }
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

    private var dictationSubtitle: String {
        if capturing == .dictation { return "Press a key combination, or Esc to cancel." }
        return "Used for hold-to-record or press-to-toggle dictation."
    }

    private var meetingSubtitle: String {
        if capturing == .meeting { return "Press a key combination, or Esc to cancel." }
        return "Starts or stops a conversation recording from any app."
    }

    private var meetingButtonTitle: String {
        if capturing == .meeting { return "Cancel" }
        return store.meetingBinding == nil ? "Set" : "Change"
    }

    /// Return cancels the live capture and otherwise confirms the dictation
    /// change — but only while nothing is capturing, so the two Cancel buttons
    /// can never both claim Esc or Return.
    private var dictationButtonShortcut: KeyboardShortcut? {
        if capturing == .dictation { return .cancelAction }
        return capturing == nil ? .defaultAction : nil
    }

    private var modeSubtitle: String {
        "Hold records while the shortcut is down; toggle starts and stops on each press."
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

    /// Each capture refuses what the other owns: the conversation shortcut can't
    /// take standalone Right Control (dictation's event tap owns it), and
    /// neither can take the key already bound to the other.
    private func makeCaptureSession(for target: CaptureTarget) -> HotkeyCaptureSession {
        switch target {
        case .dictation:
            let reserved = store.meetingBinding.map {
                [HotkeyCaptureSession.ReservedBinding(
                    binding: $0,
                    message: "That shortcut is already used for conversation recording."
                )]
            }
            return HotkeyCaptureSession(
                allowsStandaloneModifier: true,
                reservedBindings: reserved ?? []
            )
        case .meeting:
            return HotkeyCaptureSession(
                allowsStandaloneModifier: false,
                reservedBindings: [
                    HotkeyCaptureSession.ReservedBinding(
                        binding: store.binding,
                        message: "That shortcut is already used for dictation."
                    )
                ]
            )
        }
    }

    private func handle(event: NSEvent) {
        guard let target = capturing else { return }
        switch captureSession.handle(event: event) {
        case .ignored, .pendingStandaloneModifier:
            break
        case .cancelled:
            stopCapture(cancelled: true)
        case .captured(let candidate):
            errorMessage = nil
            switch target {
            case .dictation: store.update(to: candidate)
            case .meeting: store.updateMeetingBinding(to: candidate)
            }
            stopCapture(cancelled: false)
        case .rejected(let message):
            errorMessage = message
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

/// Internal, not private: the Conversations pane shows the conversation
/// shortcut's keys with the same caps.
struct KeyCap: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .typo(.mono)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Palette.wellFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Palette.hairline)
                    )
            }
        }
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
        // Three blocks, in the order the user needs them: the thing you came
        // here to do, the preferences that shape it, then the diagnostics —
        // which quiet themselves down to one line as soon as they are green.
        PaneScaffold {
            PaneHeader(
                title: "General",
                subtitle: "Dictation controls, permissions, and hotkey status."
            )

            dictationCard

            PaneSection("Preferences") {
                ReviewBeforePasteCard()
                launchAtLoginCard
                presenceCard
                appearanceCard
            }

            PaneSection("Permissions") {
                // The three copy-pasted permission cards, collapsed into
                // one self-quieting group. `.id` forces a rebuild after a
                // hotkey re-registration, whose result `HotkeyManager`
                // publishes imperatively.
                PermissionsGroup(items: permissionItems)
                    .id(hotkeyRegistrationRefreshID)
            }
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

    /// The hero block: the one thing this pane is for. A 40pt tinted glyph, the
    /// live state as a title, and the record affordance — the only control in
    /// the window allowed to be `.borderedProminent`.
    @ViewBuilder
    private var dictationCard: some View {
        Plate {
            HStack(spacing: Space.s5) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(heroTint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(heroTint.opacity(0.12)))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(recordingTitle)
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(recordingSubtitle)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s5)
                Button(action: handleStartTap) {
                    Label(
                        isRecording ? "Stop" : "Start",
                        systemImage: isRecording ? "stop.fill" : "record.circle"
                    )
                    .contentTransition(.symbolEffect(.replace.downUp))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                // Flat tints only. The brand gradient never sits behind a label:
                // white on #6194FF is 2.92:1, below even the large-text floor.
                .tint(heroTint)
            }
        }
    }

    private var isRecording: Bool { dictation.state == .recording }

    /// One tint for the hero glyph and the record button, so they can never
    /// disagree about what state the app is in.
    private var heroTint: Color { isRecording ? Palette.signalLive : Palette.accent }

    @ViewBuilder
    private var launchAtLoginCard: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s4) {
                SettingsToggleRow(
                    title: "Launch at login",
                    subtitle: launchAtLoginSubtitle,
                    isOn: launchAtLoginBinding
                )

                if loginItem.requiresApproval {
                    HStack(spacing: Space.s4) {
                        Text("Approval needed in System Settings.")
                            .typo(.caption)
                            .foregroundStyle(Palette.signalWarn)
                        Button("Open Login Items…") {
                            loginItem.openLoginItemsSettings()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                } else if let err = loginItem.lastError {
                    Text(err)
                        .typo(.caption)
                        .foregroundStyle(Palette.signalWarn)
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }

    private var launchAtLoginSubtitle: String {
        if loginItem.isEnabled {
            return "VoiceToText will start in the background when you sign in."
        }
        return "Start VoiceToText automatically in the background when you sign in."
    }

    /// Dock / menu bar presence. Both rows read as "Show …" so the switches
    /// share one polarity. They're coupled: turning the Dock icon off switches
    /// the app to an accessory (menu-bar-only) process, so the menu bar icon is
    /// forced on and locked — otherwise there'd be no way back to this window.
    @ViewBuilder
    private var presenceCard: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s5) {
                SettingsToggleRow(
                    title: "Show in Dock",
                    subtitle: "Turn off to keep VoiceToText out of the Dock and the app switcher. It keeps running in the menu bar, and your shortcut still works everywhere.",
                    isOn: dockIconBinding
                )

                PlateDivider(leadingInset: 0)

                SettingsToggleRow(
                    title: "Show in menu bar",
                    subtitle: menuBarSubtitle,
                    isOn: $presence.menuBarIconSetting,
                    isLocked: presence.isMenuBarIconLocked
                )
            }
        }
    }

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
            return "Required while VoiceToText is hidden from the Dock — it's how you reopen this window."
        }
        return "Adds a VoiceToText icon to the menu bar for starting dictation and reopening this window."
    }

    /// App-wide light/dark. `System` is the default and follows macOS, schedule
    /// included; the other two pin every window in the process — HUD, popovers
    /// and toasts included — no matter what the system does. The switch is here
    /// rather than in the token layer because nothing below `AppearanceController`
    /// needs to know: `Palette` re-resolves against whatever it pins.
    @ViewBuilder
    private var appearanceCard: some View {
        Plate {
            HStack(alignment: .center, spacing: Space.s6) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Appearance")
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(appearanceSubtitle)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s6)
                Picker("Appearance", selection: $appearance.mode) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
    }

    private var appearanceSubtitle: String {
        switch appearance.mode {
        case .system:
            return "Follows macOS, including the automatic light/dark schedule."
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
        case .idle, .error: return "Start recording"
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
/// Diagnostics were masquerading as settings: three full-height cards, always
/// expanded, occupying roughly half of GeneralPane in the 99% case where every
/// one of them is green. This group collapses on `Motion.layout` into a single
/// "All set" line in `signalReady` with a disclosure to re-open it, and any
/// regression re-expands it inline — turning the summary `signalWarn` with a
/// count — with no user action.
///
/// It stays IN THE PANE rather than becoming a toolbar chip: the direction's own
/// rule is zero custom toolbar backgrounds, and a chip is the first thing the
/// system drops when the toolbar condenses — which is exactly when a warning
/// most needs to be visible.
private struct PermissionsGroup: View {
    let items: [StatusItem]

    @State private var isExpanded = false
    @Environment(\.motion) private var motion

    private var issueCount: Int { items.filter { $0.level != .ready }.count }
    private var allGranted: Bool { issueCount == 0 }
    /// A regression forces the detail open — there is no way to collapse a
    /// warning out of sight.
    private var showsDetail: Bool { !allGranted || isExpanded }

    var body: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s5) {
                summary

                if showsDetail {
                    ForEach(items) { item in
                        PlateDivider(leadingInset: 0)
                        StatusRow(item.level, title: item.title, message: item.message) {
                            if let actionTitle = item.actionTitle, let action = item.action {
                                Button(actionTitle, action: action)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
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

    @ViewBuilder
    private var summary: some View {
        HStack(spacing: Space.s4) {
            Image(systemName: allGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(allGranted ? Palette.signalReady : Palette.signalWarn)
                .accessibilityHidden(true)

            Text(summaryText)
                .typo(.headline)
                .foregroundStyle(allGranted ? Palette.signalReady : Palette.ink)
                .contentTransition(.numericText())

            Spacer(minLength: Space.s4)

            if allGranted {
                Button {
                    withAnimation(motion.layout) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(disclosureLabel)
                .accessibilityLabel(disclosureLabel)
            }
        }
    }

    private var summaryText: String {
        if allGranted { return "All set" }
        return issueCount == 1
            ? "1 permission needs attention"
            : "\(issueCount) permissions need attention"
    }

    private var disclosureLabel: String {
        isExpanded ? "Hide permission details" : "Show permission details"
    }
}
