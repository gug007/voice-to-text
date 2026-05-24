import SwiftUI

/// Toggle + live preview for the "review before paste" setting. Backed by the
/// `review.beforePaste` UserDefault, which DictationController reads at the end
/// of each transcription to decide whether to paste directly or show the HUD.
struct ReviewBeforePasteCard: View {
    @AppStorage("review.beforePaste") private var reviewBeforePaste: Bool = true
    @Bindable private var hotkeyStore = HotkeyStore.shared

    var body: some View {
        RowCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Review before pasting")
                            .font(.system(size: 14, weight: .medium))
                        Text("See the transcript first so you can edit, paste, or cancel — nothing is typed until you confirm.")
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
/// same chip styling, sample text. Dims when the feature is off so the user
/// can still see what they'd be turning on.
private struct ReviewHUDPreview: View {
    let pasteHint: String
    let isEnabled: Bool

    private static let sampleTranscript = "Let's ship the build before lunch, and circle back on the API rename tomorrow."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 10, weight: .semibold))
                Text("PREVIEW · what you'll see after dictation")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 12) {
                Text(Self.sampleTranscript)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ReviewKeyChip(label: "Resume", systemImage: "mic.fill", hint: "⌘R", emphasis: .secondary)
                    Spacer()
                    ReviewKeyChip(label: "Cancel", hint: "esc", emphasis: .secondary)
                    ReviewKeyChip(label: "Paste", hint: pasteHint, emphasis: .primary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05))
            )
        }
        .opacity(isEnabled ? 1.0 : 0.45)
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
    }
}

/// Non-interactive twin of `ReviewKeyButton` in `LiveHUD.swift`. Kept as a
/// separate type so the preview stays decoupled from the real HUD's button
/// semantics (actions, focus, keyboard shortcuts).
private struct ReviewKeyChip: View {
    enum Emphasis {
        case primary, secondary

        var foregroundOpacity: Double { self == .primary ? 0.96 : 0.72 }
        var hintOpacity: Double { self == .primary ? 0.55 : 0.4 }
        var fillOpacity: Double { self == .primary ? 0.12 : 0.05 }
        var strokeOpacity: Double { self == .primary ? 0.18 : 0.08 }
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
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(.white.opacity(emphasis.foregroundOpacity))
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(emphasis.fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(emphasis.strokeOpacity))
        )
    }
}
