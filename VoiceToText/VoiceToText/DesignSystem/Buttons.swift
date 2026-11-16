import SwiftUI

// MARK: - Three button tiers
//
// primary   — accent-filled button with a white label (Install Update,
//             Connect, Save). At most one per screen; in-row actions are
//             secondary.
// secondary — the bordered bezel with a firm edge (Check Now, Change, Test,
//             Cancel). Matches native `.bordered`, plus a 0.5pt edge so the
//             control boundary reads even in an inactive window.
// tertiary  — a link in AppKit's link colour, no underline until hover,
//             24pt hit height (Release notes ↗, Get an API key ↗, Details).
//
// destructive — a bordered button with a red label (Delete…, Remove).
//             Always pair with `role: .destructive`.
//
// Disabled buttons use the quiet disabled look — a disabled primary never
// renders heavier than an enabled secondary.

enum ButtonTier: Sendable {
    case primary
    case secondary
    case tertiary
    case destructive
}

extension View {
    /// Applies one of the three app-wide button tiers.
    ///
    /// ```swift
    /// Button("Install Update") { … }.buttonTier(.primary)
    /// Button("Check Now") { … }.buttonTier(.secondary)
    /// Button("Relaunch") { … }.buttonTier(.tertiary)
    /// Button("Delete…", role: .destructive) { … }.buttonTier(.destructive)
    /// ```
    @ViewBuilder
    func buttonTier(_ tier: ButtonTier) -> some View {
        switch tier {
        case .primary: buttonStyle(FilledButtonStyle())
        case .secondary: buttonStyle(BezelButtonStyle())
        case .tertiary: buttonStyle(TextLinkButtonStyle())
        case .destructive: buttonStyle(BezelButtonStyle(label: Palette.destructive))
        }
    }
}

// MARK: - Secondary and destructive: the bezel

/// The secondary and destructive tiers: the native `.bordered` bezel's fill,
/// height and radius at each `controlSize`, plus a 0.5pt edge
/// (`hairlineContrast`, ~1.6:1 light / ~2:1 dark against the plate) so the
/// control's boundary shows when the fill alone is 1.2:1. The destructive
/// tier passes a red label (``Palette/destructive``, ≥4.5:1 on the fill).
///
/// ```swift
/// Button("Check Now") { … }.buttonTier(.secondary)
/// Button("Delete Action…", role: .destructive) { … }.buttonTier(.destructive)
/// ```
struct BezelButtonStyle: ButtonStyle {
    var label: Color = Palette.ink

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let metrics = ButtonMetrics(controlSize)
        let shape = RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
        configuration.label
            .font(.system(size: metrics.fontSize))
            .foregroundStyle(isEnabled ? label : Palette.inkFaint)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minHeight: metrics.height)
            .background(shape.fill(Palette.borderedFill))
            .overlay {
                if configuration.isPressed || isHovering {
                    shape.fill(Palette.ink.opacity(configuration.isPressed ? 0.10 : 0.04))
                }
            }
            .overlay(shape.strokeBorder(Palette.hairlineContrast, lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.7)
            .contentShape(shape)
            .onHover { isHovering = isEnabled && $0 }
            .animation(motion.hover, value: isHovering)
    }
}

// MARK: - Tertiary: text link

/// The native link look (`.buttonStyle(.link)`): link-coloured text, no
/// underline at rest, underlined on hover, with a 24pt-tall hit area that the
/// native style lacks. Use `ExternalLink` for a URL — it adds the ↗.
///
/// ```swift
/// Button("Show Details") { expand() }
///     .buttonTier(.tertiary)          // or .buttonStyle(.textLink)
/// Button("Conversations") { open(.meetings) }
///     .buttonStyle(TextLinkButtonStyle(font: Typo.caption))   // inside a caption
/// ```
struct TextLinkButtonStyle: ButtonStyle {
    /// Text size. Defaults to the body step; pass `Typo.caption` inside a caption line.
    var font: Font = Typo.body
    /// Text colour. The link colour; `.buttonTier(.destructive)` passes
    /// ``Palette/destructive``.
    var color: Color = Palette.link

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(isEnabled ? color : Palette.inkFaint)
            .underline(isHovering, color: color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: FormMetrics.linkHitHeight)
            .contentShape(Rectangle())
            .onHover { isHovering = isEnabled && $0 }
            .animation(motion.hover, value: isHovering)
    }
}

extension ButtonStyle where Self == TextLinkButtonStyle {
    /// The tertiary tier: `.buttonStyle(.textLink)`.
    static var textLink: TextLinkButtonStyle { TextLinkButtonStyle() }
}

/// A tertiary link that opens a URL, with a trailing ↗ so it reads as leaving
/// the app. The URL is the tooltip.
///
/// ```swift
/// ExternalLink("Release notes", destination: AppUpdater.releasesPageURL)
/// ExternalLink("Get an API key", destination: url, font: Typo.caption)
/// ```
struct ExternalLink: View {
    let title: String
    let destination: URL
    var font: Font = Typo.body

    @Environment(\.openURL) private var openURL

    init(_ title: String, destination: URL, font: Font = Typo.body) {
        self.title = title
        self.destination = destination
        self.font = font
    }

    var body: some View {
        Button {
            openURL(destination)
        } label: {
            HStack(spacing: Space.s1) {
                Text(title)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(TextLinkButtonStyle(font: font))
        .help(destination.absoluteString)
        .accessibilityHint("Opens in your browser")
    }
}
