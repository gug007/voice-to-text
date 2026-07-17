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
