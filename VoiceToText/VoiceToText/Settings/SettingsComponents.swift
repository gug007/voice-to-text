import SwiftUI

/// 34×34 rounded provider tile (gradient fill + SF Symbol). Used in both the
/// Cloud settings pane and the Models list to anchor each row.
struct ProviderIconTile: View {
    let symbol: String
    let tint: Color
    var tooltip: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.10))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint.gradient)
        }
        .frame(width: 34, height: 34)
        .help(tooltip ?? "")
    }
}

extension ProviderIconTile {
    /// Convenience initializer that picks symbol + tint from a model's
    /// local/cloud classification.
    init(isCloud: Bool) {
        self.init(
            symbol: isCloud ? "cloud.fill" : "laptopcomputer",
            tint: isCloud ? .blue : .green,
            tooltip: isCloud
                ? "Cloud — audio is sent to the provider's servers"
                : "Local — audio never leaves this Mac"
        )
    }
}

/// Title + subtitle on the left, a switch on the right — the standard row for
/// a boolean setting inside a `RowCard`. `isLocked` dims the switch when one
/// setting forces another on (see the General pane's Dock / menu bar pair).
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isLocked: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isLocked)
        }
    }
}

/// 6 px colored dot + 11 pt secondary label. Used wherever the UI shows
/// a green/orange "online status" line: "Configured", "Connected",
/// "Installed", "Not set", etc.
struct StatusDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
