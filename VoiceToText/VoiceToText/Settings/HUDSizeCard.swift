import SwiftUI

// MARK: - Dictation

/// The Dictation HUD row of General's Dictation group: size picker and a
/// compact inset with a still preview and the card's shortcuts. Backed by the
/// `hud.size` UserDefault, which `LiveHUDPanel` snapshots when a take's card
/// first appears — a change here applies from the next dictation, never to
/// one already on screen.
struct HUDSizeRow: View {
    @AppStorage(HUDSize.defaultsKey) private var size: HUDSize = HUDSize.defaultValue
    @Environment(\.motion) private var motion
    private var store: HotkeyStore { .shared }

    var body: some View {
        SettingsRow("Dictation HUD", caption: caption) {
            Picker("Dictation HUD", selection: $size) {
                ForEach(HUDSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        } below: {
            HUDPreviewInset(layout: HUDLayout(recordingAt: size), hints: hints) { layout in
                DictationRecordingPreview(layout: layout)
            }
        }
        .animation(motion.layout, value: size)
    }

    private var caption: String {
        switch size {
        case .small: return "Floats while you dictate: a pill with the timer and meter."
        case .medium: return "Floats while you dictate: one slim row with Cancel and Finish."
        case .large: return "Floats while you dictate: the full card, with live text."
        }
    }

    /// The card's buttons answer to these keys; printed so nobody has to hover
    /// to find out. Esc only while it really cancels, and the finish key as the
    /// recording mode uses it.
    private var hints: [HUDHint] {
        var hints: [HUDHint] = []
        if store.escapeCancelsDictation {
            hints.append(HUDHint(keys: ["Esc"], label: "Cancel"))
        }
        switch store.mode {
        case .toggle:
            hints.append(HUDHint(keys: store.binding.displayKeys, label: "Finish"))
        case .hold:
            hints.append(HUDHint(keys: store.binding.displayKeys, label: "Release to finish"))
        }
        return hints
    }
}

/// A fresh dictation take's recording card. Small and Medium are the live
/// card's own `HUDCompactRow`; Large is its recording sections in its order
/// and at its heights — the meter over clock, Cancel and Finish — since the
/// live control row is bound to `LiveHUDState`.
private struct DictationRecordingPreview: View {
    let layout: HUDLayout

    var body: some View {
        if let compactRow = layout.compactRow {
            HUDCompactRow(
                metrics: compactRow,
                phase: .recording,
                samples: HUDPreviewSample.levels,
                readout: .clock(HUDClock.text(seconds: Self.elapsedSeconds)),
                persistentControl: .cancel(hint: HUDKeyHints.escCancel) {},
                finishControl: .finish(hint: HUDKeyHints.finish) {}
            )
            .frame(height: HUDMetrics.controlRowHeight)
        } else {
            VStack(alignment: .leading, spacing: HUDMetrics.gap) {
                LevelBars(samples: HUDPreviewSample.levels)
                    .frame(height: HUDMetrics.meterHeight)
                    .frame(maxWidth: .infinity)
                HStack(spacing: Space.s4) {
                    HUDClock(seconds: Self.elapsedSeconds)
                    Spacer(minLength: Space.s4)
                    HUDButton(title: "Cancel", hint: HUDKeyHints.escCancel, role: .secondary) {}
                    HUDButton(title: "Finish", hint: HUDKeyHints.finish, role: .primary) {}
                }
                .frame(height: HUDMetrics.controlRowHeight)
            }
        }
    }

    /// "0:03" — a dictation is a sentence or two.
    private static let elapsedSeconds: Double = 3
}

// MARK: - Preview

/// A compact inset: the HUD card as a still, at 1:1, beside the keys its
/// buttons answer to (below them for Large, which needs the width). Laid out
/// by the same `HUDLayout` as the live card and filled by the same views — so
/// a metric changed there changes here too.
///
/// It never goes near the HUD panels, and it isn't glass (glass is legal on
/// four surfaces, `GlassSurface.swift`): an opaque plate raised off the well,
/// the shape the HUD takes under Reduce Transparency. The card is inert —
/// dimmed, no hover, no hits, hidden from VoiceOver — so its ✕ and ✓ never
/// pass for live buttons; the legend beside it stays readable.
private struct HUDPreviewInset<Content: View>: View {
    let layout: HUDLayout
    let hints: [HUDHint]
    @ViewBuilder let content: (HUDLayout) -> Content

    var body: some View {
        Plate(.well, padding: Space.s4) {
            Group {
                if layout.size == .large {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        card
                        HUDHintLine(hints: hints)
                    }
                } else {
                    HStack(spacing: Space.s6) {
                        card
                        Spacer(minLength: 0)
                        HUDHintLine(hints: hints)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        return content(layout)
            .padding(layout.contentInsets)
            // Small and Medium at their own width, so the meter keeps its
            // bars beside the legend; Large as a ceiling, since the 420pt card
            // can be wider than the column at the narrowest window.
            .frame(width: layout.size == .large ? nil : layout.width)
            .frame(maxWidth: layout.width)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: layout.minHeight)
            .background(Palette.plate, in: shape)
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
            .environment(\.plateRadius, layout.cornerRadius)
            .opacity(0.8)
            .id(layout.size)
            .transition(.opacity)
            // A still, not a demo: the dot rests instead of pulsing — a
            // blinking red dot in a settings pane reads as "recording now" —
            // and the bars hold their shape (the views' Reduce Motion frames).
            .environment(\.motion, MotionValues(reduceMotion: true))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum HUDPreviewSample {
    /// A short phrase: words with gaps between them, syllables inside each
    /// word, and the write head mid-word — what the meter shows while someone
    /// is talking. A whole 140-sample buffer, so each size pools its own window
    /// out of it exactly as the live card does.
    static let levels: [Double] = (0..<LiveHUDState.levelHistoryCount).map { index in
        let t = Double(index)
        let word = max(0, sin(t / 5 + 1.3))
        let stress = 0.55 + 0.45 * abs(sin(t / 17))
        let syllable = abs(sin(t / 1.6))
        return 0.04 + 0.86 * word * stress * (0.45 + 0.55 * syllable)
    }
}

/// One printed shortcut under a HUD preview: keys, then what they do.
private struct HUDHint: Identifiable {
    let keys: [String]
    let label: String
    var id: String { label }
}

/// "Esc Cancel   ⌥ Space Finish" — the preview's buttons, with their keys
/// printed instead of waiting behind a hover.
private struct HUDHintLine: View {
    let hints: [HUDHint]

    var body: some View {
        if !hints.isEmpty {
            HStack(spacing: Space.s6) {
                ForEach(hints) { hint in
                    HStack(spacing: Space.s3) {
                        Keycap(keys: hint.keys, size: .small)
                        Text(hint.label)
                            .typo(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(hint.label): \(Keycap.spokenName(for: hint.keys))")
                }
            }
        }
    }
}
