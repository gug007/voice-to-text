import AVFoundation
import Combine
import SwiftUI

struct PermissionGateView: View {
    @State private var micStatus = MicPermission.status

    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                // Brand use #1 of 2. The literal this replaces was exactly the
                // light-mode token (#6194FF → #854FF7) with no dark variant, so
                // the tile stayed light-mode blue on a dark desktop while the
                // sidebar mark tracked the appearance.
                .background(Palette.brandGradient)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Grant microphone access")
                .font(.system(size: 22, weight: .semibold))

            reasons

            VStack(spacing: 8) {
                Button(action: handlePrimaryTap) {
                    Text(primaryTitle)
                        .frame(minWidth: 200)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Already allowed? Relaunch", action: relaunch)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                #if DEBUG
                Text("status=\(statusName) raw=\(micStatus.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.top, 4)
                #endif
            }

            Spacer()
        }
        .task {
            if micStatus == .notDetermined {
                _ = await MicPermission.request()
                micStatus = MicPermission.status
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(refreshTimer) { _ in micStatus = MicPermission.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = MicPermission.status
        }
    }

    @ViewBuilder
    private var reasons: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReasonRow(icon: "waveform", text: "To hear what you say while recording.")
            ReasonRow(icon: "cpu", text: "The default model transcribes locally on your Mac.")
            ReasonRow(icon: "lock.fill", text: "History saves audio locally when enabled; you can turn it off.")
        }
        .frame(maxWidth: 360)
    }

    private var primaryTitle: String {
        switch micStatus {
        case .notDetermined: return "Allow Access"
        default: return "Open System Settings"
        }
    }

    private var statusName: String {
        switch micStatus {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
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

private struct ReasonRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
