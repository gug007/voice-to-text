import SwiftUI

// MARK: - Buttons
//
// Four button chromes used to live on this panel (the review key button, the
// capsule Retry, the action chip and the failure panel's buttons). They are now
// ONE: `GlassButtonStyle` at radius 10, which is the card's 22 minus its 12pt
// content inset — a real concentric relationship rather than the old 26/8/7/6
// jumble. Hover (+0.05 fill), press (scale 0.97) and the 2pt accent focus ring
// come from the style, so every HUD control has them for the first time.

/// A control on the HUD: optional SF Symbol, label, optional monospaced key hint.
///
/// Resume and Undo carry an icon AND a label — icon-only was the complaint.
struct HUDButton: View {
    let title: String
    var systemImage: String?
    var hint: String?
    var role: GlassButtonStyle.Role = .secondary
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        hint: String? = nil,
        role: GlassButtonStyle.Role = .secondary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hint = hint
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                if let hint {
                    Text(hint)
                        .typo(.mono)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .lineLimit(1)
        }
        .buttonStyle(GlassButtonStyle(role: role))
        .accessibilityLabel(title)
    }
}

/// An action chip. Same shape, same states, same radius as `HUDButton` — the
/// only difference is the caption register and the shimmer while it runs.
struct HUDActionChip: View {
    let title: String
    var systemImage: String?
    let hint: String?
    let isRunning: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .medium))
                }
                if isRunning {
                    ShimmerText(title)
                        .typo(.captionMedium)
                } else {
                    Text(title)
                        .typo(.captionMedium)
                }
                if let hint, !isRunning {
                    Text(hint)
                        .font(Typo.micro)
                        .monospaced()
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .lineLimit(1)
        }
        .buttonStyle(GlassButtonStyle(role: isRunning ? .primary : .secondary))
        .disabled(isDisabled || isRunning)
        .opacity(isDisabled ? 0.35 : 1)
    }
}

// MARK: - Banner

/// The one failure surface: 34pt, radius 10 (concentric), `signalWarn` @ 0.14
/// fill with a 0.5pt stroke at 0.34. It sits above the transcript area in the
/// review card and above the empty state in the failure card — same row either
/// way, which is what let the standalone 480×200 failure panel be deleted.
struct HUDBanner: View {
    let message: String
    /// Hint for the Retry control, when Return is bound to it.
    var retryHint: String?
    var showsRetry: Bool = false
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Space.s4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.signalWarn)

            Text(message)
                .typo(.captionMedium)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.s4)

            if showsRetry {
                HUDButton(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    hint: retryHint,
                    role: .secondary
                ) { onRetry() }
                    .help("Retry transcribing the last recording")
            }
        }
        .padding(.horizontal, Space.s5)
        // s1, not s3: a 28pt Retry control plus 6pt of padding would push the
        // row past its 34pt height and make the card grow by 6pt for nothing.
        .padding(.vertical, Space.s1)
        .frame(minHeight: HUDMetrics.bannerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ConcentricRectangle(inset: HUDMetrics.inset) { shape in
                shape.fill(Palette.signalWarn.opacity(0.14))
            }
        }
        .overlay {
            ConcentricRectangle(inset: HUDMetrics.inset) { shape in
                shape.strokeBorder(Palette.signalWarn.opacity(0.34), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Continuous effects
//
// Every `repeatForever` on this panel reads `\.motion` and renders a static
// resting frame when Reduce Motion is on. There is no `withAnimation` in the
// HUD that isn't routed through the `Motion` namespace.

/// Pulsing dot marking an active recording.
struct RecordingPulse: View {
    @Environment(\.motion) private var motion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Palette.signalLive)
            .frame(width: 9, height: 9)
            .opacity(motion.repeatsAllowed ? (pulsing ? 1 : 0.35) : 0.85)
            .onAppear {
                guard motion.repeatsAllowed else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

/// Shown while a streaming engine is connected but hasn't emitted any words
/// yet: a breathing dot beside a shimmering "Listening", so this phase and the
/// transcribing phase read as one continuous animation rather than a hard cut.
struct ListeningIndicator: View {
    @Environment(\.motion) private var motion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Palette.accent)
                .frame(width: 7, height: 7)
                .scaleEffect(motion.repeatsAllowed ? (pulsing ? 1 : 0.85) : 1)
                .opacity(motion.repeatsAllowed ? (pulsing ? 1 : 0.5) : 0.85)

            ShimmerText("Listening")
                .typo(.headline)
        }
        .onAppear {
            guard motion.repeatsAllowed else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

/// A dim word with a full-strength copy locked exactly on top of it; only the
/// gradient MASK slides, so the bright sweep tracks the letters instead of
/// rendering a shifted ghost copy. Flat `inkMuted` under Reduce Motion.
struct ShimmerText: View {
    let text: String

    @Environment(\.motion) private var motion
    @State private var phase: CGFloat = -1

    init(_ text: String) { self.text = text }

    private static let cycleDuration: TimeInterval = 1.6
    /// Mask width as a fraction of the text width.
    private static let sweepWidth: CGFloat = 0.55

    var body: some View {
        if motion.repeatsAllowed {
            animated
        } else {
            Text(text).foregroundStyle(Palette.inkMuted)
        }
    }

    private var animated: some View {
        Text(text)
            .foregroundStyle(Palette.ink.opacity(0.4))
            .overlay {
                Text(text)
                    .foregroundStyle(Palette.ink)
                    .mask {
                        GeometryReader { geo in
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0), location: 0),
                                    .init(color: .black.opacity(0.95), location: 0.5),
                                    .init(color: .black.opacity(0), location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * Self.sweepWidth)
                            .offset(x: geo.size.width * phase)
                        }
                    }
            }
            .onAppear {
                withAnimation(.linear(duration: Self.cycleDuration).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}
