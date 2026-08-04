import SwiftUI

/// Toggle + live preview for the "review before paste" setting. Backed by the
/// `review.beforePaste` UserDefault, which DictationController reads at the end
/// of each transcription to decide whether to paste directly or show the HUD.
struct ReviewBeforePasteCard: View {
    @AppStorage("review.beforePaste") private var reviewBeforePaste: Bool = true
    @Bindable private var hotkeyStore = HotkeyStore.shared
    @Environment(\.motion) private var motion

    var body: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                SettingsToggleRow(
                    title: "Review before pasting",
                    subtitle: "Edit, paste, or cancel — nothing types until you confirm.",
                    isOn: $reviewBeforePaste
                )

                ReviewHUDPreview(
                    pasteHint: hotkeyStore.binding.displayKeys.joined(),
                    isEnabled: reviewBeforePaste
                )
            }
        }
        .animation(motion.layout, value: reviewBeforePaste)
    }
}

/// Static mock of the live `ReviewView` in `LiveHUD.swift`. It used to be a
/// hardcoded `Color(white: 0.11)` slab with white text — a black rectangle
/// sitting in a light window. It is now a `.well` inside its plate, so it takes
/// the concentric radius (16 − 6 = 10) and reads correctly in both appearances.
/// Dims when the feature is off so the user can still see what they'd turn on.
///
/// It is still a mock rather than the real `ReviewView`: that view is driven by
/// a `@Bindable LiveHUDState` and hosts an `NSTextView` that grabs first
/// responder on the next runloop turn, so embedding it in a settings pane would
/// put a focus-stealing editor in a scroll view. Rebuilding the HUD is Phase 3;
/// the two will be reconciled there.
private struct ReviewHUDPreview: View {
    let pasteHint: String
    let isEnabled: Bool

    private static let sampleTranscript = "Let's ship the build before lunch, and circle back on the API rename tomorrow."

    var body: some View {
        Plate(.well, padding: Space.s5) {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text(Self.sampleTranscript)
                    .typo(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Space.s5) {
                    ReviewKeyChip(label: "Resume", systemImage: "mic.fill", hint: "⌘R", emphasis: .ghost)
                    Spacer()
                    ReviewKeyChip(label: "Cancel", hint: "esc", emphasis: .ghost)
                    ReviewKeyChip(label: "Paste", hint: pasteHint, emphasis: .primary)
                }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.4)
    }
}

/// Non-interactive twin of `ReviewKeyButton` in `LiveHUD.swift`. Two emphases:
/// `primary` keeps the raised chip look from the live HUD; `ghost` strips
/// background/border so secondary keys read as inline hints, not buttons.
private struct ReviewKeyChip: View {
    enum Emphasis {
        case primary, ghost

        /// The label ink. Primary is the raised control, so it takes full `ink`;
        /// ghost is a hint and sits at `inkMuted`.
        var labelColor: Color {
            switch self {
            case .primary: return Palette.ink
            case .ghost: return Palette.inkMuted
            }
        }
    }

    let label: String
    var systemImage: String? = nil
    let hint: String
    let emphasis: Emphasis

    var body: some View {
        HStack(spacing: Space.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Typo.captionMedium)
                    .accessibilityLabel(label)
            } else {
                Text(label)
                    .typo(.captionMedium)
            }
            Text(hint)
                .typo(.mono)
                .foregroundStyle(Palette.inkFaint)
        }
        .foregroundStyle(emphasis.labelColor)
        .modifier(ChipBackground(emphasis: emphasis))
    }
}

/// Splits chip chrome (fill + border) out of `ReviewKeyChip` so the `ghost`
/// case can opt out entirely without nil-guarding shape modifiers inline. The
/// primary chip's radius is derived from the well it sits in, not typed.
private struct ChipBackground: ViewModifier {
    let emphasis: ReviewKeyChip.Emphasis

    func body(content: Content) -> some View {
        switch emphasis {
        case .primary:
            content
                .padding(.horizontal, Space.s5)
                .padding(.vertical, Space.s3)
                .background {
                    ConcentricRectangle(inset: Space.s3) { shape in
                        shape
                            .fill(Palette.plate)
                            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 0.5))
                    }
                }
        case .ghost:
            content
        }
    }
}
