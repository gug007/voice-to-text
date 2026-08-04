import SwiftUI

// MARK: - One status vocabulary
//
// The app currently says "this is fine / this needs you" three different ways:
// the 6pt `StatusDot` (SettingsComponents.swift), ad-hoc filled glyphs in the
// General pane's three copy-pasted permission cards, and raw `.green`/`.orange`
// tints that fail AA at 11pt in light mode.
//
// `StatusRow` is the single replacement. A filled SF Symbol carries the state
// (colour alone never does), the title says what it is, the message says what
// to do about it, and the optional trailing control is the fix. It is sized to
// drop straight into a `Plate`.
//
// `StatusDot` is gone: Phase 2 removed its four call sites and deleted the type.
// `StatusPlate` (StatusPlate.swift) renders N of these rows in one `Plate` and
// is what the permission / API-key / update-failure blocks use.

/// The three states anything in the app can be in. Maps to the signal tokens,
/// never to raw `.green` / `.orange` / `.red`.
nonisolated enum StatusLevel: Sendable, CaseIterable {
    /// Granted / Installed / Connected / Up to date.
    case ready
    /// Needs attention — missing permission, missing API key, update error.
    case warning
    /// Hard failure — registration failed, transcription failed.
    case error

    var tint: Color {
        switch self {
        case .ready: return Palette.signalReady
        case .warning: return Palette.signalWarn
        case .error: return Palette.signalLive
        }
    }

    /// Filled glyphs only — a filled shape reads at 13pt where a hairline glyph
    /// does not, and the silhouettes differ so the state survives colour blindness.
    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }
}

/// A filled status glyph + Headline title + Caption message, with an optional
/// trailing control. Sits inside a `Plate`; supplies no surface of its own.
struct StatusRow<Action: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var message: String?
    @ViewBuilder var action: Action


    init(
        icon: String,
        tint: Color,
        title: String,
        message: String? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.message = message
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                if let message {
                    Text(message)
                        .typo(.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Space.s5)

            action
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension StatusRow where Action == EmptyView {
    init(icon: String, tint: Color, title: String, message: String? = nil) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Level-driven convenience

extension StatusRow {
    /// The form nearly every call site wants: the level picks both the glyph and
    /// the tint, so no pane can invent its own green.
    init(
        _ level: StatusLevel,
        title: String,
        message: String? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.init(
            icon: level.symbol,
            tint: level.tint,
            title: title,
            message: message,
            action: action
        )
    }
}

extension StatusRow where Action == EmptyView {
    init(_ level: StatusLevel, title: String, message: String? = nil) {
        self.init(level, title: title, message: message) { EmptyView() }
    }
}

/// The inline form of the same vocabulary: filled glyph + label on one line.
/// This is what replaces `StatusDot(color:label:)` at the call sites where a
/// full row would be too much (a model row's "Installed", a provider's
/// "Connected").
struct StatusLabel: View {
    let level: StatusLevel
    let text: String

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: level.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(level.tint)
            Text(text)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("StatusRow") {
    VStack(spacing: Space.s5) {
        Plate {
            VStack(alignment: .leading, spacing: Space.s5) {
                StatusRow(
                    .ready,
                    title: "Microphone",
                    message: "VoiceToText can record from your microphone."
                )
                PlateDivider(leadingInset: 0)
                StatusRow(
                    .warning,
                    title: "Accessibility",
                    message: "Required for global shortcuts, Esc cancel, and typing text into other apps."
                ) {
                    Button("Open Settings…") {}.buttonStyle(.bordered)
                }
                PlateDivider(leadingInset: 0)
                StatusRow(
                    .error,
                    title: "Global hotkey",
                    message: "Hotkey registration failed. Retry, or check Accessibility permission."
                ) {
                    Button("Retry") {}.buttonStyle(.bordered)
                }
            }
        }
        HStack(spacing: Space.s5) {
            StatusLabel(level: .ready, text: "Installed")
            StatusLabel(level: .warning, text: "Not set")
        }
    }
    .padding(Space.s7)
    .frame(width: 480)
    .background(Palette.canvas)
    .motionEnvironment()
}
#endif
