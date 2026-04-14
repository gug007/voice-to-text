import SwiftUI

struct UpdatesPane: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaneHeader(
                    title: "Updates",
                    subtitle: "Keep VoiceToText up to date."
                )

                versionCard
                actionCard

                if case .error(let message) = updater.status {
                    errorCard(message)
                }

                if case .available(_, _, let notes) = updater.status, !notes.isEmpty {
                    releaseNotesCard(notes)
                }
            }
            .padding(32)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var versionCard: some View {
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current version")
                        .font(.system(size: 14, weight: .medium))
                    Text(updater.currentVersion)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        RowCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .medium))
                    Text(actionSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if case .downloading(let fraction) = updater.status {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, 4)
                    }
                }
                Spacer()
                actionButton
            }
            .padding(18)
        }
    }

    private func errorCard(_ message: String) -> some View {
        RowCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Update failed")
                        .font(.system(size: 13, weight: .medium))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(18)
        }
    }

    private func releaseNotesCard(_ notes: String) -> some View {
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Release notes")
                    .font(.system(size: 13, weight: .medium))
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(18)
        }
    }

    // MARK: - Status pill

    @ViewBuilder
    private var statusPill: some View {
        switch updater.status {
        case .idle:
            EmptyView()

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)

        case .available(let latest, _, _):
            Label("v\(latest) available", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .labelStyle(.titleAndIcon)

        case .downloading(let fraction):
            Text("Downloading \(Int(fraction * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
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

        default:
            Button("Check Now") {
                Task { try? await updater.checkForUpdate() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}
