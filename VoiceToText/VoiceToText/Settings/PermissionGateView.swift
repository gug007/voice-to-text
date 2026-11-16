import AVFoundation
import Combine
import SwiftUI

/// The first-run screen, shown until the microphone is allowed. It says where
/// this step sits in setup, why the microphone is needed, and — once access
/// was refused — sends the user to System Settings instead.
struct PermissionGateView: View {
    @State private var micStatus = MicPermission.status
    @State private var accessibilityGranted = Self.isAccessibilityGranted

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Centred, then lifted 24pt: optical centre sits a little above the
        // geometric one.
        VStack(spacing: 0) {
            Spacer(minLength: Space.s7)
            content
            Spacer(minLength: Space.s7)
            Color.clear.frame(height: Space.s8 + Space.s6)
        }
        .padding(.horizontal, Space.s7)
        .task {
            if micStatus == .notDetermined {
                _ = await MicPermission.request()
                micStatus = MicPermission.status
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .onReceive(refreshTimer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var content: some View {
        VStack(spacing: Space.s7) {
            appIcon

            VStack(spacing: Space.s3) {
                if showsSteps {
                    Text("Step 1 of 2")
                        .typo(.captionMedium)
                        .foregroundStyle(Palette.inkMuted)
                }
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(showsSteps ? "Step 1 of 2. \(title)" : title)
                if isDenied {
                    Text("Turn on VoiceToText in System Settings → Privacy & Security → Microphone, then come back.")
                        .typo(.body)
                        .foregroundStyle(Palette.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: Space.s5) {
                ReasonRow(icon: "waveform", text: "Listens only while you're recording.")
                ReasonRow(icon: "laptopcomputer", text: "The default model transcribes locally on your Mac.")
                ReasonRow(icon: "internaldrive", text: "History keeps recordings on this Mac. You can turn it off.")
            }
            .fixedSize()

            VStack(spacing: Space.s4) {
                Button(action: handlePrimaryTap) {
                    Text(isDenied ? "Open System Settings…" : "Allow Microphone Access")
                        .frame(minWidth: 200)
                }
                .buttonTier(.primary)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if showsSteps {
                    Text("Next: allow Accessibility, so text can be pasted.")
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }

            // The escape hatch, quieter than the guidance above. An action,
            // so a small bordered button rather than a link.
            HStack(spacing: Space.s3) {
                Text("Already allowed?")
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                Button("Relaunch VoiceToText", action: relaunch)
                    .buttonTier(.secondary)
                    .controlSize(.small)
                    .help("Quits and reopens VoiceToText so it sees the new permission.")
                    .accessibilityHint("Quits and reopens the app")
            }

            #if DEBUG
            Text("status=\(statusName) raw=\(micStatus.rawValue)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.inkFaint)
            #endif
        }
    }

    /// The real icon. In dark mode its black tile would melt into the
    /// window, so a hairline rim traced from the icon's own shape outlines it;
    /// in light mode a soft shadow lifts it instead.
    private var appIcon: some View {
        let isDark = colorScheme == .dark
        return Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 80, height: 80)
            .shadow(color: isDark ? Color.white.opacity(0.35) : .clear, radius: 0.5)
            .shadow(color: Color.black.opacity(isDark ? 0 : 0.14), radius: 6, y: 2)
            .accessibilityHidden(true)
    }

    private var title: String {
        isDenied ? "Microphone access is off" : "VoiceToText needs your microphone"
    }

    private var isDenied: Bool {
        micStatus == .denied || micStatus == .restricted
    }

    /// Setup is the microphone, then Accessibility (paste and the global
    /// shortcut). Nothing to count when Accessibility is already allowed.
    private var showsSteps: Bool { !accessibilityGranted }

    private var statusName: String {
        switch micStatus {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    private func refresh() {
        micStatus = MicPermission.status
        accessibilityGranted = Self.isAccessibilityGranted
    }

    private static var isAccessibilityGranted: Bool {
        return AccessibilityPermission.isGranted
    }

    private func handlePrimaryTap() {
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

    private func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let script = #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; /usr/bin/open "$2""#
        Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", script, "relaunch", pid, bundlePath])
        NSApp.terminate(nil)
    }
}

/// An icon and a one-line sentence, read by VoiceOver as the sentence alone.
private struct ReasonRow: View {
    let icon: String
    let text: String

    var body: some View {
        // Every line is one line now, so icon and text centre on each other.
        HStack(alignment: .center, spacing: Space.s5) {
            // One weight, one fixed box, so glyphs of different widths still
            // make a straight column.
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(text)
                .typo(.body)
                .foregroundStyle(Palette.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
