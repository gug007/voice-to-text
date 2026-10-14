import SwiftUI

// MARK: - Dictation

/// Picker + still preview for the size of the dictation card. Backed by the
/// `hud.size` UserDefault, which `LiveHUDPanel` snapshots when a take's card
/// first appears — a change here applies from the next dictation, never to
/// one already on screen.
struct HUDSizeCard: View {
    @AppStorage(HUDSize.defaultsKey) private var size: HUDSize = HUDSize.defaultValue
    @Environment(\.motion) private var motion
    @Environment(\.increaseContrast) private var increaseContrast

    var body: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                HUDSettingHeader(title: "Recording HUD", subtitle: subtitle) {
                    Picker("Recording HUD", selection: $size) {
                        ForEach(HUDSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                VStack(alignment: .leading, spacing: Space.s4) {
                    HUDPreviewWell(
                        layout: HUDLayout(recordingAt: size),
                        accessibilityLabel: "Preview of the \(size.title.lowercased()) recording HUD"
                    ) { layout in
                        DictationRecordingPreview(layout: layout)
                    }
                    Text("Applies to dictation. Conversations have their own setting in the Conversations pane.")
                        .typo(.caption)
                        .foregroundStyle(Palette.inkFaint(increaseContrast: increaseContrast))
                }
            }
        }
        .animation(motion.layout, value: size)
    }

    private var subtitle: String {
        switch size {
        case .small:
            return "A pill with the timer and meter. Hover a button to see its shortcut."
        case .medium:
            return "One slim row with Cancel and Finish. Hover a button to see its shortcut."
        case .large:
            return "The full card, with key hints and live text from streaming models."
        }
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

// MARK: - Conversations

/// Off / Small / Medium / Large for the conversation card, in the
/// Conversations pane. Backed by the `conversation.hud` UserDefault, which
/// `ConversationHUDPanel` watches: unlike dictation's, a change here lands at
/// once — on a recording already running too, which morphs or goes away.
struct ConversationHUDSettingCard: View {
    @AppStorage(ConversationHUDSetting.defaultsKey)
    private var setting: ConversationHUDSetting = ConversationHUDSetting.defaultValue
    @Environment(\.motion) private var motion

    var body: some View {
        Plate {
            VStack(alignment: .leading, spacing: Space.s6) {
                HUDSettingHeader(
                    title: "Recording HUD",
                    subtitle: "Floats over every app while a conversation records. Off keeps it to the menu bar."
                ) {
                    Picker("Recording HUD", selection: $setting) {
                        ForEach(ConversationHUDSetting.allCases) { setting in
                            Text(setting.title).tag(setting)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    // Four segments: room for "Medium" in each, and still a
                    // column for the subtitle at the narrowest window.
                    .frame(width: 280)
                }

                if let size = setting.size {
                    HUDPreviewWell(
                        layout: HUDLayout(recordingAt: size),
                        accessibilityLabel: "Preview of the \(size.title.lowercased()) conversation HUD"
                    ) { layout in
                        ConversationHUDContent(
                            layout: layout,
                            isTranscribing: false,
                            samples: HUDPreviewSample.levels,
                            clock: Self.elapsed.formattedClock,
                            stopHint: HUDKeyHints.stopConversation
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(motion.layout, value: setting)
    }

    /// "24:18" — conversations run long, and the preview should look like one.
    private static let elapsed: TimeInterval = 24 * 60 + 18
}

// MARK: - Shared

/// Title and subtitle on the left, the picker on the right — the composition
/// of the General pane's Appearance card.
private struct HUDSettingHeader<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Space.s6) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .typo(.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s6)
            control
        }
    }
}

/// A HUD card, still, at 1:1 wherever the pane is wide enough for it, laid out
/// by the same `HUDLayout` as the live card and filled by the same views — so a
/// metric changed there changes here too. Only the microphone is swapped for a
/// fixed phrase.
///
/// Like `ReviewHUDPreview` it never goes near the HUD panels: each live card
/// is one panel bound to its own state, and its shadow gutter, drag surface and
/// click guard have no business in a settings pane. Nor is the card glass —
/// glass is legal on four surfaces (`GlassSurface.swift`) — so it is an opaque
/// plate raised off the well, the shape the HUD takes under Reduce
/// Transparency.
private struct HUDPreviewWell<Content: View>: View {
    let layout: HUDLayout
    let accessibilityLabel: String
    @ViewBuilder let content: (HUDLayout) -> Content

    var body: some View {
        Plate(.well, padding: Space.s5) {
            ZStack {
                card
                    .id(layout.size)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
        }
        // A still, not a demo: the dot rests instead of pulsing — a blinking
        // red dot in a settings pane reads as "recording now" — and the bars
        // hold their shape. These are the views' own Reduce Motion frames.
        .environment(\.motion, MotionValues(reduceMotion: true))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        return content(layout)
            .padding(layout.contentInsets)
            // A ceiling rather than a width: the 420pt Large card is wider than
            // the pane's column at the narrowest window, and a meter that gives
            // up a few bars' width beats a card clipped by its well.
            .frame(maxWidth: layout.width)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: layout.minHeight)
            .background(Palette.plate, in: shape)
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
            .environment(\.plateRadius, layout.cornerRadius)
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
