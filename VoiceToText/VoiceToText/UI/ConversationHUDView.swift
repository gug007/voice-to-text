import SwiftUI

// MARK: - Root
//
// The conversation card is the dictation card's recording state and nothing
// else: one shape for both of its phases, laid out by `HUDLayout(recordingAt:)`
// and worn in the same chrome. Its only control is Stop & Transcribe.

struct ConversationHUDView: View {
    @Bindable var state: ConversationHUDState
    /// Reports the card's laid-out size so the panel can size itself to it.
    let onCardSize: (CGSize) -> Void
    let onStop: () -> Void

    var body: some View {
        ConversationCard(state: state, onCardSize: onCardSize, onStop: onStop)
            .padding(HUDMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motionEnvironment()
    }
}

private struct ConversationCard: View {
    @Bindable var state: ConversationHUDState
    let onCardSize: (CGSize) -> Void
    let onStop: () -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        let layout = HUDLayout(recordingAt: state.size)
        let morph: Animation? = HUDFeatureFlags.morphEnabled ? motion.hudMorph : nil

        ConversationHUDContent(
            layout: layout,
            isTranscribing: state.isTranscribing,
            samples: state.levels,
            // The newest sample is the current level.
            isOverloaded: !state.isTranscribing && (state.levels.last ?? 0) > LevelBars.overloadThreshold,
            clock: state.elapsed.formattedClock,
            chunkProgress: state.chunkProgress,
            stopHint: HUDKeyHints.stopConversation,
            onStop: onStop
        )
        .padding(layout.contentInsets)
        .frame(width: layout.width)
        // The card's height is its content's, never the panel's: the panel is
        // sized FROM this, so it must not be sized BY it.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: layout.minHeight)
        .modifier(HUDCardChrome(layout: layout, placement: ConversationHUDPanel.shared.placement))
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onCardSize)
        .animation(morph, value: layout)
        .animation(morph, value: state.isTranscribing)
        .modifier(HUDPresentation(presentationCount: state.presentationCount, isDismissing: state.isDismissing))
    }
}

// MARK: - Content

/// The conversation card's sections at any size, from plain values — the live
/// card passes the mirrored session, the Settings preview a sample phrase.
///
/// Recording: dot, meter, clock and Stop & Transcribe. Transcribing: the bars
/// freeze, the dot greys, the clock holds the recording's length, and Stop's
/// exact slot spins. Where there is room for it the chunk counter says how far
/// along a long recording is.
struct ConversationHUDContent: View {
    let layout: HUDLayout
    let isTranscribing: Bool
    let samples: [Double]
    var isOverloaded: Bool = false
    /// The recording's length, `formattedClock`.
    let clock: String
    /// "3/12", or nil for a one-chunk recording.
    var chunkProgress: String?
    /// The conversation shortcut, when one is set.
    var stopHint: String?
    var onStop: () -> Void = {}

    var body: some View {
        if let compactRow = layout.compactRow {
            HUDCompactRow(
                metrics: compactRow,
                phase: isTranscribing ? .transcribing : .recording,
                samples: samples,
                isOverloaded: isOverloaded,
                readout: compactReadout(compactRow),
                status: transcribingStatus,
                finishControl: .stopAndTranscribe(hint: stopHint, action: onStop)
            )
            .frame(height: HUDMetrics.controlRowHeight)
        } else {
            fullCard
        }
    }

    /// The pill keeps the clock and puts the counter in the spinner's tooltip;
    /// the bar has room to print it, in the clock's place.
    private func compactReadout(_ metrics: HUDCompactMetrics) -> HUDCompactRow.Readout {
        if isTranscribing, metrics.controls == .labels, let chunkProgress {
            return .counter(chunkProgress)
        }
        return .clock(clock)
    }

    private var transcribingStatus: String {
        chunkProgress.map { "Transcribing \($0)" } ?? "Transcribing"
    }

    /// Large: the dictation card's recording sections — the 56pt meter over the
    /// control row — with Stop & Transcribe where Finish would be.
    private var fullCard: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.gap) {
            LevelBars(samples: samples, isFrozen: isTranscribing, isOverloaded: isOverloaded)
                .frame(height: HUDMetrics.meterHeight)
                .frame(maxWidth: .infinity)

            HStack(spacing: Space.s4) {
                if isTranscribing {
                    // As the dictation card's transcribing row says it, with
                    // the chunk counter as its detail.
                    ShimmerText("Transcribing")
                        .typo(.headline)
                    if let chunkProgress {
                        Text(chunkProgress)
                            .typo(.mono)
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                } else {
                    HUDClock(text: clock)
                }
                Spacer(minLength: Space.s4)
                if isTranscribing {
                    HUDBusySlot(status: transcribingStatus, accessibilityLabel: "Transcribing") {
                        stopButton(action: {})
                    }
                } else {
                    stopButton(action: onStop)
                }
            }
            .frame(height: HUDMetrics.controlRowHeight)
        }
    }

    private func stopButton(action: @escaping () -> Void) -> some View {
        HUDButton(
            title: "Stop & Transcribe",
            systemImage: "stop.fill",
            hint: stopHint,
            role: .primary,
            action: action
        )
    }
}
