import AVFoundation
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Bindable var registry: ModelRegistry
    @State private var selection: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case models, hotkey, transcription, general, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .models: return "Models"
            case .hotkey: return "Shortcut"
            case .transcription: return "Transcription"
            case .general: return "General"
            case .updates: return "Updates"
            }
        }
        var icon: String {
            switch self {
            case .models: return "waveform"
            case .hotkey: return "command"
            case .transcription: return "text.bubble"
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
        case .models: ModelsPane(registry: registry)
        case .hotkey: HotkeyPane()
        case .transcription: TranscriptionPane()
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

private struct StatBar: View {
    let label: String
    let value: Int

    private static let segmentCount = 10

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 2) {
                ForEach(0..<Self.segmentCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(i < value
                              ? Color.primary.opacity(0.72)
                              : Color.primary.opacity(0.12))
                        .frame(width: 7, height: 4)
                }
            }
        }
        .fixedSize()
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

            VStack(alignment: .leading, spacing: 6) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(model.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    StatBar(label: "Quality", value: model.quality)
                    StatBar(label: "Speed", value: model.speed)
                }
                .padding(.top, 2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                readinessControl
                Text(displaySize)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var displaySize: String {
        if case .installed(let bytes) = registry.readiness(for: model.id) {
            return bytes.formattedDiskSize
        }
        let approx = Int64(model.approxSizeMB) * 1_000_000
        return "~\(approx.formattedDiskSize)"
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
    @Bindable private var store = HotkeyStore.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

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
                            Text("Toggle recording")
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
                    Text("Choose any key with at least one modifier (⌘ ⌥ ⌃ ⇧), or a function key.")
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
        return "Press once to start, press again to stop."
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event: event)
            return nil
        }
    }

    private func handle(event: NSEvent) {
        // Esc without modifiers cancels
        let pureModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && pureModifiers.isEmpty {
            stopRecording(cancelled: true)
            return
        }

        let candidate = HotkeyBinding.fromEvent(event)

        // Allow: any combo with at least one modifier, or bare F1–F20.
        guard candidate.modifiers != 0 || candidate.isFunctionKey else {
            errorMessage = "Add at least one modifier (⌘ ⌥ ⌃ ⇧), or pick a function key."
            return
        }

        store.update(to: candidate)
        stopRecording(cancelled: false)
    }

    private func stopRecording(cancelled: Bool) {
        isRecording = false
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
                         ? "\(HotkeyStore.shared.binding.displayKeys.joined()) is registered and will work from any app."
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
        case .reviewing: return "Review transcript"
        }
    }

    private var recordingSubtitle: String {
        let hk = HotkeyStore.shared.binding.displayKeys.joined()
        switch dictation.state {
        case .idle: return "Click Start, or press \(hk) from any app."
        case .preparing: return "Downloading or loading the active model."
        case .recording: return "Click Stop, or press \(hk), when you're done speaking."
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
