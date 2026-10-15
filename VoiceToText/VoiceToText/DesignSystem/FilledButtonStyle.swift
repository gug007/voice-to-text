import SwiftUI

/// The one filled push button — Connect, Install Update, the Dictate pane's
/// Start / Stop, sheet confirmations, the permission gate.
///
/// Replaces `.borderedProminent`, whose label AppKit always draws white: on the
/// monochrome palette's near-white dark-mode ``Palette/action`` that label
/// disappears. The label here is ``Palette/onAction``, which clears AA on both
/// ``Palette/action`` and ``Palette/signalLive`` in either appearance.
struct FilledButtonStyle: ButtonStyle {
    var fill: Color = Palette.action

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typo(.headline)
            .foregroundStyle(Palette.onAction)
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(fill.opacity(fillOpacity(isPressed: configuration.isPressed)))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovering = isEnabled && $0 }
            .animation(motion.hover, value: isHovering)
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.78 }
        return isHovering ? 0.86 : 1
    }
}
