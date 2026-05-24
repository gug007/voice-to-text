import SwiftUI

/// Toggle + live preview for the "review before paste" setting. Backed by the
/// `review.beforePaste` UserDefault, which DictationController reads at the end
/// of each transcription to decide whether to paste directly or show the HUD.
struct ReviewBeforePasteCard: View {
    @AppStorage("review.beforePaste") private var reviewBeforePaste: Bool = true
    @Bindable private var hotkeyStore = HotkeyStore.shared

    var body: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Review before pasting")
                            .font(.system(size: 14, weight: .medium))
                        Text("Edit, paste, or cancel — nothing types until you confirm.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Toggle("", isOn: $reviewBeforePaste)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                ReviewHUDPreview(
                    pasteHint: hotkeyStore.binding.displayKeys.joined(),
                    isEnabled: reviewBeforePaste
                )
            }
            .padding(18)
        }
    }
}

/// Static mock of the live `ReviewView` in `LiveHUD.swift` — same dark panel,
/// same sample text. Dims when the feature is off so the user can still see
/// what they'd be turning on.
private struct ReviewHUDPreview: View {
    let pasteHint: String
    let isEnabled: Bool

    private static let sampleTranscript = "Let's ship the build before lunch, and circle back on the API rename tomorrow."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.sampleTranscript)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                ReviewKeyChip(label: "Resume", systemImage: "mic.fill", hint: "⌘R", emphasis: .ghost)
                Spacer()
                ReviewKeyChip(label: "Cancel", hint: "esc", emphasis: .ghost)
                ReviewKeyChip(label: "Paste", hint: pasteHint, emphasis: .primary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.11))
        )
        .opacity(isEnabled ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
    }
}

/// Non-interactive twin of `ReviewKeyButton` in `LiveHUD.swift`. Two emphases:
/// `primary` keeps the filled chip look from the live HUD; `ghost` strips
/// background/border so secondary keys read as inline hints, not buttons.
private struct ReviewKeyChip: View {
    enum Emphasis {
        case primary, ghost

        var foregroundOpacity: Double {
            switch self {
            case .primary: return 0.96
            case .ghost: return 0.68
            }
        }
        var hintOpacity: Double {
            switch self {
            case .primary: return 0.55
            case .ghost: return 0.42
            }
        }
    }

    let label: String
    var systemImage: String? = nil
    let hint: String
    let emphasis: Emphasis

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityLabel(label)
            } else {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(hint)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(emphasis.hintOpacity))
        }
        .foregroundStyle(.white.opacity(emphasis.foregroundOpacity))
        .modifier(ChipBackground(emphasis: emphasis))
    }
}

/// Splits chip chrome (fill + border) out of `ReviewKeyChip` so the `ghost`
/// case can opt out entirely without nil-guarding shape modifiers inline.
private struct ChipBackground: ViewModifier {
    let emphasis: ReviewKeyChip.Emphasis

    func body(content: Content) -> some View {
        switch emphasis {
        case .primary:
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
        case .ghost:
            content
        }
    }
}
