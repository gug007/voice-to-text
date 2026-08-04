import SwiftUI

/// 34×34 rounded provider tile (tinted fill + SF Symbol). Used in both the
/// Cloud settings pane and the Models list to anchor each row. Radius is
/// `Radius.tile` so it matches every other small control exactly.
struct ProviderIconTile: View {
    let symbol: String
    let tint: Color
    var tooltip: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(tint.opacity(0.10))
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
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
            tint: isCloud ? Palette.accent : Palette.signalReady,
            tooltip: isCloud
                ? "Cloud — audio is sent to the provider's servers"
                : "Local — audio never leaves this Mac"
        )
    }
}

/// Title + subtitle on the left, a switch on the right — the standard row for
/// a boolean setting inside a `Plate`. `isLocked` dims the switch when one
/// setting forces another on (see the General pane's Dock / menu bar pair).
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isLocked: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s6)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isLocked)
        }
    }
}

// `StatusDot` (6pt dot + 11pt secondary label) is gone. Its job — "Configured",
// "Connected", "Installed", "Not set" — belongs to `StatusLabel` in
// `DesignSystem/StatusRow.swift`, which uses a filled glyph so the state
// survives colour blindness and reads at 11pt.
