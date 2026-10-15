import AppKit
import SwiftUI

// MARK: - Root
//
// ONE CARD, ONE STACK. Every mode is a subset of the same vertical stack, in
// the same order, inside the same rounded rectangle. Nothing switches on the
// mode at the top level, which is what makes the morph continuous: the meter is
// literally the same view going into transcribing (so its bars freeze in place
// rather than being replaced by unrelated dots) and the control row is the same
// view in every state (so Cancel never jumps).

struct LiveHUDView: View {
    @Bindable var state: LiveHUDState
    /// Reports the card's laid-out size so the panel can size itself to it.
    let onCardSize: (CGSize) -> Void

    var body: some View {
        HUDCard(state: state, onCardSize: onCardSize)
            .padding(HUDMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motionEnvironment()
    }
}

// MARK: - The card

private struct HUDCard: View {
    @Bindable var state: LiveHUDState
    let onCardSize: (CGSize) -> Void

    @Environment(\.motion) private var motion

    /// Identity carried across the morph.
    @Namespace private var hudNamespace

    private var layout: HUDLayout { HUDLayout(state: state) }

    var body: some View {
        let layout = self.layout
        let morph: Animation? = HUDFeatureFlags.morphEnabled ? motion.hudMorph : nil

        sections(layout)
            .padding(layout.contentInsets)
            .frame(width: layout.width)
            // The card's height is its content's, never the panel's: the panel
            // is sized FROM this, so it must not be sized BY it.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: layout.minHeight)
            .modifier(HUDCardChrome(layout: layout, placement: LiveHUDPanel.shared.placement))
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onCardSize)
            .animation(morph, value: layout)
            .animation(morph, value: state.reviewBanner)
            .modifier(HUDPresentation(presentationCount: state.presentationCount))
    }

    // MARK: Sections

    @ViewBuilder
    private func sections(_ layout: HUDLayout) -> some View {
        VStack(alignment: .leading, spacing: HUDMetrics.gap) {
            if let message = bannerMessage {
                HUDBanner(
                    message: message,
                    showsRetry: hasBannerRetry,
                    actionTitle: bannerActionTitle,
                    actionIcon: state.secondaryActionIcon,
                    onAction: { state.click(state.onSecondaryAction) }
                ) {
                    performBannerRetry()
                }
                    .transition(.opacity)
            }

            if layout.showsPreparing {
                HUDPreparingBlock(state: state)
                    // Sized to absorb the card's slack, so the model name starts
                    // on the top inset and the control row stays on the bottom.
                    .frame(height: layout.preparingHeight, alignment: .topLeading)
            }

            if layout.showsMeter {
                // While the take waits on its model, the meter's slot says
                // which model and how far along — the preparing card's block,
                // which fits the slot exactly, so nothing around it moves.
                Group {
                    if let phase = modelWaitPhase {
                        HUDPreparingBlock(state: state, phase: phase)
                            .frame(height: HUDMetrics.meterHeight, alignment: .topLeading)
                            .transition(.opacity)
                    } else {
                        LevelBars(
                            samples: state.levelHistory,
                            isFrozen: state.mode == .transcribing,
                            isOverloaded: state.level > LevelBars.overloadThreshold
                        )
                        .frame(height: HUDMetrics.meterHeight)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                    }
                }
                .animation(motion.layout, value: modelWaitPhase == nil)
            }

            if layout.showsStreamText {
                StreamingTranscript(state: state)
                    .frame(height: HUDMetrics.streamTextHeight)
            }

            if layout.showsResumeTranscript {
                ResumeTranscript(state: state)
                    // Sized to absorb the card's slack, so the transcript starts
                    // on the top inset exactly where review's editor did.
                    .frame(height: layout.resumeTranscriptHeight)
            }

            if layout.showsInlineMeter {
                // Carries straight through into transcribing: same row, same
                // slot, bars and dot desaturating in place. Nothing moves.
                let isFrozen = state.mode == .transcribing
                HStack(spacing: HUDMetrics.gap) {
                    RecordingPulse(isLive: !isFrozen)
                    LevelBars(
                        samples: state.levelHistory,
                        isFrozen: isFrozen,
                        isOverloaded: state.level > LevelBars.overloadThreshold
                    )
                    .frame(maxWidth: .infinity)
                    HUDClock(seconds: state.elapsedSeconds)
                }
                .frame(height: HUDMetrics.inlineMeterHeight)
            }

            if layout.showsEditor {
                ReviewTextEditor(text: $state.reviewText, state: state)
                    .frame(height: HUDMetrics.editorHeight)
                    .frame(maxWidth: .infinity)
                    // A long transcript must not collide with the banner above
                    // or the chip row below.
                    .mask { EdgeFade() }
            }

            if layout.showsEmptyState {
                Text(state.failureDetail ?? emptyStateLine(layout))
                    .typo(.body)
                    .foregroundStyle(Palette.inkMuted)
                    // Sized to absorb the card's slack, so the control row still
                    // sits on the bottom edge exactly where review put it.
                    .frame(height: layout.emptyStateHeight, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if layout.showsChipRow {
                HUDActionChipRow(state: state)
                    .frame(height: HUDMetrics.chipRowHeight)
                    .transition(.opacity)
            }

            if let compactRow = layout.compactRow {
                // Small and Medium: the whole card is this one row, in the
                // control row's slot and at its height.
                compactRowView(compactRow)
                    .frame(height: HUDMetrics.controlRowHeight)
            } else {
                HUDControlRow(state: state, layout: layout, namespace: hudNamespace)
                    .frame(height: HUDMetrics.controlRowHeight)
            }
        }
    }

    // MARK: Compact row

    private func compactRowView(_ metrics: HUDCompactMetrics) -> some View {
        HUDCompactRow(
            metrics: metrics,
            phase: compactPhase,
            samples: state.levelHistory,
            isOverloaded: state.level > LevelBars.overloadThreshold,
            readout: .clock(HUDClock.text(seconds: state.elapsedSeconds)),
            status: compactStatus,
            persistentControl: .cancel(hint: HUDKeyHints.escCancel) { state.click(state.onCancel) },
            finishControl: .finish(hint: HUDKeyHints.finish) { state.click(state.onStop) }
        )
    }

    private var compactPhase: HUDCompactRow.Phase {
        switch state.mode {
        case .preparing: return .preparing(percent: HUDPreparingBlock.percent(state.preparingFraction))
        case .transcribing: return .transcribing
        case .recording, .resumeRecording, .reviewing, .failed, .discarded: return .recording
        }
    }

    /// The compact row's tooltip: what the Large card's preparing block would
    /// say, on one or two lines. A transcribing take that is waiting on its
    /// model names the model and how far along it is.
    private var compactStatus: String {
        switch state.mode {
        case .preparing:
            let title = HUDPreparingBlock.title(
                modelName: state.preparingModelName,
                message: state.preparingMessage
            )
            return state.preparingMessage.isEmpty ? title : "\(title)\n\(state.preparingMessage)"
        case .transcribing:
            guard let phase = state.transcribingWaitPhase else { return "Transcribing" }
            let title = HUDPreparingBlock.title(
                modelName: state.preparingModelName,
                message: state.preparingMessage,
                phase: phase
            )
            return FailureCardCopy.percent(state.preparingFraction).map { "\(title) · \($0)" } ?? title
        case .recording, .resumeRecording, .reviewing, .failed, .discarded:
            return ""
        }
    }

    /// What the failure card says it kept: nothing, or how much it captured
    /// and whether that is in History. Said both ways, because the one a
    /// user can't afford to guess is "not": a take the speech gate turned
    /// away lives only on this card, and closing it lets the audio go.
    private func emptyStateLine(_ layout: HUDLayout) -> String {
        guard layout.hasSalvagedAudio else { return "Nothing to review." }
        let captured = Self.capturedDuration(layout.salvagedSeconds)
        return state.failureSavedToHistory
            ? "\(captured) captured — saved to History."
            : "\(captured) captured — not saved."
    }

    /// "Downloading" or "Loading" while a transcribing take waits on its
    /// model; nil otherwise, in every mode.
    private var modelWaitPhase: String? {
        state.mode == .transcribing ? state.transcribingWaitPhase : nil
    }

    /// Tenths below a minute, where the difference between 0.3s and 8.6s is
    /// the whole point; the clock format above it, because "180.0s captured."
    /// is a number to decode rather than a duration to read. This line shows
    /// under every failure card, not just an interrupted one — including an
    /// ordinary long take that tripped the speech gate.
    private static func capturedDuration(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.1fs", seconds) : seconds.formattedClock
    }

    // MARK: Banner

    /// One banner vocabulary. A resumed take that produced nothing shows it over
    /// the transcript; a hard failure shows it over the empty state — same 34pt
    /// row, same tint, same Retry affordance. The standalone failure panel is
    /// gone.
    private var bannerMessage: String? {
        switch state.mode {
        case .failed: return state.failureMessage
        case .reviewing, .resumeRecording: return state.reviewBanner
        case .preparing, .recording, .transcribing, .discarded: return nil
        }
    }

    /// Only the review banner carries its own Retry. In `.failed` the control
    /// row owns the card's actions (and Return is bound to the primary one
    /// there), so putting one in the banner too would offer the same action
    /// twice in the same card.
    private var hasBannerRetry: Bool {
        switch state.mode {
        case .reviewing, .resumeRecording: return state.onRetry != nil
        case .failed, .preparing, .recording, .transcribing, .discarded: return false
        }
    }

    /// The review banner's own extra action, for a failed Resume take. In
    /// `.failed` the control row carries it, as it carries Retry.
    private var bannerActionTitle: String? {
        switch state.mode {
        case .reviewing, .resumeRecording: return state.secondaryActionTitle
        case .failed, .preparing, .recording, .transcribing, .discarded: return nil
        }
    }

    private func performBannerRetry() {
        state.click(state.onRetry)
    }
}

// MARK: - Card chrome
//
// What makes content a HUD card, shared by the dictation card and the
// conversation card so the two panels can never look or move differently.

/// The drag surface behind the content, the hover grabber, the clip, the glass
/// with its elevation, and the concentric radius for whatever sits inside —
/// all at the layout's corner radius, so a card that changes shape turns its
/// corners on the same spring as its size.
struct HUDCardChrome: ViewModifier {
    let layout: HUDLayout
    let placement: HUDPanelPlacement

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background { HUDDragSurface(cornerRadius: layout.cornerRadius, placement: placement) }
            .overlay(alignment: .top) {
                // Not on a compact row: 4pt above the bars of a 40pt pill, a
                // 2pt line reads as part of the meter rather than as a handle,
                // and the whole capsule is a drag surface anyway.
                if layout.compactRow == nil { HUDGrabber(isVisible: isHovering) }
            }
            // The chip row deliberately overhangs its slot by 20pt on each side
            // so its fade band can start outside the content box (see
            // `HUDActionChipRow`). Without this clip a scrolled-away chip would
            // render faintly *outside* the card, floating on the desktop.
            .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
            .glassCard(cornerRadius: layout.cornerRadius, reduceTransparency: reduceTransparency)
            // Radius 22 published for the concentric law: every control inside
            // the 12pt inset derives 22 − 12 = 10 with no literal anywhere. A
            // compact row publishes its capsule's radius instead.
            .environment(\.plateRadius, layout.cornerRadius)
            .onHover { isHovering = $0 }
    }
}

/// Entrance — scale 0.92→1, opacity 0→1, y +8→0 — on `hudEnter`, replayed
/// whenever `presentationCount` changes: `onAppear` fires once per hosting
/// view, and the hosting view outlives every session. Dismissal — scale
/// 1→0.96, opacity → 0 — plays on whatever animation the panel sets
/// `isDismissing` inside, `hudExit`. Under Reduce Motion the scale holds at 1
/// and only the opacity moves.
struct HUDPresentation: ViewModifier {
    let presentationCount: Int
    var isDismissing: Bool = false

    @Environment(\.motion) private var motion
    @State private var entered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: entered ? 0 : 8)
            .opacity(entered && !isDismissing ? 1 : 0)
            .onAppear { playEntrance() }
            .onChange(of: presentationCount) { playEntrance() }
    }

    private var scale: CGFloat {
        if motion.reduceMotion { return 1 }
        if isDismissing { return 0.96 }
        return entered ? 1 : 0.92
    }

    private func playEntrance() {
        entered = false
        // One turn later: setting both ends of the transition in a single
        // update coalesces them and nothing animates.
        Task { @MainActor in
            withAnimation(motion.hudEnter) { entered = true }
        }
    }
}

/// The card is a drag region. This layer sits BEHIND the content, so
/// buttons, chips and the text view take their clicks first and only the
/// chrome between them starts a drag. A double-click sends the card home.
struct HUDDragSurface: View {
    let cornerRadius: CGFloat
    let placement: HUDPanelPlacement

    @State private var isDragging = false

    var body: some View {
        Color.clear
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture(count: 2) { placement.resetPosition() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        if !isDragging {
                            isDragging = true
                            placement.dragBegan()
                        }
                        placement.dragChanged()
                    }
                    .onEnded { _ in
                        isDragging = false
                        placement.dragEnded()
                    }
            )
    }
}

/// 2 × 28pt grabber at the top centre, on hover only.
struct HUDGrabber: View {
    let isVisible: Bool

    @Environment(\.motion) private var motion

    var body: some View {
        Capsule()
            .fill(Palette.inkFaint.opacity(isVisible ? 0.25 : 0))
            .frame(width: 28, height: 2)
            .padding(.top, 5)
            .allowsHitTesting(false)
            .animation(motion.hover, value: isVisible)
    }
}

extension View {
    /// The HUD's glass, its hairline and its L3 elevation.
    ///
    /// On macOS 26 the card is wrapped in a `GlassEffectContainer` and carries a
    /// `glassEffectID`, so the system morphs the glass shape itself as the card
    /// resizes. Below 26 (and under Reduce Transparency) `glassSurface` falls
    /// back to `.regularMaterial` / an opaque fill, and the shape simply
    /// animates with the frame — radius included, which is what turns a pill's
    /// capsule ends into the review card's corners.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat, reduceTransparency: Bool) -> some View {
        if #available(macOS 26, *) {
            HUDGlassContainer(cornerRadius: cornerRadius) { self }
                .hudElevation(cornerRadius: cornerRadius, reduceTransparency: reduceTransparency)
        } else {
            glassSurface(cornerRadius: cornerRadius, opaqueFill: Palette.canvas)
                .hudElevation(cornerRadius: cornerRadius, reduceTransparency: reduceTransparency)
        }
    }

    func hudElevation(cornerRadius: CGFloat, reduceTransparency: Bool) -> some View {
        modifier(HUDElevation(cornerRadius: cornerRadius, reduceTransparency: reduceTransparency))
    }
}

@available(macOS 26, *)
private struct HUDGlassContainer<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            content
                .glassSurface(cornerRadius: cornerRadius, opaqueFill: Palette.canvas)
                .glassEffectID("hud", in: namespace)
                .glassEffectTransition(.matchedGeometry)
        }
    }
}

/// L3: `0 16px 48px rgba(0,0,0,0.30)` + `0 2px 6px rgba(0,0,0,0.14)`, reduced
/// under Reduce Transparency. Drawn as a masked background rather than a
/// `.shadow` on the card, so it shadows the CARD and not the text on it.
private struct HUDElevation: ViewModifier {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content.background { shadow }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var shadow: some View {
        shape
            .fill(Color.black)
            .shadow(
                color: .black.opacity(reduceTransparency ? 0.24 : 0.30),
                radius: reduceTransparency ? 9 : 24,
                y: reduceTransparency ? 6 : 16
            )
            .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
            .compositingGroup()
            // Keep the shadow, punch out the card's own footprint — the black
            // proxy must never show through translucent glass.
            .mask {
                Rectangle()
                    .inset(by: -HUDMetrics.gutter * 2)
                    .fill(Color.black)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }
}

/// Top and bottom fade on the review editor, so a long transcript dissolves
/// into the card instead of colliding with the banner above or the chip row
/// below. Matched to `ReviewTextEditor`'s text-container inset: at rest the
/// first and last lines sit clear of the gradient, so a short transcript is
/// never dimmed.
private struct EdgeFade: View {
    static let height: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.height)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.height)
        }
    }
}

// MARK: - Control row

/// The one control row, present in every mode. Cancel and the primary action
/// carry `matchedGeometryEffect` identities, so when review moves Cancel from
/// the trailing group to the leading edge it slides instead of popping.
private struct HUDControlRow: View {
    @Bindable var state: LiveHUDState
    let layout: HUDLayout
    let namespace: Namespace.ID

    @Environment(\.motion) private var motion

    var body: some View {
        HStack(spacing: Space.s4) {
            switch layout.mode {
            case .preparing:
                // Neutral verb: the block above names the phase precisely
                // ("Downloading 3/12 files", "Compiling…"), so this row only has
                // to say the app is working and how far along it is.
                ShimmerText("Preparing")
                    .typo(.headline)
                Text(preparingDetail)
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
                Spacer(minLength: Space.s4)
                // Nothing to finish yet, but a stalled download has to have a
                // way out — the hotkey policy already maps this to
                // `cancelPendingRecording`, so Cancel keeps its `esc` hint.
                cancelButton(title: "Cancel", hint: escCancelHint)

            case .recording, .resumeRecording:
                if !layout.showsInlineMeter {
                    HUDClock(seconds: state.elapsedSeconds)
                }
                Spacer(minLength: Space.s4)
                cancelButton(title: "Cancel", hint: escCancelHint)
                primaryButton(title: "Finish", hint: finishHint) { state.click(state.onStop) }

            case .transcribing:
                if let phase = state.transcribingWaitPhase {
                    // Waiting on the model, not transcribing yet: the elapsed
                    // clock would count the download as transcription time.
                    // On the compact card the name drops out first.
                    ShimmerText(phase)
                        .typo(.headline)
                    ViewThatFits(in: .horizontal) {
                        transcribingDetailText(modelWaitDetail)
                        transcribingDetailText(FailureCardCopy.percent(state.preparingFraction) ?? "")
                    }
                } else {
                    ShimmerText("Transcribing")
                        .typo(.headline)
                    // Finish's slot below costs the row its slack: with a long
                    // hotkey hint, chunk progress drops out before anything wraps.
                    ViewThatFits(in: .horizontal) {
                        transcribingDetailText(transcribingDetail)
                        transcribingDetailText(transcribingElapsed)
                    }
                }
                Spacer(minLength: Space.s4)
                // A hung cloud request has to have a way out, so Cancel stays,
                // with the same `esc` hint recording showed. Finish has nothing
                // left to finish, but its slot is held by an invisible stand-in
                // of the same size: without it Cancel slid right into the spot
                // Finish had just left, and the second click of a double-click
                // on Finish cancelled the take it had just finished.
                cancelButton(title: "Cancel", hint: escCancelHint)
                finishSlot

            case .reviewing:
                cancelButton(title: "Cancel", hint: "esc")
                Spacer(minLength: Space.s4)
                if !state.actionRevertStack.isEmpty, state.runningActionId == nil {
                    HUDButton(
                        title: "Undo",
                        systemImage: "arrow.uturn.backward",
                        role: .secondary
                    ) { state.click { state.undoLastAction() } }
                        .help("Undo last action")
                        .transition(.opacity)
                }
                HUDButton(
                    title: "Resume",
                    systemImage: "mic.fill",
                    hint: "⌘R",
                    role: .accent
                ) { state.click(state.onResume) }
                primaryButton(
                    title: "Paste",
                    hint: HotkeyStore.shared.binding.displayKeys.joined()
                ) { state.click(state.onPaste) }

            case .failed:
                Spacer(minLength: Space.s4)
                if let secondaryTitle = state.secondaryActionTitle {
                    HUDButton(
                        title: secondaryTitle,
                        systemImage: state.secondaryActionIcon,
                        role: .secondary
                    ) { state.click(state.onSecondaryAction) }
                }
                // Esc in the key card always closes it, whatever "Esc cancels
                // dictation" says — that setting is about Esc in other apps.
                cancelButton(title: "Close", hint: "esc")
                if let actionTitle = state.failureActionTitle {
                    primaryButton(
                        title: actionTitle,
                        systemImage: state.failureActionIcon,
                        hint: state.failureActionHint
                    ) { state.click(state.onRetry) }
                }

            case .discarded:
                Text(state.noticeMessage)
                    .typo(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Space.s4)
                // Same identity as the primary action it replaces, so the
                // button slides out of the review card instead of popping.
                if state.noticeOffersUndo {
                    primaryButton(title: "Undo", systemImage: "arrow.uturn.backward", hint: nil) {
                        state.click(state.onUndo)
                    }
                }
            }
        }
        .animation(motion.layout, value: state.actionRevertStack.count)
    }

    private func cancelButton(title: String, hint: String?) -> some View {
        HUDButton(title: title, hint: hint, role: .secondary) { state.click(state.onCancel) }
            .matchedGeometryEffect(id: "hud.cancel", in: namespace)
    }

    private var escCancelHint: String? { HUDKeyHints.escCancel }

    private func primaryButton(
        title: String,
        systemImage: String? = nil,
        hint: String?,
        action: @escaping () -> Void
    ) -> some View {
        HUDButton(title: title, systemImage: systemImage, hint: hint, role: .primary, action: action)
            .matchedGeometryEffect(id: "hud.primary", in: namespace)
    }

    /// Finish's exact footprint with nothing in it. Deliberately without the
    /// primary action's geometry identity: it only holds the slot, and the
    /// real Finish leaving must not morph into it.
    private var finishSlot: some View {
        HUDButton(title: "Finish", hint: finishHint, role: .primary) {}
            .hidden()
            .disabled(true)
            .accessibilityHidden(true)
    }

    private var finishHint: String? { HUDKeyHints.finish }

    private var transcribingDetail: String {
        guard let progress = state.transcribingProgress else { return transcribingElapsed }
        return "\(progress.current) / \(progress.total) · \(transcribingElapsed)"
    }

    private var transcribingElapsed: String {
        String(format: "%0.1fs", state.transcribingElapsedSeconds)
    }

    /// "Parakeet TDT v3 · 42%", or the name alone while there is no fraction
    /// to show.
    private var modelWaitDetail: String {
        FailureCardCopy.downloadProgress(modelName: state.preparingModelName, fraction: state.preparingFraction)
    }

    private func transcribingDetailText(_ detail: String) -> some View {
        Text(detail)
            .typo(.mono)
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
            .contentTransition(.numericText())
    }

    private var preparingDetail: String {
        HUDPreparingBlock.percent(state.preparingFraction)
    }
}

// MARK: - Preparing

/// What the card shows while the model is fetched or loaded: which model, which
/// phase, how far along. This is the surface that used to not exist — a first
/// run spent the whole 470MB download with nothing on screen but a menu-bar
/// glyph, which reads as a dead hotkey.
private struct HUDPreparingBlock: View {
    @Bindable var state: LiveHUDState
    /// The phase to name — "Downloading", "Loading" — when the caller has
    /// already worked it out; nil reads it off the engine's message.
    var phase: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title)
                .typo(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

            HUDProgressBar(fraction: state.preparingFraction)

            Text(state.preparingMessage)
                .typo(.caption)
                .foregroundStyle(Palette.inkMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var title: String {
        Self.title(modelName: state.preparingModelName, message: state.preparingMessage, phase: phase)
    }

    /// The phase message is the engine's own text, so the verb is read back off
    /// it rather than tracked separately — a compile that follows a download
    /// must not keep claiming to be downloading. Shared with the compact row's
    /// tooltip, which says the same thing without the room for this block.
    static func title(modelName name: String, message: String, phase: String? = nil) -> String {
        guard !name.isEmpty else { return "Preparing model" }
        if let phase { return "\(phase) \(name)" }
        if message.localizedCaseInsensitiveContains("download") {
            return "Downloading \(name)"
        }
        return "Loading \(name)"
    }

    /// Blank until the registry reports its first sample — an honest "we don't
    /// know yet" beats a 0% that looks like a stalled download.
    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "" }
        return "\(Int((fraction * 100).rounded()))%"
    }
}

/// 4pt track. Determinate once the registry reports a fraction; before that a
/// sweep runs across the track so a phase that reports nothing still looks
/// alive. Flat and static under Reduce Motion.
private struct HUDProgressBar: View {
    let fraction: Double?

    @Environment(\.motion) private var motion
    @State private var sweep: CGFloat = -1

    private static let height: CGFloat = 4
    private static let sweepWidth: CGFloat = 0.35

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.10))

                if let fraction {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                        .animation(motion.layout, value: fraction)
                } else if motion.repeatsAllowed {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: geo.size.width * Self.sweepWidth)
                        .offset(x: sweep * geo.size.width)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 1.1).repeatForever(autoreverses: false)
                            ) {
                                sweep = 1
                            }
                        }
                } else {
                    Capsule()
                        .fill(Palette.accent.opacity(0.5))
                        .frame(width: geo.size.width * Self.sweepWidth)
                }
            }
            // The sweep travels a full width past each edge; without this it
            // would paint outside the track and across the card.
            .clipShape(Capsule())
        }
        .frame(height: Self.height)
        .accessibilityLabel("Model preparation progress")
    }
}

/// SF Mono 13/medium, digits rolling rather than popping. Shared with the
/// compact rows, the conversation card and the Settings previews, so every
/// card keeps one clock.
struct HUDClock: View {
    let text: String

    /// A dictation take: minutes and seconds, however long it runs.
    init(seconds: Double) {
        text = Self.text(seconds: seconds)
    }

    /// Already formatted — a conversation's `formattedClock`, which grows an
    /// hours field past the hour.
    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .typo(.clock)
            .foregroundStyle(Palette.inkFaint)
            .contentTransition(.numericText())
    }

    static func text(seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Streaming / resumed transcript

/// Placeholder + live partial for streaming engines. The three-line height is
/// reserved by a hidden sizer so the card never reflows word by word.
private struct StreamingTranscript: View {
    @Bindable var state: LiveHUDState
    @Environment(\.motion) private var motion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("\n\n")
                .typo(.body)
                .lineLimit(3, reservesSpace: true)
                .hidden()

            if state.partialTranscript.isEmpty {
                ListeningIndicator()
                    .transition(.opacity)
            } else {
                Text(state.partialTranscript)
                    .typo(.body)
                    .foregroundStyle(Palette.ink.opacity(0.88))
                    .lineLimit(3, reservesSpace: true)
                    .truncationMode(.head)
                    .multilineTextAlignment(.leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(motion.hover, value: state.partialTranscript)
    }
}

/// The transcript the user was reviewing, kept on screen while a resumed take
/// streams new words in at the caret.
private struct ResumeTranscript: View {
    @Bindable var state: LiveHUDState
    @Environment(\.motion) private var motion

    private static let bottomAnchor = "resume-transcript-end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    composed
                        .typo(.transcript)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, ReviewTextEditor.lineFragmentPadding)
                        .padding(.vertical, ReviewTextEditor.verticalTextInset)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
            }
            .onChange(of: state.partialTranscript) {
                withAnimation(motion.hover) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Prior transcript in `ink`; the in-progress dictation streams in
    /// `inkMuted` at the caret so it's clear where the new words will land and
    /// that they are not final yet. Buffered engines emit no partial, so the
    /// prior text simply stays put.
    private var composed: Text {
        var result = Text(state.recordingPrefix).foregroundColor(Palette.ink)
        if !state.partialTranscript.isEmpty {
            if needsLeadingSpace { result = result + Text(" ") }
            result = result + Text(state.partialTranscript).foregroundColor(Palette.inkMuted)
        }
        result = result + Text(state.recordingSuffix).foregroundColor(Palette.ink)
        return result
    }

    private var needsLeadingSpace: Bool {
        guard let last = state.recordingPrefix.last,
              let first = state.partialTranscript.first else { return false }
        return !last.isWhitespace && !first.isWhitespace
    }
}

// MARK: - Action chips

/// Chips between the review editor and the control row. Clicking one (or
/// ⌘1–⌘9) sends the transcript through the action's transform; the running chip
/// shimmers and the rest disable until the request settles.
private struct HUDActionChipRow: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s3) {
                ForEach(Array(state.reviewActions.enumerated()), id: \.element.id) { index, action in
                    HUDActionChip(
                        title: action.name,
                        hint: index < 9 ? "⌘\(index + 1)" : nil,
                        isRunning: state.runningActionId == action.id,
                        isDisabled: state.runningActionId != nil && state.runningActionId != action.id
                    ) { state.click { state.onRunAction?(action) } }
                }
            }
            .padding(.horizontal, HUDActionChipRow.fadeWidth)
        }
        // OVERFLOW: the row used to cut chips off invisibly. A 20pt gradient
        // mask on each edge makes a cut-off chip look cut off.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fadeWidth)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fadeWidth)
            }
        }
        .padding(.horizontal, -Self.fadeWidth)
    }

    static let fadeWidth: CGFloat = 20
}

// MARK: - Review editor

/// NSTextView-backed editor: we need the caret position when Resume is
/// pressed so the next transcription can be spliced in at the cursor.
/// SwiftUI's TextEditor doesn't expose a selection binding on macOS in a way
/// that survives panel focus changes, so we wrap an NSTextView directly.
private struct ReviewTextEditor: NSViewRepresentable {
    @Binding var text: String
    let state: LiveHUDState

    /// Where the editor's text sits inside its frame. `ResumeTranscript` pads
    /// by the same amounts, so the text doesn't jump when the card switches
    /// between review and a resumed take.
    static let verticalTextInset: CGFloat = 12
    static let lineFragmentPadding: CGFloat = 5

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FocusOnAttachTextView.scrollableTextView()
        Self.configureScrollView(scrollView)
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        Self.configureTextView(textView, delegate: context.coordinator)
        textView.string = text
        textView.setSelectedRange(clampedRange(state.selectedRange, in: text))
        context.coordinator.lastSyncedText = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Skip resync when nothing came in from the outside — otherwise we'd
        // clobber the user's caret on every keystroke (textDidChange writes
        // through the binding, which triggers updateNSView).
        guard textView.string != text, context.coordinator.lastSyncedText != text else {
            return
        }
        textView.breakUndoCoalescing()
        textView.string = text
        // The replacement bypassed the undo machinery, so recorded operations
        // now target ranges in text that no longer exists — replaying them
        // would corrupt the transcript or raise NSRangeException.
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(clampedRange(state.selectedRange, in: text))
        context.coordinator.lastSyncedText = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(range.location, length))
        let extent = max(0, min(range.length, length - location))
        return NSRange(location: location, length: extent)
    }

    /// Takes first responder the moment it lands in the panel. SwiftUI calls
    /// `makeNSView` before inserting the view, and the insertion can trail the
    /// next main-queue turn, so focusing "on the next run loop" found no window
    /// and left the panel itself as first responder: Return, typing and
    /// Shift+Return went nowhere until the user clicked into the text.
    private final class FocusOnAttachTextView: NSTextView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }

    private static func configureTextView(_ textView: NSTextView, delegate: NSTextViewDelegate) {
        textView.delegate = delegate
        // The Transcript register: SF Pro 15 / line-height 21, in `ink` — not
        // white-on-black. This is the largest body text in the app.
        textView.font = .systemFont(ofSize: 15)
        // Keeps the first and last lines out of the scroll-edge gradient.
        textView.textContainerInset = NSSize(width: 0, height: verticalTextInset)
        textView.textContainer?.lineFragmentPadding = lineFragmentPadding
        textView.textColor = Palette.inkNS
        textView.insertionPointColor = Palette.accentNS
        textView.selectedTextAttributes = [
            .backgroundColor: Palette.accentNS.withAlphaComponent(0.22)
        ]
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
    }

    private static func configureScrollView(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReviewTextEditor
        /// Last text we either sent to or received from the NSTextView.
        /// Lets `updateNSView` distinguish "user just typed" from "binding
        /// changed externally" and skip self-inflicted refreshes.
        var lastSyncedText: String = ""

        init(parent: ReviewTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lastSyncedText = textView.string
            parent.text = textView.string
            parent.state.selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.state.selectedRange = textView.selectedRange()
        }

        /// Return pastes; Shift+Return inserts a literal newline.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if shiftHeld {
                return false // let the text view insert the newline itself
            }
            parent.state.onPaste?()
            return true // swallow the Return so it pastes instead of adding a line
        }
    }
}
