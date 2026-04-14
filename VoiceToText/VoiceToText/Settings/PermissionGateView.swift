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
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.38, green: 0.58, blue: 1.0),
                            Color(red: 0.52, green: 0.31, blue: 0.97)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
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

                Text("status=\(statusName) raw=\(micStatus.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
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
            ReasonRow(icon: "cpu", text: "Transcription runs locally — no cloud.")
            ReasonRow(icon: "lock.fill", text: "Audio is held in memory and never stored.")
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
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", bundlePath])
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
