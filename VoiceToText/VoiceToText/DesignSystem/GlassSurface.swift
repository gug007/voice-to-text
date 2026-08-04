import SwiftUI

// MARK: - Glass
//
// GLASS INVENTORY — exactly four surfaces, and this list is the spec. If a
// fifth appears in review, it is wrong. Every entry names its call site, so
// `grep glassSurface` is the audit:
//
//   1. The window toolbar — system glass. No call site here, and none wanted:
//      the toolbar gets its glass from `.toolbar { }` itself.
//   2. The dictation HUD card — `UI/LiveHUDView.swift` (the card and its
//      Reduce-Transparency sibling are one surface presented two ways).
//   3. The undo toast — `Settings/UndoDeletionToast.swift`.
//   4. Popovers — `Settings/MinimalDropdown.swift` (`DropdownPopup`, which is
//      both the dropdown's own popup AND the RecordingRow regenerate menu) and
//      `Settings/RecordingRow.swift` (the speaker-rename popover).
//
// That is four call-site groups for three code locations, because the toolbar
// needs none. The point of routing all of them through one modifier is the
// accessibility branch below: Reduce Transparency has to flatten the whole
// floating layer at once, or the surfaces that missed it read as the only
// translucent things on screen.
//
// EVERYTHING ELSE IS OPAQUE. Model rows, History rows, settings cards,
// transcript blocks and the permission gate are `Plate`s. Glass is a floating
// layer, never a texture: content that scrolls beneath the toolbar's scroll-edge
// effect must be opaque for that effect to mean anything, and glass cannot
// cheaply sample glass.
//
// The app is pinned at macOS 15.0, so every glass surface is authored twice:
// real Liquid Glass on macOS 26+, `.regularMaterial` plus a 0.5pt hairline
// below. Both branches additionally collapse to an opaque fill under
// Reduce Transparency.

private struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    /// `plate` for surfaces that sit over content (HUD, toast, popovers);
    /// `canvas` where the surface is the backdrop itself.
    let opaqueFill: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            // Blur removed entirely, 1pt stroke at ink @ 0.18.
            content
                .background(opaqueFill, in: shape)
                .overlay { shape.strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1) }
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Palette.glassHairline, lineWidth: 0.5) }
        }
    }
}

extension View {
    /// Applies the app's glass treatment in `shape`.
    ///
    /// Legal on exactly four surfaces — see the inventory at the top of this
    /// file. On macOS 26+ this is real Liquid Glass; on 15.0–25 it is
    /// `.regularMaterial` with a 0.5pt hairline, which still reads as a
    /// deliberate floating layer. Under Reduce Transparency both become an
    /// opaque `plate` fill with a 1pt ink stroke.
    nonisolated func glassSurface<S: InsettableShape>(
        in shape: S,
        opaqueFill: Color = Palette.plate
    ) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, opaqueFill: opaqueFill))
    }

    /// Convenience for the common rounded-rectangle case.
    nonisolated func glassSurface(
        cornerRadius: CGFloat = Radius.hud,
        opaqueFill: Color = Palette.plate
    ) -> some View {
        glassSurface(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            opaqueFill: opaqueFill
        )
    }
}

// MARK: - Controls on glass

/// The HUD control chrome: radius 10 (= card 22 − content inset 12, concentric),
/// `ink` text rather than white — that is what gives the HUD a real light mode.
///
/// One shape for every control on the panel: Cancel, Finish, Paste, Resume,
/// Undo, Retry and the action chips. The old Capsule variant is deleted so the
/// panel has exactly one button shape.
struct GlassButtonStyle: ButtonStyle {
    enum Role: Sendable {
        /// Fill white @ 0.62 light / white @ 0.10 dark. The one primary per panel.
        case primary
        /// Fill ink @ 0.05 / white @ 0.05.
        case secondary
        /// Secondary weight, `accent` ink and an `accent` @ 0.12 fill — for a
        /// control that is neither the primary action nor a plain alternative.
        /// The HUD's Resume button is the only user: with Cancel, Resume and
        /// Paste side by side, a three-way choice needs three legible weights.
        case accent
    }

    var role: Role = .secondary
    var radius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, role: role, radius: radius)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: GlassButtonStyle.Role
    let radius: CGFloat

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.motion) private var motion

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        configuration.label
            .typo(.headline)
            .foregroundStyle(role == .accent ? Palette.accent : Palette.ink)
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s3)
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(stroke, lineWidth: 0.5) }
            // Visible 2pt accent focus ring at 60%, offset 2pt — keyboard users
            // must be able to see which HUD control Tab landed on.
            .overlay {
                RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(isFocused ? 0.6 : 0), lineWidth: 2)
                    .padding(-2)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(motion.hover, value: isHovering)
            .animation(motion.press, value: configuration.isPressed)
            .animation(motion.hover, value: isFocused)
    }

    /// Base fill per role, raised one step (+0.05) on hover.
    private var fill: Color {
        let bump = isHovering && isEnabled ? 0.05 : 0
        if reduceTransparency {
            // No blur to sit on — fall back to the opaque well/plate vocabulary.
            switch role {
            case .primary: return Palette.plate.opacity(1)
            case .secondary: return Palette.wellFill.opacity(1)
            case .accent: return Palette.accent.opacity(0.16)
            }
        }
        switch role {
        case .primary:
            return Palette.dynamic(
                "hudPrimaryFill\(bump)",
                light: 0xFFFFFF, lightAlpha: 0.62 + bump,
                dark: 0xFFFFFF, darkAlpha: 0.10 + bump
            )
        case .secondary:
            return Palette.dynamic(
                "hudSecondaryFill\(bump)",
                light: 0x0D0D10, lightAlpha: 0.05 + bump,
                dark: 0xFFFFFF, darkAlpha: 0.05 + bump
            )
        case .accent:
            return Palette.accent.opacity(0.12 + bump)
        }
    }

    private var stroke: Color {
        if reduceTransparency { return Palette.ink.opacity(0.18) }
        switch role {
        case .primary:
            return Palette.dynamic(
                "hudPrimaryStroke",
                light: 0x0D0D10, lightAlpha: 0.18,
                dark: 0xFFFFFF, darkAlpha: 0.18
            )
        case .secondary:
            return Palette.dynamic(
                "hudSecondaryStroke",
                light: 0x0D0D10, lightAlpha: 0.10,
                dark: 0xFFFFFF, darkAlpha: 0.10
            )
        case .accent:
            return Palette.accent.opacity(0.30)
        }
    }
}

#if DEBUG
#Preview("Glass") {
    VStack(spacing: Space.s5) {
        HStack(spacing: Space.s4) {
            Text("0:14").typo(.clock).foregroundStyle(.inkFaint)
            Spacer()
            Button("Cancel") {}.buttonStyle(GlassButtonStyle(role: .secondary))
            Button("Finish") {}.buttonStyle(GlassButtonStyle(role: .primary))
        }
        .padding(Space.s5)
        .frame(width: 420)
        .glassSurface(cornerRadius: Radius.hud)
    }
    .padding(Space.s8)
    .background(Palette.canvas)
    .motionEnvironment()
}
#endif
