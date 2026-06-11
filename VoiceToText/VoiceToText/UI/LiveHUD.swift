import AppKit
import Observation
import OSLog
import SwiftUI

/// Recording HUD: non-activating, non-key — floats above whatever app the
/// user is typing in without stealing focus.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Review HUD: nonactivating (doesn't bring our Settings window forward with it)
/// but still accepts key status so the user can edit the transcript in a TextEditor.
/// Same pattern as Spotlight/Raycast.
private final class KeyAcceptingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum LiveHUDMode {
    case recording
    case transcribing
    case reviewing
    case failed
}

@Observable
@MainActor
final class LiveHUDState {
    static let shared = LiveHUDState()
    static let levelHistoryCount = 140

    var mode: LiveHUDMode = .recording
    var isRecording: Bool = false
    var elapsedSeconds: Double = 0
    /// Smoothed mic level, 0...1.
    var level: Double = 0
    /// Rolling buffer of recent levels for the ECG trace (oldest → newest).
    var levelHistory: [Double] = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
    /// Editable transcript bound to the review TextEditor.
    var reviewText: String = ""
    /// One-line notice shown above the review editor when a Resume attempt
    /// silently produced nothing (so failures after API charges stay visible).
    var reviewBanner: String?
    var transcribingElapsedSeconds: Double = 0
    var transcribingProgress: TranscribingProgress?

    /// Whether the recording HUD reserves a live-transcript area (true for
    /// streaming engines like ElevenLabs). Buffered local engines leave this
    /// false so the HUD stays compact.
    var showsLiveText: Bool = false
    /// Live transcript shown while recording with a streaming engine — the
    /// committed text plus the in-progress partial. Replaced on each update.
    var partialTranscript: String = ""

    /// Last error surfaced through the failure HUD. Cleared whenever the HUD
    /// transitions away from `.failed`.
    var failureMessage: String = ""
    /// Whether the failure HUD should offer a Retry button. Failures whose
    /// audio can't possibly succeed on a second pass (too-short, VAD silent)
    /// set this to `false` and only show Dismiss.
    var failureCanRetry: Bool = false

    /// Whether this review session shows the action chips row. Snapshotted
    /// from `ActionsStore.shared.showsInReview` when the review HUD is shown
    /// so the row's presence always matches the panel height chosen at the
    /// same moment (same pattern as `showsLiveText`).
    var reviewShowsActions: Bool = false
    /// The actions offered by this review session, snapshotted alongside
    /// `reviewShowsActions`. Chips, ⌘1–⌘9, and index lookups all read this
    /// one list so mid-review settings changes can't desync them.
    var reviewActions: [DictationAction] = []
    /// Identifier of the dictation action currently rewriting the review
    /// text, if any. Drives the running shimmer on its chip and disables the
    /// other chips while the request is in flight.
    var runningActionId: UUID?
    /// Snapshots of the review text taken before each action rewrote it,
    /// oldest first. Revert pops one entry at a time, so chained actions
    /// (translate, then improve) undo step by step back to the original.
    var actionRevertStack: [String] = []

    /// Cursor position inside the review editor. Written by the editor's
    /// delegate, read by DictationController when Resume is pressed so the
    /// new transcription can be spliced in at the caret.
    @ObservationIgnored var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @ObservationIgnored var onPaste: (@MainActor () -> Void)?
    @ObservationIgnored var onCancel: (@MainActor () -> Void)?
    @ObservationIgnored var onResume: (@MainActor () -> Void)?
    @ObservationIgnored var onRetry: (@MainActor () -> Void)?
    @ObservationIgnored var onRunAction: (@MainActor (DictationAction) -> Void)?
}

struct TranscribingProgress: Equatable {
    let current: Int
    let total: Int
}

@MainActor
final class LiveHUDPanel {
    static let shared = LiveHUDPanel()
    private var recordingPanel: NSPanel?
    private var reviewPanel: NSPanel?
    private let state = LiveHUDState.shared

    private let recordingSize = NSSize(width: 480, height: 150)
    /// Taller recording layout that reserves room for the live transcript
    /// (streaming engines). Used while `state.showsLiveText` is set, including
    /// the recording→transcribing hand-off (which leaves the flag untouched).
    private let recordingLiveSize = NSSize(width: 480, height: 224)
    private var activeRecordingSize: NSSize {
        state.showsLiveText ? recordingLiveSize : recordingSize
    }
    private let reviewSize = NSSize(width: 560, height: 260)
    /// Taller review layout that reserves room for the action chips row.
    private let reviewActionsSize = NSSize(width: 560, height: 300)
    private let failureSize = NSSize(width: 480, height: 200)

    private init() {}

    func show(showsLiveText: Bool = false) {
        reviewPanel?.orderOut(nil)

        state.mode = .recording
        state.isRecording = true
        state.elapsedSeconds = 0
        state.level = 0
        state.levelHistory = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
        state.reviewText = ""
        state.reviewBanner = nil
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.showsLiveText = showsLiveText
        state.partialTranscript = ""
        state.failureMessage = ""
        state.failureCanRetry = false
        state.selectedRange = NSRange(location: 0, length: 0)
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = nil
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil

        let p = ensureRecordingPanel()
        position(p, size: activeRecordingSize)
        p.orderFrontRegardless()
        AppLog.hud.info("HUD shown at \(String(describing: p.frame))")
    }

    /// Reuses the recording panel (same size/position) for a seamless
    /// hand-off from "recording" to "transcribing". Also hides the review
    /// panel — needed when transitioning from the failure HUD (which is
    /// hosted on the review panel) into a retry.
    func showTranscribing() {
        reviewPanel?.orderOut(nil)

        state.mode = .transcribing
        state.isRecording = false
        state.level = 0
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil

        let p = ensureRecordingPanel()
        position(p, size: activeRecordingSize)
        p.orderFrontRegardless()
    }

    func showReview(
        text: String,
        cursorLocation: Int? = nil,
        banner: String? = nil,
        onPaste: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onResume: @escaping @MainActor () -> Void,
        onRunAction: (@MainActor (DictationAction) -> Void)? = nil
    ) {
        recordingPanel?.orderOut(nil)

        let nsLen = (text as NSString).length
        let caret = max(0, min(cursorLocation ?? nsLen, nsLen))

        state.mode = .reviewing
        state.isRecording = false
        state.level = 0
        state.reviewText = text
        state.reviewBanner = banner
        state.failureMessage = ""
        state.failureCanRetry = false
        state.selectedRange = NSRange(location: caret, length: 0)
        // Snapshot once per session: the chip list, the row's presence, and
        // the panel height are decided together, so a mid-review settings
        // change (key added, action toggled) can't squeeze the editor inside
        // a fixed frame or desync ⌘1–⌘9 from the visible chips.
        state.reviewActions = ActionsStore.shared.enabledActions
        state.reviewShowsActions = ActionsStore.shared.showsInReview
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = onPaste
        state.onCancel = onCancel
        state.onResume = onResume
        state.onRetry = nil
        state.onRunAction = onRunAction

        let p = ensureReviewPanel()
        position(p, size: state.reviewShowsActions ? reviewActionsSize : reviewSize)
        // Nonactivating panel: becomes key for keyboard input without activating
        // our app, so the Settings window stays wherever the user left it.
        p.orderFrontRegardless()
        p.makeKeyAndOrderFront(nil)
        AppLog.hud.info("HUD review shown at \(String(describing: p.frame))")
    }

    /// Displays the failure HUD with a user-facing error message. Offers Retry
    /// when `canRetry` is true (network/transient failures); otherwise only a
    /// Dismiss action (e.g. "no speech detected", where re-running the same
    /// audio won't help). Hosted on the key-accepting review panel so the
    /// buttons and Esc work, sized smaller than the review HUD.
    func showFailure(
        message: String,
        canRetry: Bool,
        onRetry: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        recordingPanel?.orderOut(nil)

        state.mode = .failed
        state.isRecording = false
        state.level = 0
        state.failureMessage = message
        state.failureCanRetry = canRetry
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.reviewText = ""
        state.reviewBanner = nil
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onCancel = onCancel
        state.onRetry = onRetry
        state.onPaste = nil
        state.onResume = nil
        state.onRunAction = nil

        let p = ensureReviewPanel()
        position(p, size: failureSize)
        p.orderFrontRegardless()
        p.makeKeyAndOrderFront(nil)
        AppLog.hud.info("HUD failure shown: \(message)")
    }

    func setElapsed(_ seconds: Double) {
        state.elapsedSeconds = seconds
    }

    func setTranscribingElapsed(_ seconds: Double) {
        state.transcribingElapsedSeconds = seconds
    }

    func setTranscribingProgress(current: Int, total: Int) {
        state.transcribingProgress = TranscribingProgress(current: current, total: total)
    }

    /// Live transcript update from a streaming engine (committed + partial).
    func setPartialTranscript(_ text: String) {
        state.partialTranscript = text
    }

    func setLevel(_ level: Double) {
        // Exponential smoothing so the trace doesn't jitter on every tap buffer.
        let smoothed = state.level * 0.6 + level * 0.4
        state.level = smoothed

        var history = state.levelHistory
        history.removeFirst()
        history.append(smoothed)
        state.levelHistory = history
    }

    func hide() {
        state.isRecording = false
        state.level = 0
        state.reviewBanner = nil
        state.showsLiveText = false
        state.partialTranscript = ""
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.failureMessage = ""
        state.failureCanRetry = false
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = nil
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil
        recordingPanel?.orderOut(nil)
        reviewPanel?.orderOut(nil)
    }

    /// Whether the given key event was delivered to the review panel.
    /// Used to keep review-only shortcuts (⌘1–⌘9) from firing while the
    /// user is typing in another of our windows (e.g. Settings).
    func isReviewPanelEvent(_ event: NSEvent) -> Bool {
        event.window === reviewPanel
    }

    /// Current edited review text (read at paste time).
    var currentReviewText: String { state.reviewText }

    /// Current caret position inside the review editor (read at resume time
    /// to decide where to splice the next transcription).
    var currentCursorLocation: Int { state.selectedRange.location }

    private func ensureRecordingPanel() -> NSPanel {
        if let recordingPanel { return recordingPanel }

        let initialRect = NSRect(origin: .zero, size: recordingSize)
        let p = NonKeyPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        configureFloating(p)
        attachHosting(p, rect: initialRect)
        recordingPanel = p
        return p
    }

    private func ensureReviewPanel() -> NSPanel {
        if let reviewPanel { return reviewPanel }

        let initialRect = NSRect(origin: .zero, size: reviewSize)
        let p = KeyAcceptingPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        configureFloating(p)
        attachHosting(p, rect: initialRect)
        reviewPanel = p
        return p
    }

    private func configureFloating(_ p: NSPanel) {
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    private func attachHosting(_ p: NSPanel, rect: NSRect) {
        let hosting = NSHostingView(rootView: LiveHUDView(state: state))
        hosting.frame = rect
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.minY + 120
        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true,
            animate: false
        )
    }
}

struct LiveHUDView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        Group {
            switch state.mode {
            case .recording:
                RecordingView(state: state)
            case .transcribing:
                TranscribingView(state: state)
            case .reviewing:
                ReviewView(state: state)
            case .failed:
                FailedView(state: state)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 4)
        .padding(20)
    }
}

private struct RecordingView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(spacing: 10) {
            LevelBars(samples: state.levelHistory)
                .frame(maxWidth: .infinity)
                .frame(height: 72)

            if state.showsLiveText {
                // The transcript area is pinned to a constant three-line height
                // by the hidden sizer below, so the HUD never reflows — whether
                // it shows the "Listening" indicator, one line, or three wrapped
                // lines. An empty Text doesn't reserve its line count, so the
                // sizer carries real line breaks to hold the height open.
                // Newest words stay visible via head truncation.
                ZStack(alignment: .topLeading) {
                    Text("\n\n")
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(3, reservesSpace: true)
                        .hidden()

                    if state.partialTranscript.isEmpty {
                        ListeningIndicator()
                            .transition(.opacity)
                    } else {
                        Text(state.partialTranscript)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3, reservesSpace: true)
                            .truncationMode(.head)
                            .multilineTextAlignment(.leading)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.easeOut(duration: 0.18), value: state.partialTranscript)
            }

            HStack(spacing: 14) {
                Text(timeString)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()

                Text(recordingHint)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.1)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    private var timeString: String {
        let total = Int(state.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var recordingHint: String {
        switch HotkeyStore.shared.mode {
        case .hold: return "Release to finish · Esc cancels"
        case .toggle: return "Press again to finish · Esc cancels"
        }
    }
}

/// Placeholder shown while a streaming engine is connected but hasn't emitted
/// any words yet. A breathing "live" dot beside a shimmering "Listening" label
/// — reuses the same shimmer treatment as the transcribing state so the two
/// phases read as one continuous animation rather than a hard cut.
private struct ListeningIndicator: View {
    @State private var pulsing = false

    private static let dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(.white)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .scaleEffect(pulsing ? 1 : 0.85)
                .opacity(pulsing ? 1 : 0.5)

            ShimmerText("Listening")
                .font(.system(size: 13, weight: .medium))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

private struct TranscribingView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(spacing: 14) {
            PulsingDots()
                .frame(height: 14)

            ShimmerText("Transcribing")
                .font(.system(size: 14, weight: .medium))

            HStack(spacing: 10) {
                if let progress = state.transcribingProgress {
                    Text("\(progress.current) / \(progress.total)")
                }
                Text(elapsedString)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var elapsedString: String {
        String(format: "%0.1fs", state.transcribingElapsedSeconds)
    }
}

private struct PulsingDots: View {
    @State private var phase: Double = 0

    private static let dotCount = 3
    private static let dotSize: CGFloat = 8
    private static let dotSpacing: CGFloat = 10
    private static let cycleDuration: TimeInterval = 1.2

    var body: some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .opacity(opacity(at: index))
                    .scaleEffect(scale(at: index))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: Self.cycleDuration).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    // Per-dot phase offset makes the highlight travel left → right;
    // the triangle shape smooths the cycle.
    private func wave(at index: Int) -> Double {
        let offset = Double(index) / Double(Self.dotCount)
        let p = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 1 - abs(p - 0.5) * 2
    }

    private func opacity(at index: Int) -> Double {
        0.25 + 0.7 * wave(at: index)
    }

    private func scale(at index: Int) -> Double {
        0.8 + 0.4 * wave(at: index)
    }
}

private struct ShimmerText: View {
    let text: String
    @State private var phase: CGFloat = -1

    init(_ text: String) { self.text = text }

    private static let cycleDuration: TimeInterval = 1.8
    private static let baseOpacity: Double = 0.4

    var body: some View {
        // A dim base word with a full-brightness copy locked exactly on top of
        // it; only the gradient *mask* slides across, so the bright sweep tracks
        // the letters precisely instead of rendering a shifted ghost copy.
        Text(text)
            .foregroundStyle(.white.opacity(Self.baseOpacity))
            .overlay {
                Text(text)
                    .foregroundStyle(.white)
                    .mask {
                        GeometryReader { geo in
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0), location: 0),
                                    .init(color: .white.opacity(0.95), location: 0.5),
                                    .init(color: .white.opacity(0), location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: geo.size.width * phase)
                        }
                    }
            }
            .onAppear {
                withAnimation(.linear(duration: Self.cycleDuration).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

private struct ReviewView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = state.reviewBanner {
                ReviewBanner(message: banner)
            }

            ReviewTextEditor(text: $state.reviewText, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if state.reviewShowsActions {
                ReviewActionsBar(state: state)
            }

            HStack(spacing: 8) {
                ReviewKeyButton(
                    title: "Resume",
                    systemImage: "mic.fill",
                    hint: "⌘R",
                    emphasis: .secondary
                ) { state.onResume?() }

                Spacer()

                ReviewKeyButton(
                    title: "Cancel",
                    hint: "esc",
                    emphasis: .secondary
                ) { state.onCancel?() }

                ReviewKeyButton(
                    title: "Paste",
                    hint: HotkeyStore.shared.binding.displayKeys.joined(),
                    emphasis: .primary
                ) { state.onPaste?() }
            }
        }
    }
}

/// Row of AI action chips between the review editor and the key buttons.
/// Clicking a chip (or ⌘1–⌘9) sends the transcript through the action's
/// OpenAI transform; the running chip shimmers and the rest disable until
/// the request settles. After a transform, a Revert chip restores the
/// pre-action text.
private struct ReviewActionsBar: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(state.reviewActions.enumerated()), id: \.element.id) { index, action in
                    ReviewActionChip(
                        title: action.name,
                        hint: index < 9 ? "⌘\(index + 1)" : nil,
                        isRunning: state.runningActionId == action.id,
                        isDisabled: state.runningActionId != nil && state.runningActionId != action.id
                    ) { state.onRunAction?(action) }
                }

                if !state.actionRevertStack.isEmpty, state.runningActionId == nil {
                    ReviewActionChip(
                        title: "Undo",
                        systemImage: "arrow.uturn.backward",
                        hint: nil,
                        isRunning: false,
                        isDisabled: false
                    ) { revert() }
                }
            }
        }
    }

    /// Steps back one action at a time: each click restores the text from
    /// before the most recent transform, so chained actions unwind in order
    /// until the original transcript is back (then the chip disappears).
    private func revert() {
        guard let original = state.actionRevertStack.popLast() else { return }
        state.reviewBanner = nil
        // No-op restore would desync the recorded caret from the visible one
        // (the editor skips syncs when the text is unchanged).
        guard original != state.reviewText else { return }
        state.selectedRange = NSRange(location: (original as NSString).length, length: 0)
        state.reviewText = original
    }
}

private struct ReviewActionChip: View {
    let title: String
    var systemImage: String? = nil
    let hint: String?
    let isRunning: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                if isRunning {
                    ShimmerText(title)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                if let hint, !isRunning {
                    Text(hint)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isRunning ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(isRunning ? 0.16 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isRunning)
        .opacity(isDisabled ? 0.35 : 1)
    }
}

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
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = .systemBlue
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
    }
}

/// Shown when transcription fails or returns nothing. Surfaces the error
/// message (so the user knows what went wrong) and offers Retry when the
/// audio still has a chance to transcribe on a second pass (network blip,
/// transient model error, empty decode).
private struct FailedView: View {
    @Bindable var state: LiveHUDState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .padding(.top, 1)
                Text(state.failureMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Spacer()

                ReviewKeyButton(
                    title: state.failureCanRetry ? "Dismiss" : "Close",
                    hint: "esc",
                    emphasis: .secondary
                ) { state.onCancel?() }

                if state.failureCanRetry {
                    ReviewKeyButton(
                        title: "Retry",
                        systemImage: "arrow.clockwise",
                        hint: "↩",
                        emphasis: .primary
                    ) { state.onRetry?() }
                }
            }
        }
    }
}

private struct ReviewBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35))
        )
    }
}

private struct ReviewKeyButton: View {
    enum Emphasis { case primary, secondary }

    let title: String
    let systemImage: String?
    let hint: String
    let emphasis: Emphasis
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        hint: String,
        emphasis: Emphasis,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hint = hint
        self.emphasis = emphasis
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityLabel(title)
                } else {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(hint)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(emphasis == .primary ? 0.55 : 0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(.white.opacity(emphasis == .primary ? 0.96 : 0.72))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(emphasis == .primary ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(emphasis == .primary ? 0.18 : 0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Mirrored capsule bars, oldest → newest left → right. Each bar springs to
/// its level independently so the strip feels alive even on a steady signal.
/// A small floor keeps silent bars visible as a thin baseline.
private struct LevelBars: View {
    let samples: [Double]

    private static let barCount = 56
    private static let barSpacing: CGFloat = 3
    private static let minBarHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = Self.barSpacing * CGFloat(Self.barCount - 1)
            let barWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(Self.barCount))
            let maxHeight = geo.size.height

            HStack(alignment: .center, spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    let level = level(at: index)
                    Capsule()
                        .fill(Color.white.opacity(opacity(at: index)))
                        .frame(width: barWidth, height: barHeight(level: level, max: maxHeight))
                        .animation(.spring(response: 0.18, dampingFraction: 0.75), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func level(at index: Int) -> Double {
        guard !samples.isEmpty else { return 0 }
        let step = Double(samples.count) / Double(Self.barCount)
        let sampleIndex = min(samples.count - 1, Int(Double(index) * step))
        return samples[sampleIndex]
    }

    private func barHeight(level: Double, max maxHeight: CGFloat) -> CGFloat {
        let clamped = min(1, Swift.max(0, level))
        return Self.minBarHeight + (maxHeight - Self.minBarHeight) * CGFloat(clamped)
    }

    // Older samples on the left fade out; the rightmost bars sit at the
    // "write head" and read as the current input.
    private func opacity(at index: Int) -> Double {
        let t = Double(index) / Double(Self.barCount - 1)
        return 0.22 + 0.68 * t
    }
}
