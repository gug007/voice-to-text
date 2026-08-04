import SwiftUI

/// Destructive actions are never a filled red control — they are quiet
/// `inkMuted` text that turns `signalLive` on hover, so the colour that means
/// "recording" is not spent on a button the user is only reading.
///
/// Used by Cloud's "Remove" (forget the API key) and History's "Clear All".
struct DestructiveTextButtonStyle: ButtonStyle {
    @Environment(\.motion) private var motion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering || configuration.isPressed
                             ? Palette.signalLive
                             : Palette.inkMuted)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(motion.hover, value: isHovering)
    }
}
