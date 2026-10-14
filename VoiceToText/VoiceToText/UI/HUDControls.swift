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
    /// Only where the control is not inside the full card's 12pt inset — the
    /// Medium row's capsules. Nil keeps the style's concentric 10.
    var radius: CGFloat?
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        hint: String? = nil,
        role: GlassButtonStyle.Role = .secondary,
        radius: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hint = hint
        self.role = role
        self.radius = radius
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
        .buttonStyle(style)
        .accessibilityLabel(title)
    }

    private var style: GlassButtonStyle {
        var style = GlassButtonStyle(role: role)
        if let radius { style.radius = radius }
        return style
    }
}

/// A 28pt circular control for the Small HUD, where Cancel and Finish have no
/// room to say their names. Same `GlassButtonStyle` as every other HUD control,
/// so hover, press and the focus ring come with it; the title and key hint
/// the other sizes print move into the tooltip and the accessibility label.
struct HUDIconButton: View {
    let title: String
    let systemImage: String
    var hint: String?
    var role: GlassButtonStyle.Role = .secondary
    /// What VoiceOver says, when the title reads badly aloud ("&"). The title
    /// otherwise.
    var accessibilityLabel: String?
    let action: () -> Void

    /// One control-row height, like every other HUD control.
    private static let side = HUDMetrics.controlRowHeight

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(GlassButtonStyle(role: role, radius: Self.side / 2, iconSide: Self.side))
        .hudHelp(title, hint: hint)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// A control's exact footprint with a spinner in it, for while there is
/// nothing to finish — never an empty gap. Wherever something to the left
/// is flexible, a slot that shrank would slide the next control into the spot
/// the finish control just left, and the second click of a double-click on
/// Finish would land on Cancel and throw away the take it had just finished.
struct HUDBusySlot<Footprint: View>: View {
    /// The tooltip: what the card is waiting on.
    let status: String
    let accessibilityLabel: String
    /// The control whose slot this holds. Drawn hidden, so it only sizes.
    @ViewBuilder let footprint: Footprint

    var body: some View {
        ZStack {
            footprint
                .hidden()
                .disabled(true)
                .accessibilityHidden(true)
            HUDSpinner()
                .help(status)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

extension View {
    /// The tooltip for a HUD control whose key hint has no room on the card:
    /// "Finish (⌥Space)", or the title alone where no key does it.
    func hudHelp(_ title: String, hint: String?) -> some View {
        help(hint.map { "\(title) (\($0))" } ?? title)
    }
}

// MARK: - Key hints

/// The keys a live card's controls advertise. One place, so the full cards,
/// the compact rows and the Settings previews cannot disagree.
enum HUDKeyHints {
    /// Cancel promises `esc` only where Esc really cancels. With "Esc cancels
    /// dictation" off, recording, preparing and transcribing stop taking Esc,
    /// so they must not advertise it. The review and failure cards keep
    /// theirs: they are key, and Esc typed into them always works.
    static var escCancel: String? {
        HotkeyStore.shared.escapeCancelsDictation ? "esc" : nil
    }

    /// Toggle mode finishes on the same hotkey, so show it; hold mode finishes
    /// on release, which has no key to surface, so the button stands alone.
    static var finish: String? {
        switch HotkeyStore.shared.mode {
        case .toggle: return HotkeyStore.shared.binding.displayKeys.joined()
        case .hold: return nil
        }
    }

    /// The conversation shortcut, when one is set: it stops a recording from
    /// any app, so Stop & Transcribe names it. Unset by default.
    static var stopConversation: String? {
        HotkeyStore.shared.meetingBinding?.displayKeys.joined()
    }
}

/// An action chip. Same shape, same states, same radius as `HUDButton` — the
/// only difference is the caption register and the shimmer while it runs.
///
/// The running chip stays clickable and is the action's Stop: it trades its
/// shortcut hint for a stop glyph, and the click reaches the same `action`,
/// which the controller reads as "stop" for the action already running. A
/// long prompt can take minutes, and Esc alone was not a control anyone could
/// see.
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
                if isRunning {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                } else if let hint {
                    Text(hint)
                        .font(Typo.micro)
                        .monospaced()
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .lineLimit(1)
        }
        .buttonStyle(GlassButtonStyle(role: isRunning ? .primary : .secondary))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .help(isRunning ? "Stop “\(title)” (esc)" : "")
        .accessibilityLabel(isRunning ? "Stop \(title)" : title)
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
    /// A second way out beside Retry ("Check API Key"), or nil.
    var actionTitle: String?
    var actionIcon: String?
    var onAction: () -> Void = {}
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

            if let actionTitle {
                HUDButton(title: actionTitle, systemImage: actionIcon, role: .secondary) { onAction() }
            }

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
    /// Still capturing. `false` once the take is in transcribing: the dot
    /// settles to the meter's frozen grey on the same 0.4s clock the bars
    /// desaturate on, rather than blinking on over a dead meter.
    var isLive: Bool = true

    @Environment(\.motion) private var motion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(isLive ? Palette.signalLive : Palette.inkFaint.opacity(0.30))
            .frame(width: 9, height: 9)
            .opacity(liveOpacity)
            .onAppear {
                guard motion.repeatsAllowed else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .animation(motion.reduceMotion ? Motion.reduced : .smooth(duration: 0.4), value: isLive)
    }

    private var liveOpacity: Double {
        guard isLive else { return 1 }
        return motion.repeatsAllowed ? (pulsing ? 1 : 0.35) : 0.85
    }
}

/// The compact rows' "working" mark, in Finish's slot while there is nothing
/// to finish. A three-quarter arc turning on a faint track — drawn rather
/// than `ProgressView`, because the system spinner keeps spinning under Reduce
/// Motion and this one has to come to rest: a still arc, which next to the
/// frozen meter still reads as busy.
struct HUDSpinner: View {
    @Environment(\.motion) private var motion
    @State private var turning = false

    private static let diameter: CGFloat = 14
    private static let lineWidth: CGFloat = 2
    private static let arc: CGFloat = 0.72
    private static let period: TimeInterval = 0.9

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.ink.opacity(0.10), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: Self.arc)
                .stroke(Palette.inkMuted, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .onAppear {
            guard motion.repeatsAllowed else { return }
            withAnimation(.linear(duration: Self.period).repeatForever(autoreverses: false)) {
                turning = true
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
