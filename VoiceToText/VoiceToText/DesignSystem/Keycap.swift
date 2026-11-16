import SwiftUI

// MARK: - Keycap

/// A keyboard shortcut drawn as key caps — the one way the app prints a
/// shortcut. Each key is a ≥22×22pt cap with a 12pt medium glyph (modifiers
/// 13pt). The tooltip and VoiceOver label spell the keys out
/// ("Control-Option-Shift-R").
///
/// A chord is always ONE cap ("⌃⌥⇧R", "⌘1", "⌥ Space", "Esc"). Two styles:
/// - `.display` (default): flat — hairline outline, no fill, no shadow. For
///   every read-only shortcut (hints, captions, lists, the Start row).
/// - `.editable`: the same cap raised, with a bottom edge. Only beside the
///   Change / Set button of a shortcut the user can rebind (the Shortcut pane).
///
/// ```swift
/// Keycap(keys: store.binding.displayKeys)                     // read-only
/// Keycap(keys: ["⌘", "Y"], size: .small)                      // inline in a caption
/// Keycap(keys: store.binding.displayKeys, style: .editable)   // next to "Change"
/// ```
/// `KeyCap` is the old name and still works.
struct Keycap: View {
    enum Size: Sendable {
        /// 22pt caps, 12pt glyphs — trailing controls, shortcut lists.
        case regular
        /// 18pt caps, 11pt glyphs — inside a caption or a menu-like line.
        case small
    }

    enum Style: Sendable {
        /// Flat, outlined, read-only.
        case display
        /// Raised, for a shortcut that can be changed right there.
        case editable
    }

    let keys: [String]
    var size: Size = .regular
    var style: Style = .display

    init(keys: [String], size: Size = .regular, style: Style = .display) {
        self.keys = keys
        self.size = size
        self.style = style
    }

    var body: some View {
        HStack(spacing: Space.s1 + 1) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                KeycapFace(key: cap, size: size, style: style)
            }
        }
        .fixedSize()
        .help(Keycap.spokenName(for: keys))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Keycap.spokenName(for: keys))
        .accessibilityAddTraits(.isStaticText)
    }

    /// One cap per chord in both styles, as macOS menus print shortcuts:
    /// modifiers in order, then the key — "⌃⌥⇧R", "⌘1", "⌥ Space", "Esc".
    private var caps: [String] {
        let modifiers = keys.prefix { Keycap.modifierSymbols[$0] != nil }.joined()
        let rest = keys.dropFirst(keys.prefix { Keycap.modifierSymbols[$0] != nil }.count).joined(separator: " ")
        // A named key reads as a word, so it keeps a thin gap after the glyphs.
        let gap = !modifiers.isEmpty && rest.count > 1 && rest.first?.isLetter == true ? "\u{2009}" : ""
        return [modifiers + gap + rest]
    }

    /// Modifier glyphs drawn as SF Symbols, which sit on the baseline at the
    /// right size (the text ⌃ renders as a small raised caret).
    nonisolated static let modifierSymbols: [String: String] = [
        "⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command",
    ]

    /// "Control-Option-Shift-R", "Option-Space", "Right Control".
    nonisolated static func spokenName(for keys: [String]) -> String {
        keys.map { spokenName(forKey: $0) }.joined(separator: "-")
    }

    nonisolated static func spokenName(forKey key: String) -> String {
        switch key {
        case "⌃": return "Control"
        case "⌥": return "Option"
        case "⇧": return "Shift"
        case "⌘": return "Command"
        case "fn", "🌐", "Fn": return "Function"
        case "⎋": return "Escape"
        case "Esc": return "Escape"
        case "↩", "⏎": return "Return"
        case "⇥": return "Tab"
        case "⌫": return "Delete"
        case "⌦": return "Forward Delete"
        case "←": return "Left Arrow"
        case "→": return "Right Arrow"
        case "↑": return "Up Arrow"
        case "↓": return "Down Arrow"
        case "␣": return "Space"
        default: return key
        }
    }
}

/// The old name, kept so existing call sites compile.
typealias KeyCap = Keycap

private struct KeycapFace: View {
    let key: String
    let size: Keycap.Size
    let style: Keycap.Style

    @Environment(\.increaseContrast) private var increaseContrast
    @Environment(\.displayScale) private var displayScale

    /// The cap's text with modifier characters swapped for their symbols.
    private var label: Text {
        key.reduce(Text(verbatim: "")) { text, character in
            if let symbol = Keycap.modifierSymbols[String(character)] {
                return text + Text(Image(systemName: symbol))
            }
            return text + Text(verbatim: String(character))
        }
    }

    var body: some View {
        let side: CGFloat = size == .regular ? FormMetrics.keycapMin : 18
        let base: CGFloat = size == .regular ? 12 : 11
        let shape = RoundedRectangle(cornerRadius: Radius.minimum - (size == .regular ? 1 : 2), style: .continuous)
        label
            .font(.system(size: base, weight: .medium))
            .tracking(key.count > 1 ? 0.5 : 0)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, key.count > 1 ? Space.s3 : 0)
            .frame(minWidth: side, minHeight: side)
            .background {
                if style == .editable {
                    ZStack {
                        // The 1pt darker band at the bottom is what makes it a key.
                        shape.fill(Palette.keycapShadow)
                            .offset(y: 1)
                        shape.fill(Palette.keycapFace)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    increaseContrast ? Palette.hairlineContrast : Palette.keycapEdge,
                    lineWidth: style == .editable ? 0.5 : 1 / max(displayScale, 1)
                )
            }
            .padding(.bottom, style == .editable ? 1 : 0)
    }
}

// MARK: - Badge

/// A small capsule label for a fact about an item: "Live", "Fastest",
/// "Recommended", "Most accurate". Sentence case. Neutral by default —
/// secondary ink on the well fill. `.warning` / `.error` are reserved for
/// states that need the user ("No API key", "Failed"); never use them to
/// decorate a feature.
///
/// ```swift
/// BadgeLabel("Recommended")
/// BadgeLabel("No API key", tone: .warning)
/// BadgeLabel("Active", systemImage: "checkmark")
/// ```
struct BadgeLabel: View {
    enum Tone: Sendable {
        case neutral
        case warning
        case error
    }

    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    init(_ text: String, tone: Tone = .neutral, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Space.s1 + 1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .typo(.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s1)
        .background(Capsule(style: .continuous).fill(background))
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Palette.inkMuted
        case .warning: return Palette.signalWarn
        case .error: return Palette.signalLive
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Palette.wellFill
        case .warning: return Palette.signalWarn.opacity(0.12)
        case .error: return Palette.signalLive.opacity(0.12)
        }
    }
}

// MARK: - Status tag

/// A state, not an action: "✓ Dictation", "✓ Conversations", "✓ Installed".
/// Secondary ink with a glyph and no fill, border or link colour, so it can
/// never be mistaken for a button or a link. (`BadgeLabel` is for facts about
/// an item such as "Recommended"; this is for what the item is doing now.)
///
/// ```swift
/// StatusTag("Dictation")
/// StatusTag("Downloading", systemImage: "arrow.down.circle")
/// ```
struct StatusTag: View {
    let text: String
    var systemImage: String = "checkmark"

    init(_ text: String, systemImage: String = "checkmark") {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Space.s1 + 1) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .typo(.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.inkMuted)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
