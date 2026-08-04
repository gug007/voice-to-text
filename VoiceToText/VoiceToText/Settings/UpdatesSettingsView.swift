import SwiftUI

struct UpdatesPane: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        PaneScaffold {
            PaneHeader(
                title: "Updates",
                subtitle: "Keep VoiceToText up to date."
            )

            versionCard
            actionCard

            if case .error(let message) = updater.status {
                // The same status vocabulary the permission group uses.
                StatusPlate([
                    StatusItem(
                        id: "update-error",
                        level: .warning,
                        title: "Update failed",
                        message: message
                    )
                ])
            }

            if case .available(_, _, let notes) = updater.status, !notes.isEmpty {
                releaseNotesCard(notes)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var versionCard: some View {
        Plate {
            HStack {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Current version")
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(updater.currentVersion)
                        .typo(.mono)
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                statusPill
            }
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        Plate {
            HStack {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(actionTitle)
                        .typo(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(actionSubtitle)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)

                    if case .downloading(let fraction) = updater.status {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, Space.s2)
                    }
                }
                Spacer()
                actionButton
            }
        }
    }

    private func releaseNotesCard(_ notes: String) -> some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Release notes")
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text(notes)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Status pill

    @ViewBuilder
    private var statusPill: some View {
        switch updater.status {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: Space.s3) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
            }

        case .upToDate:
            StatusLabel(level: .ready, text: "Up to date")

        case .available(let latest, _, _):
            Label("v\(latest) available", systemImage: "arrow.down.circle.fill")
                .typo(.captionMedium)
                .foregroundStyle(Palette.accent)
                .labelStyle(.titleAndIcon)

        case .downloading(let fraction):
            Text("Downloading \(Int(fraction * 100))%")
                .typo(.mono)
                .foregroundStyle(Palette.inkMuted)
                .contentTransition(.numericText())

        case .installing:
            HStack(spacing: Space.s3) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .typo(.captionMedium)
                    .foregroundStyle(Palette.inkMuted)
            }

        case .error:
            StatusLabel(level: .warning, text: "Error")
        }
    }

    // MARK: - Action card copy

    private var actionTitle: String {
        switch updater.status {
        case .available(let v, _, _):
            return "Version \(v) is ready to install"
        case .downloading:
            return "Downloading update…"
        case .installing:
            return "Installing update…"
        case .upToDate:
            return "You're up to date"
        default:
            return "Check for updates"
        }
    }

    private var actionSubtitle: String {
        switch updater.status {
        case .available:
            return "The app will quit and relaunch automatically."
        case .downloading(let fraction):
            return "\(Int(fraction * 100))% downloaded"
        case .installing:
            return "Mounting and copying the new app."
        case .upToDate:
            return "You have the latest version."
        case .error(let message):
            return message
        default:
            return "Fetch the latest release from GitHub."
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updater.status {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)

        case .available:
            Button("Install Update") {
                Task { await updater.installUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(Palette.accent)

        default:
            Button("Check Now") {
                Task { try? await updater.checkForUpdate() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}
