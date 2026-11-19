import SwiftUI

// MARK: - Root
//
// The conversation card is the dictation card's recording state and nothing
// else: one shape for both of its phases, laid out by `HUDLayout(recordingAt:)`
// and worn in the same chrome. Its controls are the two ways to end a
// recording that keep it: Stop & Transcribe, and Stop & Save beside it.

struct ConversationHUDView: View {
    @Bindable var state: ConversationHUDState
    /// Reports the card's laid-out size so the panel can size itself to it.
    let onCardSize: (CGSize) -> Void
    let onStop: () -> Void
    let onSave: () -> Void

    var body: some View {
        ConversationCard(state: state, onCardSize: onCardSize, onStop: onStop, onSave: onSave)
            .padding(HUDMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motionEnvironment()
    }
}

private struct ConversationCard: View {
    @Bindable var state: ConversationHUDState
    let onCardSize: (CGSize) -> Void
    let onStop: () -> Void
    let onSave: () -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        let layout = HUDLayout(recordingAt: state.size)
        let morph: Animation? = HUDFeatureFlags.morphEnabled ? motion.hudMorph : nil

        ConversationHUDContent(
            layout: layout,
            isTranscribing: state.isTranscribing,
            isSaving: state.isSaving,
            samples: state.levels,
            // The newest sample is the current level.
            isOverloaded: !state.isTranscribing && (state.levels.last ?? 0) > LevelBars.overloadThreshold,
            clock: state.elapsed.formattedClock,
            chunkProgress: state.chunkProgress,
            stopHint: HUDKeyHints.stopConversation,
            isPhoneListening: state.isPhoneListening,
            onStop: onStop,
            onSave: onSave
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
        .animation(morph, value: state.isPhoneListening)
        .modifier(HUDPresentation(presentationCount: state.presentationCount, isDismissing: state.isDismissing))
    }
}

// MARK: - Content

/// The conversation card's sections at any size, from plain values — the live
/// card passes the mirrored session, the Settings preview a sample phrase.
///
/// Recording: dot, meter, clock, Stop & Save and Stop & Transcribe.
/// Transcribing: the bars freeze, the dot greys, the clock holds the
/// recording's length, Stop & Save leaves and Stop's exact slot spins. Where
/// there is room for it the chunk counter says how far along a long recording
/// is. After Stop & Save the same busy card says Saving for the moment the
/// file takes to land.
struct ConversationHUDContent: View {
    let layout: HUDLayout
    let isTranscribing: Bool
    /// The busy phase is a Stop & Save filing its audio, not a transcription.
    var isSaving: Bool = false
    let samples: [Double]
    var isOverloaded: Bool = false
    /// The recording's length, `formattedClock`.
    let clock: String
    /// "3/12", or nil for a one-chunk recording.
    var chunkProgress: String?
    /// The conversation shortcut, when one is set.
    var stopHint: String?
    var isPhoneListening: Bool = false
    var onStop: () -> Void = {}
    var onSave: () -> Void = {}

    var body: some View {
        if let compactRow = layout.compactRow {
            HUDCompactRow(
                metrics: compactRow,
                phase: isTranscribing ? .transcribing : .recording,
                samples: samples,
                isOverloaded: isOverloaded,
                readout: compactReadout(compactRow),
                status: busyStatus,
                busyAccessibilityLabel: busyTitle,
                readoutBadge: isPhoneListening ? .phoneListening : nil,
                recordingControl: .stopAndSave(action: onSave),
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

    private var busyTitle: String {
        isSaving ? "Saving" : "Transcribing"
    }

    private var busyStatus: String {
        chunkProgress.map { "\(busyTitle) \($0)" } ?? busyTitle
    }

    /// Large: the dictation card's recording sections — the 56pt meter over the
    /// control row — with Stop & Save and Stop & Transcribe where Cancel and
    /// Finish would be.
    private var fullCard: some View {
        VStack(alignment: .leading, spacing: HUDMetrics.gap) {
            LevelBars(samples: samples, isFrozen: isTranscribing, isOverloaded: isOverloaded)
                .frame(height: HUDMetrics.meterHeight)
                .frame(maxWidth: .infinity)

            Group {
                if isTranscribing {
                    busyRow
                } else {
                    // The clock outgrows its slot past the hour and the stop
                    // hint is as long as the user's shortcut, so the row gives
                    // up names in order: the badge's first, then Stop & Save's.
                    ViewThatFits(in: .horizontal) {
                        recordingRow(namesBadge: true, namesSave: true)
                        recordingRow(namesBadge: false, namesSave: true)
                        recordingRow(namesBadge: false, namesSave: false)
                    }
                }
            }
            .frame(height: HUDMetrics.controlRowHeight)
        }
    }

    private func recordingRow(namesBadge: Bool, namesSave: Bool) -> some View {
        HStack(spacing: Space.s4) {
            HUDClock(text: clock)
                .fixedSize()
            if isPhoneListening {
                HUDReadoutBadge(badge: .phoneListening, showsTitle: namesBadge)
                    .fixedSize()
                    .transition(.opacity)
            }
            Spacer(minLength: Space.s4)
            saveButton(named: namesSave)
            stopButton(action: onStop)
                .fixedSize()
        }
    }

    /// As the dictation card's transcribing row says it, with the chunk
    /// counter as its detail.
    private var busyRow: some View {
        HStack(spacing: Space.s4) {
            ShimmerText(busyTitle)
                .typo(.headline)
            if let chunkProgress {
                Text(chunkProgress)
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: Space.s4)
            HUDBusySlot(status: busyStatus, accessibilityLabel: busyTitle) {
                stopButton(action: {})
            }
        }
    }

    @ViewBuilder
    private func saveButton(named: Bool) -> some View {
        if named {
            HUDButton(
                title: "Stop & Save",
                systemImage: "square.and.arrow.down",
                role: .secondary,
                action: onSave
            )
            .fixedSize()
            .help("Stop and keep the audio without transcribing it. Transcribe it later from History.")
        } else {
            HUDIconButton(
                title: "Stop & Save",
                systemImage: "square.and.arrow.down",
                role: .secondary,
                accessibilityLabel: "Stop and Save",
                action: onSave
            )
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
