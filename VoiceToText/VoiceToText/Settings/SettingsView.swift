import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Bindable var registry: ModelRegistry
    @State private var selection: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general, hotkey, models, transcription, cloud, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .models: return "Models"
            case .hotkey: return "Shortcut"
            case .transcription: return "Transcription"
            case .cloud: return "Cloud"
            case .general: return "General"
            case .updates: return "Updates"
            }
        }
        var icon: String {
            switch self {
            case .models: return "waveform"
            case .hotkey: return "command"
            case .transcription: return "text.bubble"
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
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("")
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .models: ModelsPane(registry: registry, onShowCloudSettings: { selection = .cloud })
        case .hotkey: HotkeyPane()
        case .transcription: TranscriptionPane()
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

struct ModelsPane: View {
    @Bindable var registry: ModelRegistry
    var onShowCloudSettings: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    PaneHeader(
                        title: "Models",
                        subtitle: "Pick the model you want to use for dictation."
                    )
                    Spacer()
                    if registry.totalDiskUsageBytes > 0 {
                        Text("\(registry.totalDiskUsageBytes.formattedDiskSize) on disk")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(ModelCatalog.all) { model in
                        ModelRow(
                            model: model,
                            registry: registry,
                            onShowCloudSettings: onShowCloudSettings
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { registry.setActive(model.id) }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 36)
        }
        .onAppear { registry.refreshInstalledState() }
    }
}

private struct StatDots: View {
    let label: String
    let value: Int

    private static let dotCount = 10

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 3) {
                ForEach(0..<Self.dotCount, id: \.self) { i in
                    Circle()
                        .fill(i < value
                              ? Color.primary.opacity(0.65)
                              : Color.primary.opacity(0.10))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .fixedSize()
    }
}

private struct ModelRow: View {
    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry
    let onShowCloudSettings: () -> Void
    @Bindable private var keyStore = OpenAIAPIKeyStore.shared

    private var isActive: Bool { registry.activeModelId == model.id }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            providerIcon

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if isActive { activeBadge }
                }
                Text(model.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    StatDots(label: "Quality", value: model.quality)
                    StatDots(label: "Speed", value: model.speed)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                readinessControl
                if let size = displaySize {
                    Text(size)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive
                      ? Color.accentColor.opacity(0.10)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive
                              ? Color.accentColor.opacity(0.35)
                              : Color.primary.opacity(0.06))
        )
    }

    // MARK: Provider icon (left)

    private var providerIcon: some View {
        let tint: Color = model.isCloud ? .blue : .green
        let symbol = model.isCloud ? "cloud.fill" : "laptopcomputer"
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 34, height: 34)
        .help(model.isCloud
              ? "Cloud — runs on the provider's servers"
              : "Local — runs on this Mac")
    }

    private var activeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Active")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
        )
    }

    private var displaySize: String? {
        if model.isCloud { return nil }
        if case .installed(let bytes) = registry.readiness(for: model.id) {
            return bytes.formattedDiskSize
        }
        let approx = Int64(model.approxSizeMB) * 1_000_000
        return "~\(approx.formattedDiskSize)"
    }

    // MARK: Readiness controls (right)

    @ViewBuilder
    private var readinessControl: some View {
        if model.isCloud {
            cloudReadinessControl
        } else {
            localReadinessControl
        }
    }

    @ViewBuilder
    private var cloudReadinessControl: some View {
        if keyStore.hasKey {
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                onShowCloudSettings()
            } label: {
                HStack(spacing: 3) {
                    Text("Add API key")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help("Open Cloud settings to add your API key")
        }
    }

    @ViewBuilder
    private var localReadinessControl: some View {
        switch registry.readiness(for: model.id) {
        case .notInstalled:
            Button("Download") {
                Task { await registry.prepareModel(id: model.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .preparing(let fraction, let message):
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                HStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

        case .installed:
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Installed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Button {
                    registry.deleteModel(id: model.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete model from disk")
            }

        case .failed:
            Button("Retry") {
                Task { await registry.prepareModel(id: model.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
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
