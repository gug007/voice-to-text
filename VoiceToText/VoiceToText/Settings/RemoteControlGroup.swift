import SwiftUI

/// The Conversations pane's "iPhone" group: the switch for
/// `RemoteControlController`, the Tailscale account it signs in with, and
/// whether the phone has been here. The rows below the switch only exist
/// while it is on, because nothing below it runs while it is off.
struct RemoteControlGroup: View {
    @Bindable private var remote = RemoteControlController.shared
    @Environment(\.motion) private var motion

    var body: some View {
        SettingsGroup("iPhone", footer: footer) {
            SettingsRow(
                "Control from iPhone",
                caption: "Start and stop conversations, read them and play them back from the iPhone app.",
                isOn: $remote.isEnabled
            )
            if remote.isEnabled {
                SettingsRow(
                    "Let iPhone listen live",
                    caption: "Hear the conversation on your iPhone while this Mac records it. The Mac shows when an iPhone is listening.",
                    isOn: $remote.liveListenEnabled
                )
                accountRow
                if remote.tailnet.state.isRunning {
                    connectionRow
                }
            }
        }
        .animation(motion.layout, value: remote.isEnabled)
        .animation(motion.layout, value: remote.tailnet.state)
        .animation(motion.layout, value: remote.liveListeners)
    }

    private var footer: String {
        remote.isEnabled
            ? "Sign in to the same Tailscale account in Voice to Text on your iPhone. Only devices on that account can connect."
            : "Connects through Tailscale, built into the app. Nothing connects until you turn this on."
    }

    @ViewBuilder
    private var accountRow: some View {
        switch remote.tailnet.state {
        case .off, .starting:
            SettingsRow("Tailscale", caption: "Starting…") {
                ProgressView().controlSize(.small).accessibilityLabel("Starting Tailscale")
            }
        case .connecting:
            SettingsRow("Tailscale", caption: "Connecting…") {
                ProgressView().controlSize(.small).accessibilityLabel("Connecting to Tailscale")
            }
        case .signedOut:
            SettingsRow("Tailscale", caption: "Sign in with the account your iPhone uses.") {
                Button("Sign in with Tailscale") { remote.signIn() }
                    .buttonTier(.secondary)
            }
        case .needsLogin:
            SettingsRow("Tailscale", caption: "Finish signing in in your browser.") {
                HStack(spacing: Space.s4) {
                    Button("Cancel") { remote.cancelSignIn() }
                        .buttonTier(.tertiary)
                    Button("Open Sign-In Page") { remote.openSignInPage() }
                        .buttonTier(.secondary)
                }
            }
        case .running(let account):
            SettingsRow("Signed in as \(account)", caption: "Tailscale") {
                Button("Sign Out") { remote.signOut() }
                    .buttonTier(.secondary)
            }
        case .failed(let message):
            StatusRow(.error, title: "Tailscale", message: message) {
                Button("Try Again") { remote.retry() }
                    .buttonTier(.secondary)
            }
            .settingsRowPadding()
        }
    }

    @ViewBuilder
    private var connectionRow: some View {
        if let error = remote.listenError {
            StatusRow(.error, title: "Can't accept connections", message: error)
                .settingsRowPadding()
        } else if remote.liveListeners > 0 {
            StatusRow(
                icon: "iphone.radiowaves.left.and.right",
                tint: Palette.signalLive,
                title: remote.liveListeners == 1 ? "iPhone listening" : "\(remote.liveListeners) iPhones listening",
                message: "Hearing this conversation live."
            )
            .settingsRowPadding()
        } else if let client = remote.lastClient {
            StatusRow(
                icon: "iphone",
                tint: Palette.signalReady,
                title: "Last connected: \(client.name)",
                message: client.at.formatted(.relative(presentation: .named))
            )
            .settingsRowPadding()
        } else {
            StatusRow(
                icon: "iphone",
                tint: Palette.inkMuted,
                title: "Waiting for your iPhone",
                message: "Open Voice to Text on the iPhone and sign in there too."
            )
            .settingsRowPadding()
        }
    }
}
