import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var registry: ModelRegistry
    @State private var selection: Section = .models

    enum Section: String, CaseIterable, Identifiable {
        case models, hotkey, transcription, general
        var id: String { rawValue }
        var title: String {
            switch self {
            case .models: return "Models"
            case .hotkey: return "Shortcut"
            case .transcription: return "Transcription"
            case .general: return "General"
            }
        }
        var icon: String {
            switch self {
            case .models: return "waveform"
            case .hotkey: return "command"
            case .transcription: return "text.bubble"
            case .general: return "slider.horizontal.3"
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
        case .models: ModelsPane(registry: registry)
        case .hotkey: HotkeyPane()
        case .transcription: TranscriptionPane()
        case .general: GeneralPane()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PaneHeader(
                        title: "Models",
                        subtitle: "Download a model to your Mac and pick one for dictation."
                    )
                    Spacer()
                    if registry.totalDiskUsageBytes > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Disk used")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            Text(registry.totalDiskUsageBytes.formattedDiskSize)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                        ModelRow(model: model, registry: registry)
                            .contentShape(Rectangle())
                            .onTapGesture { registry.setActive(model.id) }

                        if index < ModelCatalog.all.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
            }
            .padding(32)
        }
        .onAppear { registry.refreshInstalledState() }
    }
}

private struct ModelRow: View {
    let model: ModelDescriptor
    @Bindable var registry: ModelRegistry

    private var isActive: Bool { registry.activeModelId == model.id }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .medium))
                    if model.recommended {
                        Text("Recommended")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
                Text(model.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    metaLabel(displaySize)
                    Text("·").foregroundStyle(.tertiary)
                    metaLabel(model.languages)
                    Text("·").foregroundStyle(.tertiary)
                    metaLabel(model.backend == .fluidAudio ? "FluidAudio" : "WhisperKit")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }

            Spacer()

            readinessControl
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
    }

    private var displaySize: String {
        if case .installed(let bytes) = registry.readiness(for: model.id) {
            return bytes.formattedDiskSize
        }
        return "~\(formattedSize(model.approxSizeMB))"
    }

    private func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }

    @ViewBuilder
    private var readinessControl: some View {
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
                    .frame(width: 140)
                HStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

        case .installed:
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                    Text("Installed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    registry.deleteModel(id: model.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "Shortcut",
                    subtitle: "The keyboard shortcut to start and stop dictation."
                )

                RowCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Toggle recording")
                                .font(.system(size: 14, weight: .medium))
                            Text("Press once to start, press again to stop.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyCap(keys: ["⌥", "Space"])
                    }
                    .padding(18)
                }

                Text("Rebinding will be available in a future update.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(32)
        }
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
    @State private var micStatus = MicPermission.status
    @State private var permissionAlert: PermissionAlert?
    @Bindable private var dictation = DictationController.shared

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

                statusCard

                microphoneCard

                accessibilityCard
            }
            .padding(32)
        }
        .onAppear {
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
                    message: Text("VoiceToText needs Accessibility permission to type transcribed text into other apps. Open System Settings → Privacy & Security → Accessibility and enable VoiceToText."),
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
        accessibilityGranted = AccessibilityPermission.isGranted
        micStatus = MicPermission.status
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
    private var statusCard: some View {
        let isRegistered = HotkeyManager.shared.isRegistered
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isRegistered ? .green : .orange)
                        Text("Global hotkey")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(isRegistered
                         ? "⌥Space is registered and will work from any app."
                         : "Hotkey registration failed. See logs for details.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
        }
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
                    Text("Required to type transcribed text into other apps.")
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
        }
    }

    private var recordingSubtitle: String {
        switch dictation.state {
        case .idle: return "Click Start, or press ⌥Space from any app."
        case .preparing: return "Downloading or loading the active model."
        case .recording: return "Click Stop, or press ⌥Space, when you're done speaking."
        case .transcribing: return "Waiting for transcription…"
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
