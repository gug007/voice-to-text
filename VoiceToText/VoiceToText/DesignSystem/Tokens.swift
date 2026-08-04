import AppKit
import SwiftUI

// MARK: - Clear Coat token layer
//
// Everything visual in the app resolves through these four namespaces:
// `Typo` (type), `Space` (spacing), `Radius` (geometry) and `Palette` (colour).
// Nothing below this file is allowed to type a raw font size, spacing value,
// corner radius or hex literal — that is the whole point of the layer.
//
// Colours are built as dynamic `NSColor`s with an appearance provider, so a
// token adapts to light/dark by itself. Call sites must NOT branch on
// `@Environment(\.colorScheme)`; if a token looks wrong in one appearance the
// fix belongs here.

// MARK: - Typography

/// The six-step type scale plus three special registers. SF Pro throughout,
/// SF Mono for the machine register. Weights in use: regular, medium, semibold
/// — bold is deliberately absent.
///
/// `Typo.headline` is the plain `Font`. `.typo(.headline)` additionally applies
/// the tracking and line-height that belong to the step, and is what call sites
/// should reach for when a style carries either.
nonisolated enum Typo {

    // Six-step scale.

    /// 26 / semibold / −0.36 / lh 32. Pane titles only.
    static let display = Font.system(size: 26, weight: .semibold)
    /// 17 / semibold / −0.20 / lh 22. Provider names, sheet titles, empty-state headlines.
    static let title = Font.system(size: 17, weight: .semibold)
    /// 13 / semibold / lh 16. Every row title, model name, primary button label.
    static let headline = Font.system(size: 13, weight: .semibold)
    /// 13 / regular / lh 17. Subtitles, body copy, field text.
    static let body = Font.system(size: 13, weight: .regular)
    /// 11 / regular / +0.06 / lh 14. Row subtitles, metadata, footnotes.
    static let caption = Font.system(size: 11, weight: .regular)
    /// 11 / medium — the caption register when it labels a control.
    static let captionMedium = Font.system(size: 11, weight: .medium)
    /// 10 / semibold / +0.50 / lh 12. UPPERCASE ONLY — apply `.textCase(.uppercase)`
    /// (or uppercase the string) at the call site; the size is only earned by caps.
    static let micro = Font.system(size: 10, weight: .semibold)

    // Three special registers.

    /// SF Mono 11 / regular / +0.20. Key hints, percentages, counters, versions,
    /// WER figures, API-key fields. Nothing else is monospaced.
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// SF Mono 13 / medium / monospacedDigit. The HUD timer.
    static let clock = Font.system(size: 13, weight: .medium, design: .monospaced).monospacedDigit()
    /// SF Mono 22 / semibold / monospacedDigit. The Conversations recording clock.
    static let clockLarge = Font.system(size: 22, weight: .semibold, design: .monospaced).monospacedDigit()
    /// SF Pro 15 / regular / lh 21. The review editor, resume composed text and
    /// the History reading pane — the only 15pt in the app.
    static let transcript = Font.system(size: 15, weight: .regular)

    /// A type step as a value, so `.typo(_:)` can apply font + tracking +
    /// line-height in one modifier.
    enum Style: Sendable, CaseIterable {
        case display, title, headline, body, caption, captionMedium, micro
        case mono, clock, clockLarge, transcript

        var font: Font {
            switch self {
            case .display: return Typo.display
            case .title: return Typo.title
            case .headline: return Typo.headline
            case .body: return Typo.body
            case .caption: return Typo.caption
            case .captionMedium: return Typo.captionMedium
            case .micro: return Typo.micro
            case .mono: return Typo.mono
            case .clock: return Typo.clock
            case .clockLarge: return Typo.clockLarge
            case .transcript: return Typo.transcript
            }
        }

        var tracking: CGFloat {
            switch self {
            case .display: return -0.36
            case .title: return -0.20
            case .headline, .body, .clock, .clockLarge, .transcript: return 0
            case .caption, .captionMedium: return 0.06
            case .micro: return 0.50
            case .mono: return 0.20
            }
        }

        /// Extra leading needed to reach the step's line-height, measured against
        /// the real font metrics rather than guessed.
        var lineSpacing: CGFloat {
            switch self {
            case .display: return Typo.extraLeading(size: 26, weight: .semibold, target: 32)
            case .title: return Typo.extraLeading(size: 17, weight: .semibold, target: 22)
            case .headline: return Typo.extraLeading(size: 13, weight: .semibold, target: 16)
            case .body: return Typo.extraLeading(size: 13, weight: .regular, target: 17)
            case .caption: return Typo.extraLeading(size: 11, weight: .regular, target: 14)
            case .captionMedium: return Typo.extraLeading(size: 11, weight: .medium, target: 14)
            case .micro: return Typo.extraLeading(size: 10, weight: .semibold, target: 12)
            case .mono, .clock, .clockLarge: return 0
            case .transcript: return Typo.extraLeading(size: 15, weight: .regular, target: 21)
            }
        }
    }

    /// Line-height target minus the font's natural line height, floored at 0.
    static func extraLeading(size: CGFloat, weight: NSFont.Weight, target: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let natural = font.ascender - font.descender + font.leading
        return max(0, target - natural)
    }
}

extension View {
    /// Applies a type step's font, tracking and line-height together.
    nonisolated func typo(_ style: Typo.Style) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

// MARK: - Spacing

/// Eight named steps replacing the 4/5/6/7/8/9/10/11/14/16/18/24/32 sprawl.
nonisolated enum Space {
    /// 2 — hairline nudges.
    static let s1: CGFloat = 2
    /// 4 — title ↔ subtitle.
    static let s2: CGFloat = 4
    /// 6 — icon-button gutters, well inset.
    static let s3: CGFloat = 6
    /// 8 — icon ↔ label.
    static let s4: CGFloat = 8
    /// 12 — stacked groups inside a plate.
    static let s5: CGFloat = 12
    /// 16 — plate interior padding.
    static let s6: CGFloat = 16
    /// 24 — pane margins, gaps between pane sections.
    static let s7: CGFloat = 24
    /// 32 — reserved for hero blocks.
    static let s8: CGFloat = 32
}

// MARK: - Radii

/// The radius ladder. All shapes are `.continuous`; the plain-circular
/// `RowCard` radius is retired.
nonisolated enum Radius {
    /// The content card. 16.
    static let plate: CGFloat = 16
    /// Small button, dropdown trigger, action chip, KeyCap. 8.
    static let control: CGFloat = 8
    /// The dictation HUD card. 22 (content inset 12 → controls at 10).
    static let hud: CGFloat = 22
    /// Provider icon tile / app mark. 8 — matches `control` exactly.
    static let tile: CGFloat = 8
    /// Sidebar selection capsule at 28pt row height.
    static let sidebarRow: CGFloat = 28
    /// Nothing derived is allowed below this — smaller reads as a pinched corner.
    static let minimum: CGFloat = 6

    /// THE CONCENTRIC LAW: a shape inset by `inset` inside a parent of radius
    /// `parent` gets `parent − inset`, never below `minimum`.
    static func concentric(parent: CGFloat, inset: CGFloat) -> CGFloat {
        max(minimum, parent - inset)
    }
}

// MARK: - Palette

/// Every colour in the app, as a light/dark pair resolved by the system.
///
/// Contrast figures are measured against the surface each token actually sits
/// on; `inkFaint` is the floor for anything that carries meaning. `NSColor`'s
/// `.tertiaryLabelColor` (~1.9:1 in light) is not an acceptable substitute and
/// must not reappear.
nonisolated enum Palette {

    // MARK: Surfaces

    /// Detail-pane background, permission gate, HUD opaque fallback base.
    static let canvas = Palette.dynamic("canvas", light: 0xF4F4F7, dark: 0x1E1E20)
    /// The sidebar column — deliberately darker than `canvas` in both modes.
    static let sidebar = Palette.dynamic("sidebar", light: 0xE4E4E9, dark: 0x121214)
    /// The one content-surface fill. Opaque: content is never glass.
    static let plate = Palette.dynamic("plate", light: 0xFFFFFF, dark: 0x2A2A2D)
    /// `plate` lifted for hover on an interactive plate.
    static let plateHover = Palette.dynamic("plateHover", light: 0xFBFBFD, dark: 0x313135)
    /// `plateHover` with the delta doubled, for Increase Contrast.
    static let plateHoverContrast = Palette.dynamic("plateHoverContrast", light: 0xF7F7FB, dark: 0x383840)
    /// Fill for a `.well` nested inside a plate.
    static let wellFill = Palette.dynamic(
        "wellFill",
        light: 0x0D0D10, lightAlpha: 0.045,
        dark: 0xFFFFFF, darkAlpha: 0.055
    )

    // MARK: Ink

    /// Primary text, active model name, record label. 19.9:1 on plate light.
    static let ink = Color(nsColor: inkNS)
    /// The AppKit sibling of ``ink``, for the views that are `NSView`s rather
    /// than SwiftUI — today that is only the HUD's review `NSTextView`.
    /// Derived from the same pair, so the two can never drift.
    static let inkNS = Palette.nsDynamic("ink", light: 0x0D0D10, dark: 0xF2F2F5)
    /// Secondary text — subtitles, body copy. 7.4:1 light / 5.9:1 dark.
    static let inkMuted = Palette.dynamic("inkMuted", light: 0x55555E, dark: 0xA6A6B0)
    /// Tertiary metadata — meta lines, gauge values, timestamps, key hints.
    /// 5.2:1 light / 4.8:1 dark, so 10–11pt decision-critical text still clears AA.
    /// Under Increase Contrast this collapses into `inkMuted`; use
    /// ``inkFaint(increaseContrast:)`` wherever the environment is available.
    static let inkFaint = Palette.dynamic("inkFaint", light: 0x6C6C77, dark: 0x94949F)

    // MARK: Signals

    /// The one tint that carries meaning. Never decorative.
    static let accent = Color(nsColor: accentNS)
    /// The AppKit sibling of ``accent`` — the review editor's insertion point
    /// and selection tint.
    static let accentNS = Palette.nsDynamic("accent", light: 0x4B5BEF, dark: 0x8493FF)
    /// Recording only — pulsing dot, Stop tint, menu-bar tint, meter clip cue.
    /// Never used for destructive actions.
    static let signalLive = Color(nsColor: signalLiveNS)
    /// The AppKit sibling of ``signalLive`` — the menu-bar glyph tint and the
    /// elapsed row in the status-item menu. Same pair, so the two can't drift.
    static let signalLiveNS = Palette.nsDynamic("signalLive", light: 0xD22C33, dark: 0xFF6B63)
    /// Granted / Installed / Connected / Up to date / copy-confirmed.
    static let signalReady = Palette.dynamic("signalReady", light: 0x12794B, dark: 0x45D08A)
    /// Needs attention — missing permission or key, update error, failed run.
    static let signalWarn = Color(nsColor: signalWarnNS)
    /// The AppKit sibling of ``signalWarn`` — the menu-bar error glyph.
    static let signalWarnNS = Palette.nsDynamic("signalWarn", light: 0x9A5A00, dark: 0xFFB44A)

    // MARK: Editorial

    /// The "MOST ACCURATE" model badge, and nothing else. It sits outside the
    /// signal set on purpose: "most accurate" is a judgement, not a status, and
    /// tinting it `accent` would collide with the active-model tint two badges
    /// away. #5856D6 / #7D7AFF.
    static let badgeIndigo = Palette.dynamic("badgeIndigo", light: 0x5856D6, dark: 0x7D7AFF)
    /// The favorited-recording star. Raw `.yellow` is 1.4:1 on a light plate,
    /// which is why the star reads as a smudge today. #C99A00 / #FFD426.
    static let favorite = Palette.dynamic("favorite", light: 0xC99A00, dark: 0xFFD426)

    // MARK: Lines

    /// The plate hairline at rest: ink @ 0.09 light / 0.14 dark.
    static let hairline = Palette.dynamic(
        "hairline",
        light: 0x0D0D10, lightAlpha: 0.09,
        dark: 0xF2F2F5, darkAlpha: 0.14
    )
    /// The plate hairline on hover: ink @ 0.12 / 0.18.
    static let hairlineHover = Palette.dynamic(
        "hairlineHover",
        light: 0x0D0D10, lightAlpha: 0.12,
        dark: 0xF2F2F5, darkAlpha: 0.18
    )
    /// Every hairline under Increase Contrast: ink @ 0.22.
    static let hairlineContrast = Palette.dynamic(
        "hairlineContrast",
        light: 0x0D0D10, lightAlpha: 0.22,
        dark: 0xF2F2F5, darkAlpha: 0.22
    )
    /// Separator between rows of a flush plate: 0.08 light / 0.09 dark.
    static let divider = Palette.dynamic(
        "divider",
        light: 0x0D0D10, lightAlpha: 0.08,
        dark: 0xFFFFFF, darkAlpha: 0.09
    )
    /// The 0.5pt edge on a material fallback surface (macOS 15 glass shim):
    /// black @ 0.07 light / white @ 0.14 dark.
    static let glassHairline = Palette.dynamic(
        "glassHairline",
        light: 0x000000, lightAlpha: 0.07,
        dark: 0xFFFFFF, darkAlpha: 0.14
    )

    // MARK: Accessibility-resolved accessors

    /// The plate hairline, honouring Increase Contrast.
    static func hairline(increaseContrast: Bool) -> Color {
        increaseContrast ? hairlineContrast : hairline
    }

    /// The hover hairline, honouring Increase Contrast.
    static func hairlineHover(increaseContrast: Bool) -> Color {
        increaseContrast ? hairlineContrast : hairlineHover
    }

    /// Tertiary metadata ink. Under Increase Contrast `inkFaint` is replaced by
    /// `inkMuted` everywhere — this accessor is the only sanctioned way to read it.
    static func inkFaint(increaseContrast: Bool) -> Color {
        increaseContrast ? inkMuted : inkFaint
    }

    /// The plate hover fill, with the delta doubled under Increase Contrast.
    static func plateHover(increaseContrast: Bool) -> Color {
        increaseContrast ? plateHoverContrast : plateHover
    }

    // MARK: Brand

    /// The brand gradient — 135°, `#6194FF → #854FF7` light / `#7FA8FF → #A276FF` dark.
    ///
    /// LEGAL IN EXACTLY TWO PLACES: the 88pt permission-gate hero tile and the
    /// 26pt sidebar app mark. NO TEXT MAY SIT ON IT — white on `#6194FF` is
    /// 2.92:1 and on `#7FA8FF` is 2.35:1, below even the 3:1 large-text floor.
    /// Tinted controls (including the record button) use flat ``accent`` instead.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandGradientStart, brandGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let brandGradientStart = Palette.dynamic("brandStart", light: 0x6194FF, dark: 0x7FA8FF)
    static let brandGradientEnd = Palette.dynamic("brandEnd", light: 0x854FF7, dark: 0xA276FF)

    // MARK: Construction

    /// Builds an appearance-adaptive `Color` from a light/dark sRGB pair.
    /// The provider closure captures only scalars, so it is safe to hand to
    /// AppKit from any isolation domain.
    static func dynamic(
        _ name: String,
        light: UInt32,
        lightAlpha: Double = 1,
        dark: UInt32,
        darkAlpha: Double = 1
    ) -> Color {
        Color(
            nsColor: nsDynamic(
                name,
                light: light, lightAlpha: lightAlpha,
                dark: dark, darkAlpha: darkAlpha
            )
        )
    }

    /// The same pair as an `NSColor`, for AppKit views that cannot take a
    /// SwiftUI `Color`. ``dynamic(_:light:lightAlpha:dark:darkAlpha:)` is a
    /// thin wrapper over this, so the two spellings of a token are one value.
    static func nsDynamic(
        _ name: String,
        light: UInt32,
        lightAlpha: Double = 1,
        dark: UInt32,
        darkAlpha: Double = 1
    ) -> NSColor {
        NSColor(name: NSColor.Name("vtt.\(name)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(
                sRGBHex: isDark ? dark : light,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        }
    }
}

extension NSColor {
    /// `0xRRGGBB` in the sRGB space.
    nonisolated convenience init(sRGBHex hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

// MARK: - Ergonomic call sites

/// `.foregroundStyle(.inkMuted)` reads better than `.foregroundStyle(Palette.inkMuted)`
/// and keeps the token names identical in both spellings.
extension Color {
    nonisolated static var canvas: Color { Palette.canvas }
    nonisolated static var sidebar: Color { Palette.sidebar }
    nonisolated static var plate: Color { Palette.plate }
    nonisolated static var ink: Color { Palette.ink }
    nonisolated static var inkMuted: Color { Palette.inkMuted }
    nonisolated static var inkFaint: Color { Palette.inkFaint }
    nonisolated static var accent: Color { Palette.accent }
    nonisolated static var signalLive: Color { Palette.signalLive }
    nonisolated static var signalReady: Color { Palette.signalReady }
    nonisolated static var signalWarn: Color { Palette.signalWarn }
}

/// Lets the tokens be written in leading-dot form wherever a `ShapeStyle` is
/// expected — `.foregroundStyle(.inkFaint)`, `.fill(.plate)`.
extension ShapeStyle where Self == Color {
    nonisolated static var canvas: Color { Palette.canvas }
    nonisolated static var sidebar: Color { Palette.sidebar }
    nonisolated static var plate: Color { Palette.plate }
    nonisolated static var ink: Color { Palette.ink }
    nonisolated static var inkMuted: Color { Palette.inkMuted }
    nonisolated static var inkFaint: Color { Palette.inkFaint }
    nonisolated static var accent: Color { Palette.accent }
    nonisolated static var signalLive: Color { Palette.signalLive }
    nonisolated static var signalReady: Color { Palette.signalReady }
    nonisolated static var signalWarn: Color { Palette.signalWarn }
}

// MARK: - Accessibility levers
//
// macOS has no Dynamic Type. The three levers that matter are Reduce Motion
// (see `Motion.swift`), Reduce Transparency (see `GlassSurface.swift`) and
// Increase Contrast — which SwiftUI surfaces as `\.colorSchemeContrast`, not as
// an `accessibilityIncreaseContrast` key.

extension EnvironmentValues {
    /// `true` when the user has Increase Contrast on. Hairlines go to ink @ 0.22,
    /// `inkFaint` collapses into `inkMuted`, and the plate hover delta doubles.
    nonisolated var increaseContrast: Bool { colorSchemeContrast == .increased }
}

#if DEBUG
#Preview("Tokens") {
    VStack(alignment: .leading, spacing: Space.s5) {
        Text("Display").typo(.display)
        Text("Title").typo(.title)
        Text("Headline").typo(.headline)
        Text("Body").typo(.body).foregroundStyle(.inkMuted)
        Text("Caption").typo(.caption).foregroundStyle(.inkFaint)
        Text("MICRO").typo(.micro).foregroundStyle(.inkFaint)
        Text("mono 11 · 4.2s").typo(.mono).foregroundStyle(.inkFaint)
        HStack(spacing: Space.s3) {
            ForEach(
                [Palette.accent, Palette.signalLive, Palette.signalReady, Palette.signalWarn],
                id: \.self
            ) { swatch in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(swatch)
                    .frame(width: 34, height: 22)
            }
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .fill(Palette.brandGradient)
                .frame(width: 34, height: 22)
        }
    }
    .padding(Space.s7)
    .background(Palette.canvas)
}
#endif
