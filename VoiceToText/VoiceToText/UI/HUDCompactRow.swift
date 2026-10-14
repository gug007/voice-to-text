import SwiftUI

// MARK: - Compact row
//
// Small and Medium draw a live take as ONE row where Large stacks a meter over
// a control row: dot, meter, readout, then the controls. It is the same row
// from preparing through recording to transcribing — only the leading content
// and the finish slot change — so nothing to the left of that slot ever moves
// while the take is live.
//
// The row takes plain values, never a HUD's state object, which is what lets
// both cards share it — the dictation HUD (Cancel + Finish) and the
// conversation HUD (Stop & Transcribe alone) — and lets Settings preview the
// very view the live card draws by feeding it a sample phrase.

struct HUDCompactRow: View {
    enum Phase: Equatable {
        /// The model is being fetched or loaded. `percent` is "42%", or empty
        /// until the registry reports a fraction.
        case preparing(percent: String)
        case recording
        /// The meter freezes where it stopped and the finish slot spins.
        case transcribing
    }

    /// What sits between the meter and the controls.
    enum Readout: Equatable {
        /// The take's length, in the HUD clock's register.
        case clock(String)
        /// Chunk progress, "3/12", in the machine register the full cards
        /// print it in.
        case counter(String)
    }

    /// One trailing control. A circle on the pill, a named capsule on the bar.
    struct Control {
        let title: String
        let systemImage: String
        var hint: String?
        var role: GlassButtonStyle.Role = .secondary
        /// What VoiceOver says for the pill's circle, when the title reads
        /// badly aloud. The title otherwise.
        var accessibilityLabel: String?
        let action: () -> Void
    }

    let metrics: HUDCompactMetrics
    let phase: Phase
    let samples: [Double]
    var isOverloaded: Bool = false
    let readout: Readout
    /// What the card is waiting on — the model and its phase while preparing,
    /// a model download or "Transcribing" after Finish. The Large card spells
    /// this out in its own rows; here it is the tooltip.
    var status: String = ""
    /// Before the finish slot in every phase, in the same spot: the dictation
    /// card's Cancel. Nil on the conversation card, which has no Cancel on
    /// purpose — one stray click must not throw away an hour of meeting.
    var persistentControl: Control?
    /// Finish, or Stop & Transcribe. Live only while recording.
    let finishControl: Control

    var body: some View {
        HStack(spacing: Space.s4) {
            switch phase {
            case .preparing(let percent):
                preparingLabel(percent: percent)
            case .recording, .transcribing:
                RecordingPulse(isLive: phase == .recording)
                LevelBars(
                    samples: samples,
                    isFrozen: phase == .transcribing,
                    isOverloaded: isOverloaded,
                    barCount: metrics.meterBars,
                    barSpacing: metrics.meterSpacing,
                    window: metrics.meterWindow
                )
                .frame(height: metrics.meterHeight)
                .frame(maxWidth: .infinity)
                readoutView
                    // The meter gives way, never the readout: a conversation's
                    // clock grows to "1:02:33" past the hour.
                    .fixedSize()
            }

            HStack(spacing: metrics.controlSpacing) {
                if let persistentControl {
                    control(persistentControl)
                }
                finishSlot
            }
            // Same rule as the readout: the buttons keep their natural width.
            // Left flexible, the bar's capsules split the meter's share and
            // "Cancel" truncated to "Can…".
            .fixedSize()
        }
    }

    @ViewBuilder
    private var readoutView: some View {
        switch readout {
        case .clock(let text):
            HUDClock(text: text)
        case .counter(let text):
            Text(text)
                .typo(.mono)
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    /// Neutral verb plus progress, as the Large card's control row says it;
    /// which model and which phase are in the tooltip.
    private func preparingLabel(percent: String) -> some View {
        HStack(spacing: Space.s4) {
            ShimmerText("Preparing")
                .typo(.headline)
            Text(percent)
                .typo(.mono)
                .foregroundStyle(Palette.inkFaint)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(status)
    }

    /// The finish control while recording; before and after, its exact
    /// footprint with a spinner in it (see `HUDBusySlot` for why it is never
    /// an empty gap). The stand-in only holds the slot: the real control
    /// leaving must not morph into it.
    @ViewBuilder
    private var finishSlot: some View {
        if phase == .recording {
            control(finishControl)
        } else {
            HUDBusySlot(status: status, accessibilityLabel: isPreparing ? "Preparing" : "Transcribing") {
                control(finishControl, action: {})
            }
        }
    }

    /// Neither shape prints its key hint — there is no room for one — so both
    /// carry it in the tooltip.
    @ViewBuilder
    private func control(_ control: Control, action: (() -> Void)? = nil) -> some View {
        switch metrics.controls {
        case .icons:
            HUDIconButton(
                title: control.title,
                systemImage: control.systemImage,
                hint: control.hint,
                role: control.role,
                accessibilityLabel: control.accessibilityLabel,
                action: action ?? control.action
            )
        case .labels:
            HUDButton(title: control.title, role: control.role, radius: metrics.controlRadius, action: action ?? control.action)
                .hudHelp(control.title, hint: control.hint)
        }
    }

    private var isPreparing: Bool {
        if case .preparing = phase { return true }
        return false
    }
}

// MARK: - The controls each card offers

extension HUDCompactRow.Control {
    /// Dictation: the way out of a stalled download, a recording or a hung
    /// cloud request.
    static func cancel(hint: String?, action: @escaping () -> Void) -> Self {
        Self(title: "Cancel", systemImage: "xmark", hint: hint, role: .secondary, action: action)
    }

    static func finish(hint: String?, action: @escaping () -> Void) -> Self {
        Self(title: "Finish", systemImage: "checkmark", hint: hint, role: .primary, action: action)
    }

    /// Conversations: the card's only control.
    static func stopAndTranscribe(hint: String?, action: @escaping () -> Void) -> Self {
        Self(
            title: "Stop & Transcribe",
            systemImage: "stop.fill",
            hint: hint,
            role: .primary,
            accessibilityLabel: "Stop and Transcribe",
            action: action
        )
    }
}
