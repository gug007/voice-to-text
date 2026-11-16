import AppKit
import SwiftUI

struct UpdatesPane: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        PaneScaffold {
            SettingsGroup {
                versionRow

                if case .error(let message) = updater.status {
                    StatusRow(.warning, title: "Update failed", message: message) {
                        ExternalLink("Download manually", destination: AppUpdater.releasesPageURL)
                    }
                    .settingsRowPadding()
                }

                if case .available(let version, _, let notes) = updater.status, !notes.isEmpty {
                    notesRow(version: version, notes: notes)
                }

                SettingsRow(
                    "Check for updates automatically",
                    caption: "At launch and once a day. VoiceToText asks before installing.",
                    isOn: $updater.automaticallyChecksForUpdates
                )

                SettingsRow("Release notes", caption: "What changed in each version.") {
                    ExternalLink("View on GitHub", destination: AppUpdater.releasesPageURL)
                }
            }
        }
        .onChange(of: updater.status) { old, new in
            // A check's result lands in the status line; say it aloud too.
            guard old == .checking, new != .checking else { return }
            AccessibilityNotification.Announcement(statusLine(now: .now).text).post()
        }
    }

    // MARK: - Version row

    private static let iconSize: CGFloat = 40

    /// The installed version, its update state, and the one action that
    /// state calls for.
    private var versionRow: some View {
        HStack(alignment: .center, spacing: Space.s5) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                // A rim so a dark icon keeps its silhouette on the dark plate.
                .shadow(color: Palette.iconEdge, radius: 1, x: 0, y: 0.5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text("VoiceToText \(updater.currentVersion)")
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                statusCaption
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            actionButton
                .fixedSize()
        }
        .settingsRowPadding()
        .settingsDividerInset(FormMetrics.rowHorizontalPadding + Self.iconSize + Space.s5)
    }

    /// Re-rendered every 30 s so "checked 5 min ago" keeps up.
    private var statusCaption: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            statusCaption(now: context.date)
        }
    }

    private func statusCaption(now: Date) -> some View {
        let status = statusLine(now: now)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                if status.showsSpinner {
                    ProgressView()
                        .controlSize(.mini)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                } else if let symbol = status.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(status.tint)
                        .accessibilityHidden(true)
                }
                Text(status.text)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = status.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
            }
        }
    }

    private struct StatusLine {
        var symbol: String?
        var tint: Color = Palette.inkMuted
        var text: String
        var showsSpinner = false
        var progress: Double?
    }

    private func statusLine(now: Date) -> StatusLine {
        switch updater.status {
        case .idle:
            return StatusLine(text: lastChecked(now: now).map { "Checked \($0)" } ?? "Last checked: never")
        case .checking:
            return StatusLine(text: "Checking for updates…", showsSpinner: true)
        case .upToDate:
            return StatusLine(
                symbol: "checkmark.circle.fill",
                tint: Palette.signalReady,
                text: ["Up to date", lastChecked(now: now).map { "checked \($0)" }]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        case .available(let version, _, _):
            return StatusLine(
                symbol: "arrow.down.circle.fill",
                tint: Palette.ink,
                text: conversationBusy
                    ? "Version \(version) is available. Finish the current conversation first: installing quits the app."
                    : "Version \(version) is available. Installing quits and reopens the app."
            )
        case .downloading(let fraction):
            return StatusLine(text: "Downloading… \(Int(fraction * 100))%", progress: fraction)
        case .installing:
            return StatusLine(text: "Installing…", showsSpinner: true)
        case .installed(let relaunches):
            return StatusLine(
                symbol: "checkmark.circle.fill",
                tint: Palette.signalReady,
                text: relaunches
                    ? "Installed. Quit VoiceToText to finish; it reopens on the new version."
                    : "Installed. Quit and reopen VoiceToText to use the new version."
            )
        case .error:
            return StatusLine(
                symbol: "exclamationmark.triangle.fill",
                tint: Palette.signalWarn,
                text: ["Couldn't check for updates", lastChecked(now: now).map { "last checked \($0)" }]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
    }

    /// "just now", "5 min ago", "3 hr ago", "yesterday", "4 days ago" — or
    /// nil before the first answered check.
    private func lastChecked(now: Date) -> String? {
        guard let checked = updater.lastCheckedAt else { return nil }
        let minutes = Int(max(0, now.timeIntervalSince(checked)) / 60)
        switch minutes {
        case ..<1: return "just now"
        case ..<60: return "\(minutes) min ago"
        case ..<(24 * 60): return "\(minutes / 60) hr ago"
        case ..<(48 * 60): return "yesterday"
        default: return "\(minutes / (24 * 60)) days ago"
        }
    }

    /// Installing quits the app, so it waits for a recording or transcription
    /// to finish (`installUpdate` refuses too, for the launch prompt).
    private var conversationBusy: Bool {
        MeetingController.shared.isBusy
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updater.status {
        case .checking:
            // Same button, held disabled, so the row doesn't jump while the
            // status line shows the spinner.
            Button("Check Now") {}
                .buttonTier(.secondary)
                .disabled(true)

        case .downloading, .installing:
            EmptyView()

        case .available:
            Button("Install Update") {
                Task { await updater.installUpdate() }
            }
            .buttonTier(.primary)
            .disabled(conversationBusy)

        case .installed:
            Button("Quit VoiceToText") {
                NSApp.terminate(nil)
            }
            .buttonTier(.primary)

        case .idle, .upToDate, .error:
            Button("Check Now") {
                Task { await updater.checkForUpdate() }
            }
            .buttonTier(.secondary)
        }
    }

    private func notesRow(version: String, notes: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("What's new in \(version)")
                .typo(.body)
                .foregroundStyle(Palette.ink)
            Text(notes)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .settingsRowPadding()
    }
}
