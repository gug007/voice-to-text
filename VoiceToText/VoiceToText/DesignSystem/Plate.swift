import SwiftUI

// MARK: - The concentric law
//
// A shape nested inside a rounded parent and inset by `p` gets
// `parentRadius − p`, clamped to ≥ 6. A shape with no rounded parent uses its
// fixed base radius.
//
// This is implemented with an environment shim on EVERY OS version, on purpose.
// macOS 26's concentric container shapes resolve against the nearest ancestor
// `containerShape(_:)` — they do NOT track the window radius by themselves —
// so they buy nothing here and would fork the implementation for no gain.
// A `Plate` publishes its own resolved radius; anything nested reads it and
// subtracts its own inset.

nonisolated struct PlateRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = Radius.plate
}

extension EnvironmentValues {
    /// The corner radius of the nearest enclosing `Plate`. Nested shapes derive
    /// their own radius from this rather than typing a literal.
    nonisolated var plateRadius: CGFloat {
        get { self[PlateRadiusKey.self] }
        set { self[PlateRadiusKey.self] = newValue }
    }
}

private struct ConcentricRectModifier: ViewModifier {
    let inset: CGFloat
    let style: RoundedCornerStyle

    @Environment(\.plateRadius) private var parentRadius

    func body(content: Content) -> some View {
        let radius = Radius.concentric(parent: parentRadius, inset: inset)
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: style))
            // Keep the chain going: anything nested deeper derives from us.
            .environment(\.plateRadius, radius)
    }
}

extension View {
    /// Clips to the rounded rectangle that is concentric with the enclosing
    /// `Plate` for a shape inset by `inset`, and republishes the derived radius
    /// so deeper nesting stays concentric too.
    nonisolated func concentricRect(
        inset: CGFloat,
        style: RoundedCornerStyle = .continuous
    ) -> some View {
        modifier(ConcentricRectModifier(inset: inset, style: style))
    }
}

/// Hands the caller the concentric `RoundedRectangle` for a given inset, for
/// the cases that need to fill or stroke it rather than clip to it.
///
/// ```swift
/// ConcentricRectangle(inset: Space.s3) { shape in
///     shape.fill(Palette.wellFill)
/// }
/// ```
struct ConcentricRectangle<Content: View>: View {
    let inset: CGFloat
    var style: RoundedCornerStyle = .continuous
    @ViewBuilder let content: (RoundedRectangle) -> Content

    @Environment(\.plateRadius) private var parentRadius

    var body: some View {
        let radius = Radius.concentric(parent: parentRadius, inset: inset)
        content(RoundedRectangle(cornerRadius: radius, style: style))
            .environment(\.plateRadius, radius)
    }
}

// MARK: - Plate

/// THE content-surface primitive. One type replaces both `RowCard` and
/// `InsetCard`, and its interior padding replaces every hand-typed
/// `.padding(18)`.
///
/// Content is never glass — glass is reserved for the four floating surfaces
/// listed in `GlassSurface.swift`. A plate is opaque because content scrolls
/// under the toolbar's scroll-edge effect, and that effect only means something
/// against an opaque surface.
///
/// ```swift
/// Plate { SettingsToggleRow(…) }                       // static card
/// Plate(isInteractive: true) { ModelRow(…) }           // hoverable card
/// Plate(.well, inset: Space.s3) { progressTrack }      // radius 10 inside 16
/// Plate(.flush) { rows }                               // edge-to-edge list
/// ```
struct Plate<Content: View>: View {

    enum Variant: Sendable {
        /// Opaque card: `plate` fill, 0.5pt inset hairline, radius 16, no shadow at rest.
        case plate
        /// Recessed area inside a plate: tinted fill, no stroke, concentric radius.
        case well
        /// A plate whose children run edge to edge, separated by `PlateDivider`.
        case flush
    }

    private let variant: Variant
    private let isInteractive: Bool
    private let isPressed: Bool
    private let explicitPadding: CGFloat?
    private let inset: CGFloat
    private let baseRadius: CGFloat
    private let fillsWidth: Bool
    private let content: Content

    @Environment(\.plateRadius) private var parentRadius
    @Environment(\.increaseContrast) private var increaseContrast
    @Environment(\.motion) private var motion

    @State private var isHovering = false

    /// - Parameters:
    ///   - variant: surface treatment. Defaults to `.plate`.
    ///   - isInteractive: **only** interactive plates get a hover treatment.
    ///     A non-interactive plate never lifts, never shadows and never scales —
    ///     that difference is how the user learns which cards are clickable.
    ///   - isPressed: supplied by `PlateButtonStyle`; leave at `false` otherwise.
    ///   - padding: interior padding. Defaults to `Space.s6` (16) for `.plate`
    ///     and `.well`, and 0 for `.flush` (children own their own padding).
    ///   - inset: how far this plate sits inside its parent — only meaningful
    ///     for `.well`, where it drives the concentric radius. Defaults to
    ///     `Space.s3` (6), i.e. radius 10 inside a 16 plate.
    ///   - radius: base radius for `.plate` / `.flush`. Defaults to `Radius.plate`.
    ///   - fillsWidth: stretch to the available width. Cards want this; chips don't.
    init(
        _ variant: Variant = .plate,
        isInteractive: Bool = false,
        isPressed: Bool = false,
        padding: CGFloat? = nil,
        inset: CGFloat = Space.s3,
        radius: CGFloat = Radius.plate,
        fillsWidth: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.isInteractive = isInteractive
        self.isPressed = isPressed
        self.explicitPadding = padding
        self.inset = inset
        self.baseRadius = radius
        self.fillsWidth = fillsWidth
        self.content = content()
    }

    var body: some View {
        let radius = resolvedRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let lifted = isInteractive && isHovering

        content
            .environment(\.plateRadius, radius)
            .padding(resolvedPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .clipShape(shape)
            .background(fill(lifted: lifted), in: shape)
            .overlay {
                if let stroke = strokeColor(lifted: lifted) {
                    shape.strokeBorder(stroke, lineWidth: 0.5)
                }
            }
            .shadow(
                color: .black.opacity(lifted ? 0.07 : 0),
                radius: lifted ? 3 : 0,
                x: 0,
                y: lifted ? 1 : 0
            )
            .scaleEffect(isInteractive && isPressed ? 0.985 : 1)
            .contentShape(shape)
            .onHover { hovering in
                guard isInteractive else { return }
                isHovering = hovering
            }
            .animation(motion.hover, value: lifted)
            .animation(motion.press, value: isPressed)
    }

    // MARK: Resolution

    private var resolvedRadius: CGFloat {
        switch variant {
        case .plate, .flush:
            return baseRadius
        case .well:
            return Radius.concentric(parent: parentRadius, inset: inset)
        }
    }

    private var resolvedPadding: CGFloat {
        if let explicitPadding { return explicitPadding }
        switch variant {
        case .plate, .well: return Space.s6
        case .flush: return 0
        }
    }

    private func fill(lifted: Bool) -> Color {
        switch variant {
        case .plate, .flush:
            return lifted
                ? Palette.plateHover(increaseContrast: increaseContrast)
                : Palette.plate
        case .well:
            return Palette.wellFill
        }
    }

    private func strokeColor(lifted: Bool) -> Color? {
        switch variant {
        case .plate, .flush:
            return lifted
                ? Palette.hairlineHover(increaseContrast: increaseContrast)
                : Palette.hairline(increaseContrast: increaseContrast)
        case .well:
            return nil
        }
    }
}

// MARK: - Flush list plumbing

/// The 1px separator between rows of a `Plate(.flush)`, inset 14pt from the
/// leading edge so it reads as a list rather than a table.
struct PlateDivider: View {
    var leadingInset: CGFloat = 14

    var body: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// A flush plate built from a collection, with `PlateDivider` inserted between
/// rows automatically. This is the shape the recordings list and each Models
/// section want; hand-rolling `Plate(.flush) { LazyVStack { … } }` is only
/// needed when the rows are heterogeneous.
struct FlushPlate<Data: RandomAccessCollection, Row: View>: View
where Data.Element: Identifiable {
    let data: Data
    var leadingInset: CGFloat = 14
    var radius: CGFloat = Radius.plate
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        Plate(.flush, radius: radius) {
            // Lazy so a long list doesn't lay out every row up front.
            LazyVStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                    if index > 0 { PlateDivider(leadingInset: leadingInset) }
                    row(element)
                }
            }
        }
    }
}

// MARK: - Interactive plates

/// Wraps a button's label in an interactive `Plate`, wiring hover and the 0.985
/// press scale. Use this rather than putting a `Button` inside a `Plate`, so the
/// whole card is the tap target.
struct PlateButtonStyle: ButtonStyle {
    var padding: CGFloat? = nil
    var radius: CGFloat = Radius.plate

    func makeBody(configuration: Configuration) -> some View {
        Plate(
            .plate,
            isInteractive: true,
            isPressed: configuration.isPressed,
            padding: padding,
            radius: radius
        ) {
            configuration.label
        }
    }
}

#if DEBUG
#Preview("Plate") {
    VStack(alignment: .leading, spacing: Space.s5) {
        Plate {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Static plate").typo(.headline)
                Text("No hover — this card is not clickable.")
                    .typo(.body)
                    .foregroundStyle(.inkMuted)
            }
        }

        Button {} label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Interactive plate").typo(.headline)
                Text("Lifts on hover, scales on press.")
                    .typo(.body)
                    .foregroundStyle(.inkMuted)
            }
        }
        .buttonStyle(PlateButtonStyle())

        Plate {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("Well inside a plate").typo(.headline)
                Plate(.well, padding: Space.s5) {
                    Text("Radius 10 = 16 − 6").typo(.mono).foregroundStyle(.inkFaint)
                }
            }
        }
    }
    .padding(Space.s7)
    .frame(width: 420)
    .background(Palette.canvas)
    .motionEnvironment()
}
#endif
