import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Bindable var registry: ModelRegistry
    @State private var selection: Section = .general

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
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    // macOS 26's floating sidebar panel clips the row's leading
                    // icon gutter (known NavigationSplitView issue; safe-area
                    // padding shifts the panel, not the rows). Indent the row
                    // content itself back into the visible panel.
                    .padding(.leading, sidebarContentInset)
                    .tag(section)
            }
            .listStyle(.sidebar)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // With the transparent title bar (hiddenTitleBar), pull the pane
                // up so its header sits at the very top of the content area. The
                // detail has no window controls, so nothing is obscured.
                .ignoresSafeArea(.container, edges: .top)
        }
        .navigationTitle("")
        .frame(minWidth: 880, minHeight: 560)
    }

    private var sidebarContentInset: CGFloat {
        if #available(macOS 26.0, *) { return 24 }
        return 0
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

struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

struct HotkeyPane: View {
    @Bindable private var store = HotkeyStore.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?
    @State private var captureSession = HotkeyCaptureSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "Shortcut",
                    subtitle: "The keyboard shortcut to start and stop dictation."
                )

                RowCard {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Recording shortcut")
                                .font(.system(size: 14, weight: .medium))
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isRecording {
                            Text("Press a shortcut…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                )
                        } else {
                            KeyCap(keys: store.binding.displayKeys)
                        }
                        Button(isRecording ? "Cancel" : "Change") {
                            if isRecording { stopRecording(cancelled: true) } else { startRecording() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(isRecording ? .cancelAction : .defaultAction)
                    }
                    .padding(18)
                }

                RowCard {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Recording mode")
                                .font(.system(size: 14, weight: .medium))
                            Text(modeSubtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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
                    .padding(18)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 12) {
                    if store.binding != .defaultBinding {
                        Button("Reset to ⌥Space") { store.resetToDefault() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text("Choose any key with at least one modifier (⌘ ⌥ ⌃ ⇧), a function key, or Right Control.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(32)
        }
        .onDisappear { stopRecording(cancelled: true) }
    }

    private var subtitle: String {
        if isRecording { return "Press a key combination, or Esc to cancel." }
        return "Used for hold-to-record or press-to-toggle dictation."
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

    private func startRecording() {
        errorMessage = nil
        captureSession.reset()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event: event)
            return nil
        }
    }

    private func handle(event: NSEvent) {
        switch captureSession.handle(event: event) {
        case .ignored, .pendingStandaloneModifier:
            break
        case .cancelled:
            stopRecording(cancelled: true)
        case .captured(let candidate):
            errorMessage = nil
            store.update(to: candidate)
            stopRecording(cancelled: false)
        case .rejected(let message):
            errorMessage = message
        }
    }

    private func stopRecording(cancelled: Bool) {
        isRecording = false
        captureSession.reset()
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if cancelled { errorMessage = nil }
    }
}

private struct KeyCap: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.primary.opacity(0.1))
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

    enum PermissionAlert: Identifiable {
        case microphone
        case accessibility

        var id: String {
            switch self {
            case .microphone: return "mic"
            case .accessibility: return "a11y"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "General",
                    subtitle: "Dictation controls, permissions, and hotkey status."
                )

                dictationCard

                ReviewBeforePasteCard()

                launchAtLoginCard

                statusCard

                microphoneCard

                accessibilityCard
            }
            .padding(32)
        }
        .onAppear {
            refreshPermissions()
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .alert(item: $permissionAlert) { alert in
            switch alert {
            case .microphone:
                return Alert(
                    title: Text("Microphone Access Required"),
                    message: Text("VoiceToText needs permission to record audio for transcription. Open System Settings → Privacy & Security → Microphone and enable VoiceToText."),
                    primaryButton: .default(Text("Open System Settings")) {
                        MicPermission.openSystemSettings()
                    },
                    secondaryButton: .cancel()
                )
            case .accessibility:
                return Alert(
                    title: Text("Accessibility Access Required"),
                    message: Text("VoiceToText needs Accessibility permission for global shortcuts, Esc cancel, and typing text into other apps. Open System Settings → Privacy & Security → Accessibility and enable VoiceToText."),
                    primaryButton: .default(Text("Open System Settings")) {
                        AccessibilityPermission.promptForPermission()
                        AccessibilityPermission.openSystemSettings()
                    },
                    secondaryButton: .cancel()
                )
            }
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

    @ViewBuilder
    private var dictationCard: some View {
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recordingTitle)
                        .font(.system(size: 14, weight: .medium))
                    Text(recordingSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: handleStartTap) {
                    Label(
                        dictation.state == .recording ? "Stop" : "Start",
                        systemImage: dictation.state == .recording ? "stop.fill" : "record.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(dictation.state == .recording ? .red : .accentColor)
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var launchAtLoginCard: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Launch at login")
                            .font(.system(size: 14, weight: .medium))
                        Text(launchAtLoginSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if loginItem.requiresApproval {
                    HStack(spacing: 8) {
                        Text("Approval needed in System Settings.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Button("Open Login Items…") {
                            loginItem.openLoginItemsSettings()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                } else if let err = loginItem.lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(18)
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

    @ViewBuilder
    private var statusCard: some View {
        let isRegistered = HotkeyManager.shared.isRegistered
        let usesStandaloneRightControl = HotkeyStore.shared.binding == .rightControlBinding
        let needsListenEventAccess = usesStandaloneRightControl && !listenEventGranted
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isRegistered ? .green : .orange)
                        Text("Global hotkey")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(hotkeyStatusMessage(
                        isRegistered: isRegistered,
                        usesStandaloneRightControl: usesStandaloneRightControl,
                        listenEventGranted: listenEventGranted
                    ))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isRegistered {
                    Button(needsListenEventAccess ? "Open Settings…" : "Retry") {
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(18)
        }
        .id(hotkeyRegistrationRefreshID)
    }

    private func hotkeyStatusMessage(
        isRegistered: Bool,
        usesStandaloneRightControl: Bool,
        listenEventGranted: Bool
    ) -> String {
        if isRegistered {
            return "\(HotkeyStore.shared.binding.displayKeys.joined()) is registered and will work from any app."
        }
        if usesStandaloneRightControl && !listenEventGranted {
            return "Right Control needs Input Monitoring permission. Enable VoiceToText in System Settings, then return here."
        }
        return "Hotkey registration failed. Retry, or check Accessibility permission."
    }

    @ViewBuilder
    private var microphoneCard: some View {
        let granted = micStatus == .authorized
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(granted ? .green : .orange)
                        Text("Microphone")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(micSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !granted {
                    Button(micActionTitle) {
                        handleMicTap()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var accessibilityCard: some View {
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text("Accessibility")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text("Required for global shortcuts, Esc cancel, and typing text into other apps.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !accessibilityGranted {
                    Button("Open Settings…") {
                        AccessibilityPermission.promptForPermission()
                        AccessibilityPermission.openSystemSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(18)
        }
    }

    private var micSubtitle: String {
        switch micStatus {
        case .authorized:
            return "VoiceToText can record from your microphone."
        case .notDetermined:
            return "Click Request to grant microphone access."
        case .denied, .restricted:
            return "Denied. Open System Settings → Privacy → Microphone and enable VoiceToText."
        @unknown default:
            return "Unknown status."
        }
    }

    private var micActionTitle: String {
        switch micStatus {
        case .notDetermined: return "Request…"
        default: return "Open Settings…"
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
        }
    }

    private var recordingSubtitle: String {
        let hk = HotkeyStore.shared.binding.displayKeys.joined()
        switch dictation.state {
        case .idle:
            return "Click Start, or use \(hk) from any app."
        case .preparing: return "Downloading or loading the active model."
        case .recording:
            switch HotkeyStore.shared.mode {
            case .hold:
                return "Release the shortcut, press Esc to cancel, or click Stop."
            case .toggle:
                return "Press the shortcut again, press Esc to cancel, or click Stop."
            }
        case .transcribing: return "Waiting for transcription…"
        case .reviewing: return "Press \(hk) to paste, or Esc to cancel."
        case .error(let message): return message
        }
    }
}

struct RowCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

