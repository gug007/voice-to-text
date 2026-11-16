import SwiftUI

/// The primary tier (`.buttonTier(.primary)`): the one filled button on a
/// screen — Connect, Install Update, sheet confirmations.
///
/// Default fill is ``Palette/primaryFill`` (the system accent, deepened for
/// AA) with a white label. Custom rather than `.borderedProminent`, which
/// turns grey whenever the window is inactive. Height and corner radius
/// follow the native `.bordered` button at the same `controlSize`, so the
/// tiers line up side by side.
///
/// Disabled, it drops to the quiet well fill with faint ink, so it never
/// reads heavier than an enabled `.bordered` button next to it.
///
/// ```swift
/// Button("Install Update") { … }.buttonTier(.primary)
/// Button("Stop") { … }.buttonStyle(FilledButtonStyle(fill: Palette.signalLive))
/// ```
/// A custom `fill` takes ``Palette/onAction`` as its label colour.
struct FilledButtonStyle: ButtonStyle {
    var fill: Color?

    init(fill: Color? = nil) {
        self.fill = fill
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let metrics = ButtonMetrics(controlSize)
        let shape = RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
        configuration.label
            .font(.system(size: metrics.fontSize, weight: .medium))
            .foregroundStyle(isEnabled ? labelColor : Palette.inkFaint)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minHeight: metrics.height)
            .background(shape.fill(background(isPressed: configuration.isPressed)))
            .contentShape(shape)
            .onHover { isHovering = isEnabled && $0 }
            .animation(motion.hover, value: isHovering)
    }

    private var labelColor: Color { fill == nil ? Palette.onPrimary : Palette.onAction }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Palette.wellFill }
        let base = fill ?? Palette.primaryFill
        if isPressed { return base.opacity(0.78) }
        return base.opacity(isHovering ? 0.86 : 1)
    }
}

/// Height, radius, padding and font size of a hand-drawn button, matched to
/// the native `.bordered` bezel at each `controlSize`.
struct ButtonMetrics {
    let fontSize: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let horizontalPadding: CGFloat

    init(_ size: ControlSize) {
        switch size {
        case .mini, .small:
            fontSize = 11; height = 20; radius = 5; horizontalPadding = Space.s4
        case .large, .extraLarge:
            fontSize = 13; height = 30; radius = 8; horizontalPadding = Space.s6
        default:
            fontSize = 13; height = 24; radius = 6; horizontalPadding = Space.s5
        }
    }
}
