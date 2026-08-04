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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Identity carried across the morph.
    @Namespace private var hudNamespace

    @State private var entered = false
    @State private var isHoveringCard = false
    @State private var isDragging = false

    private var layout: HUDLayout { HUDLayout(state: state) }

    var body: some View {
        let layout = self.layout
        let morph: Animation? = HUDFeatureFlags.morphEnabled ? motion.hudMorph : nil

        sections(layout)
            .padding(HUDMetrics.inset)
            .frame(width: layout.width)
            // The card's height is its content's, never the panel's: the panel
            // is sized FROM this, so it must not be sized BY it.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: layout.minHeight)
            .background { dragSurface }
            .overlay(alignment: .top) { grabber }
            // The chip row deliberately overhangs its slot by 20pt on each side
            // so its fade band can start outside the content box (see
            // `HUDActionChipRow`). Without this clip a scrolled-away chip would
            // render faintly *outside* the card, floating on the desktop.
            .clipShape(RoundedRectangle(cornerRadius: Radius.hud, style: .continuous))
            .glassCard(reduceTransparency: reduceTransparency)
            // Radius 22 published for the concentric law: every control inside
            // the 12pt inset derives 22 − 12 = 10 with no literal anywhere.
            .environment(\.plateRadius, Radius.hud)
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onCardSize)
            .animation(morph, value: layout)
            .animation(morph, value: state.reviewBanner)
            .scaleEffect(entranceScale)
            .offset(y: entered ? 0 : 8)
            .opacity(entered ? 1 : 0)
            .onAppear { playEntrance() }
            .onChange(of: state.presentationCount) { playEntrance() }
            .onHover { isHoveringCard = $0 }
    }

    // MARK: Sections

    @ViewBuilder
    private func sections(_ layout: HUDLayout) -> some View {
        VStack(alignment: .leading, spacing: HUDMetrics.gap) {
            if let message = bannerMessage {
                HUDBanner(message: message, showsRetry: hasBannerRetry) {
                    performBannerRetry()
                }
                    .transition(.opacity)
            }

            if layout.showsMeter {
                LevelBars(
                    samples: state.levelHistory,
                    isFrozen: state.mode == .transcribing,
                    isOverloaded: state.level > LevelBars.overloadThreshold
                )
                .frame(height: HUDMetrics.meterHeight)
                .frame(maxWidth: .infinity)
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
                HStack(spacing: HUDMetrics.gap) {
                    RecordingPulse()
                    LevelBars(
                        samples: state.levelHistory,
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
                Text("Nothing to review.")
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

            if layout.showsTailSpacer {
                Spacer(minLength: 0)
            }

            HUDControlRow(state: state, layout: layout, namespace: hudNamespace)
                .frame(height: HUDMetrics.controlRowHeight)
        }
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
        case .recording, .transcribing: return nil
        }
    }

    /// Only the review banner carries its own Retry. In `.failed` the control
    /// row owns it (and Return is bound to it there), so putting one in the
    /// banner too would offer the same action twice in the same card.
    private var hasBannerRetry: Bool {
        switch state.mode {
        case .reviewing, .resumeRecording: return state.onRetry != nil
        case .failed, .recording, .transcribing: return false
        }
    }

    private func performBannerRetry() {
        state.onRetry?()
    }

    // MARK: Entrance

    private var entranceScale: CGFloat {
        if motion.reduceMotion { return 1 }
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

    // MARK: Drag

    /// The card is a drag region. This layer sits BEHIND the content, so
    /// buttons, chips and the text view take their clicks first and only the
    /// chrome between them starts a drag.
    private var dragSurface: some View {
        Color.clear
            .contentShape(RoundedRectangle(cornerRadius: Radius.hud, style: .continuous))
            .onTapGesture(count: 2) { LiveHUDPanel.shared.resetPosition() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        if !isDragging {
                            isDragging = true
                            LiveHUDPanel.shared.dragBegan()
                        }
                        LiveHUDPanel.shared.dragChanged()
                    }
                    .onEnded { _ in
                        isDragging = false
                        LiveHUDPanel.shared.dragEnded()
                    }
            )
    }

    /// 2 × 28pt grabber at the top centre, on hover only.
    private var grabber: some View {
        Capsule()
            .fill(Palette.inkFaint.opacity(isHoveringCard ? 0.25 : 0))
            .frame(width: 28, height: 2)
            .padding(.top, 5)
            .allowsHitTesting(false)
            .animation(motion.hover, value: isHoveringCard)
    }
}

// MARK: - Card chrome

private extension View {
    /// The HUD's glass, its hairline and its L3 elevation.
    ///
    /// On macOS 26 the card is wrapped in a `GlassEffectContainer` and carries a
    /// `glassEffectID`, so the system morphs the glass shape itself as the card
    /// resizes. Below 26 (and under Reduce Transparency) `glassSurface` falls
    /// back to `.regularMaterial` / an opaque fill, and the shape simply
    /// animates with the frame.
    @ViewBuilder
    func glassCard(reduceTransparency: Bool) -> some View {
        if #available(macOS 26, *) {
            HUDGlassContainer { self }
                .hudElevation(reduceTransparency: reduceTransparency)
        } else {
            glassSurface(cornerRadius: Radius.hud, opaqueFill: Palette.canvas)
                .hudElevation(reduceTransparency: reduceTransparency)
        }
    }

    func hudElevation(reduceTransparency: Bool) -> some View {
        modifier(HUDElevation(reduceTransparency: reduceTransparency))
    }
}

@available(macOS 26, *)
private struct HUDGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            content
                .glassSurface(cornerRadius: Radius.hud, opaqueFill: Palette.canvas)
                .glassEffectID("hud", in: namespace)
                .glassEffectTransition(.matchedGeometry)
        }
    }
}

/// L3: `0 16px 48px rgba(0,0,0,0.30)` + `0 2px 6px rgba(0,0,0,0.14)`, reduced
/// under Reduce Transparency. Drawn as a masked background rather than a
/// `.shadow` on the card, so it shadows the CARD and not the text on it.
private struct HUDElevation: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content.background { shadow }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.hud, style: .continuous)
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
            case .recording, .resumeRecording:
                if !layout.showsInlineMeter {
                    HUDClock(seconds: state.elapsedSeconds)
                }
                Spacer(minLength: Space.s4)
                cancelButton(title: "Cancel")
                primaryButton(title: "Finish", hint: finishHint) { state.onStop?() }

            case .transcribing:
                ShimmerText("Transcribing")
                    .typo(.headline)
                Text(transcribingDetail)
                    .typo(.mono)
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
                Spacer(minLength: Space.s4)
                // Finish is gone — there is nothing left to finish — but a
                // hung cloud request has to have a way out, so Cancel stays
                // exactly where recording left it and keeps its `esc` hint.
                cancelButton(title: "Cancel")

            case .reviewing:
                cancelButton(title: "Cancel")
                Spacer(minLength: Space.s4)
                if !state.actionRevertStack.isEmpty, state.runningActionId == nil {
                    HUDButton(
                        title: "Undo",
                        systemImage: "arrow.uturn.backward",
                        role: .secondary
                    ) { state.undoLastAction() }
                        .help("Undo last action")
                        .transition(.opacity)
                }
                HUDButton(
                    title: "Resume",
                    systemImage: "mic.fill",
                    hint: "⌘R",
                    role: .accent
                ) { state.onResume?() }
                primaryButton(
                    title: "Paste",
                    hint: HotkeyStore.shared.binding.displayKeys.joined()
                ) { state.onPaste?() }

            case .failed:
                Spacer(minLength: Space.s4)
                cancelButton(title: "Close")
                if state.failureCanRetry {
                    primaryButton(
                        title: "Retry",
                        systemImage: "arrow.clockwise",
                        hint: "↩"
                    ) { state.onRetry?() }
                }
            }
        }
        .animation(motion.layout, value: state.actionRevertStack.count)
    }

    private func cancelButton(title: String) -> some View {
        HUDButton(title: title, hint: "esc", role: .secondary) { state.onCancel?() }
            .matchedGeometryEffect(id: "hud.cancel", in: namespace)
    }

    private func primaryButton(
        title: String,
        systemImage: String? = nil,
        hint: String?,
        action: @escaping () -> Void
    ) -> some View {
        HUDButton(title: title, systemImage: systemImage, hint: hint, role: .primary, action: action)
            .matchedGeometryEffect(id: "hud.primary", in: namespace)
    }

    /// Toggle mode finishes on the same hotkey, so show it; hold mode finishes
    /// on release, which has no key to surface, so the button stands alone.
    private var finishHint: String? {
        switch HotkeyStore.shared.mode {
        case .toggle: return HotkeyStore.shared.binding.displayKeys.joined()
        case .hold: return nil
        }
    }

    private var transcribingDetail: String {
        let elapsed = String(format: "%0.1fs", state.transcribingElapsedSeconds)
        guard let progress = state.transcribingProgress else { return elapsed }
        return "\(progress.current) / \(progress.total) · \(elapsed)"
    }
}

/// SF Mono 13/medium, digits rolling rather than popping.
private struct HUDClock: View {
    let seconds: Double

    var body: some View {
        Text(text)
            .typo(.clock)
            .foregroundStyle(Palette.inkFaint)
            .contentTransition(.numericText())
    }

    private var text: String {
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

    /// Prior transcript in `ink`; the in-progress dictation streams in `accent`
    /// at the caret so it's clear where the new words will land. Buffered
    /// engines emit no partial, so the prior text simply stays put.
    private var composed: Text {
        var result = Text(state.recordingPrefix).foregroundColor(Palette.ink)
        if !state.partialTranscript.isEmpty {
            if needsLeadingSpace { result = result + Text(" ") }
            result = result + Text(state.partialTranscript).foregroundColor(Palette.accent)
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
                    ) { state.onRunAction?(action) }
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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        Self.configureScrollView(scrollView)
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        Self.configureTextView(textView, delegate: context.coordinator)
        textView.string = text
        textView.setSelectedRange(clampedRange(state.selectedRange, in: text))
        context.coordinator.lastSyncedText = text
        focusOnNextRunLoop(textView)
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

    private func focusOnNextRunLoop(_ textView: NSTextView) {
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
    }

    private static func configureTextView(_ textView: NSTextView, delegate: NSTextViewDelegate) {
        textView.delegate = delegate
        // The Transcript register: SF Pro 15 / line-height 21, in `ink` — not
        // white-on-black. This is the largest body text in the app.
        textView.font = .systemFont(ofSize: 15)
        // Keeps the first and last lines out of the scroll-edge gradient.
        textView.textContainerInset = NSSize(width: 0, height: 12)
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
