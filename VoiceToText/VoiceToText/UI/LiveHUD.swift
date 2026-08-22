import AppKit
import Observation
import OSLog
import SwiftUI

// MARK: - The panel
//
// PANEL / FOCUS MODEL
//
// There is exactly ONE panel. It used to be two — a non-key recording panel and
// a key-accepting review panel — which ordered out and in at different sizes in
// the same frame, which is why recording → review read as a glitch. The object
// on screen now never changes identity; only `acceptsKey` flips.
//
// Key eligibility is a stored flag rather than a `true`/`false` override,
// because `canBecomeKey` is consulted by AppKit when a window is ordered in or
// asked to become key — not continuously. Every flip therefore goes through
// `setKeyEligible(_:)`, which re-orders the panel afterwards.
//
// GIVING KEY BACK is the dangerous direction. A nonactivating panel that is key
// has taken key status away from the frontmost app's window; simply setting
// `acceptsKey = false` would leave it key with no way to type into it and no
// way for the target app to get the caret back. The only ordering AppKit
// documents for handing key back to the previously key window is `orderOut(_:)`
// — which is exactly what the two-panel version did on every one of these
// transitions. So a downgrade orders the panel out (key returns to the target
// app, precisely as today), flips the flag, and orders it straight back in
// within the same runloop turn.
private final class HUDPanel: NSPanel {
    /// Flipped per mode by `LiveHUDPanel.setKeyEligible(_:)`. Never write it
    /// directly — the panel must be re-ordered after every change.
    var acceptsKey = false

    override var canBecomeKey: Bool { acceptsKey }
    /// Never main: the app must not come forward, the Settings window must stay
    /// wherever the user left it.
    override var canBecomeMain: Bool { false }
}

/// Hosting view that responds to the very first click even when our app isn't
/// the active one. The HUD panel is nonactivating, so without this the first
/// click on a HUD button while another app is frontmost is consumed to bring the
/// panel forward instead of firing the button — leaving the buttons dead until a
/// second click.
///
/// Concrete (non-generic) on purpose: a generic `NSHostingView<Content>`
/// subclass crashes the Swift 6.3 optimizer (EarlyPerfInliner segfault on the
/// synthesized deinit) in Release builds.
private final class FirstMouseHostingView: NSHostingView<LiveHUDView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Modes

nonisolated enum LiveHUDMode: Sendable, Equatable {
    /// The model is being downloaded or loaded, before capture can start. Shown
    /// only once preparation outlasts `DictationController.preparingRevealDelay`
    /// — a warm model is ready in milliseconds and must not flash a card — which
    /// is what puts the first-run download on screen instead of leaving the
    /// hotkey looking dead for the length of a 470MB fetch.
    case preparing
    case recording
    /// Recording resumed from a review session: the prior transcript stays on
    /// screen (read-only) while new speech streams in at the caret.
    case resumeRecording
    case transcribing
    case reviewing
    /// A transcription failure. No longer a separate 480×200 panel — it renders
    /// as a banner inside the same card at the same review width.
    case failed

    /// Whether the panel accepts key status (and therefore keyboard input) in
    /// this mode. Preparing, recording and transcribing must NOT: the user is
    /// typing in another app and the caret has to stay there.
    var acceptsKey: Bool {
        switch self {
        case .preparing, .recording, .transcribing: return false
        case .resumeRecording, .reviewing, .failed: return true
        }
    }
}

// MARK: - Feature flags

nonisolated enum HUDFeatureFlags {
    /// THE MORPH KILL SWITCH.
    ///
    /// `defaults write com.gug007.VoiceToText hud.morph -bool NO` restores the
    /// pre-Clear-Coat behaviour: the panel frame is set with `animate: false`
    /// and the card's mode change carries no animation, i.e. today's hard cut.
    /// Read fresh at every transition, so flipping it takes effect on the next
    /// dictation without a rebuild or even a relaunch.
    ///
    /// It exists because the NSPanel frame animation and the SwiftUI spring are
    /// two clocks that have to agree frame-for-frame; if they ever fight on a
    /// machine we can't reproduce, this is the switch that turns the fight off.
    static let morphKey = "hud.morph"

    static var morphEnabled: Bool {
        UserDefaults.standard.object(forKey: morphKey) as? Bool ?? true
    }
}

// MARK: - State

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

    /// While a resumed recording is in flight, the prior review text split at
    /// the caret. The resume-recording view renders `recordingPrefix` +
    /// live partial + `recordingSuffix`, so the transcript the user was
    /// reviewing stays on screen while new words stream in where they'll land.
    var recordingPrefix: String = ""
    var recordingSuffix: String = ""

    /// Set while this session came out of a review (Resume). Keeps the card at
    /// the review width through the resumed take AND its transcribing phase, so
    /// the morph never snaps back to the compact size mid-session.
    var resumedSession: Bool = false

    /// Last error surfaced through the failure HUD. Cleared whenever the HUD
    /// transitions away from `.failed`.
    var failureMessage: String = ""
    /// Title of the failure card's action button, or nil for Close only.
    /// Failures whose audio can't possibly succeed on a second pass (too-short,
    /// VAD silent) offer nothing; transcription failures offer "Retry"; a
    /// missing permission offers "Open Settings", because pressing the hotkey
    /// again cannot fix it and the message alone leaves the user hunting.
    var failureActionTitle: String?
    var failureActionIcon: String = "arrow.clockwise"
    /// Key hint on that button — only set where the key is really bound
    /// (Return runs Retry; nothing is bound to Open Settings).
    var failureActionHint: String?

    /// Display name of the model being downloaded or loaded, on the preparing
    /// card. The card names the model because "which model is this waiting on"
    /// is the first thing a user asks when a hotkey press seems to do nothing.
    var preparingModelName: String = ""
    /// Preparation progress, 0...1. Nil until the registry reports its first
    /// sample, which is what the indeterminate bar renders.
    var preparingFraction: Double?
    /// Phase text straight from the engine — "Downloading 3/12 files",
    /// "Compiling parakeet_encoder…". This is the line that distinguishes a
    /// running download from a wedged one.
    var preparingMessage: String = ""

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

    /// Bumped every time the panel is shown from hidden. The card replays its
    /// entrance spring on change — `onAppear` fires once per hosting view, and
    /// the hosting view now outlives every session.
    var presentationCount: Int = 0

    /// Cursor position inside the review editor. Written by the editor's
    /// delegate, read by DictationController when Resume is pressed so the
    /// new transcription can be spliced in at the caret.
    @ObservationIgnored var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @ObservationIgnored var onPaste: (@MainActor () -> Void)?
    @ObservationIgnored var onCancel: (@MainActor () -> Void)?
    @ObservationIgnored var onStop: (@MainActor () -> Void)?
    @ObservationIgnored var onResume: (@MainActor () -> Void)?
    @ObservationIgnored var onRetry: (@MainActor () -> Void)?
    @ObservationIgnored var onRunAction: (@MainActor (DictationAction) -> Void)?

    /// Steps back one action at a time: each call restores the text from
    /// before the most recent transform, so chained actions unwind in order
    /// until the original transcript is back (then the Undo button hides).
    func undoLastAction() {
        guard let original = actionRevertStack.popLast() else { return }
        reviewBanner = nil
        // No-op restore would desync the recorded caret from the visible one
        // (the editor skips syncs when the text is unchanged).
        guard original != reviewText else { return }
        selectedRange = NSRange(location: (original as NSString).length, length: 0)
        reviewText = original
    }
}

struct TranscribingProgress: Equatable {
    let current: Int
    let total: Int
}

// MARK: - Controller

@MainActor
final class LiveHUDPanel {
    static let shared = LiveHUDPanel()

    private var panel: HUDPanel?
    private let state = LiveHUDState.shared

    /// Last card size SwiftUI actually laid out. The panel frame is always this
    /// plus the shadow gutter — there are no `NSSize` constants left.
    private var measuredCardSize: CGSize = .zero
    /// When the current morph ends. Late size corrections inside this window
    /// ride the same spring; after it they snap.
    private var morphDeadline: Date = .distantPast

    private var dragStartPanelOrigin: NSPoint?
    private var dragStartMouse: NSPoint?

    private init() {}

    // MARK: Presentation

    /// The model is being fetched or loaded and recording hasn't started yet.
    ///
    /// Deliberately NOT shown on every hotkey press — `DictationController`
    /// only calls this once preparation has outlasted its reveal delay, so a
    /// warm model goes straight to the recording card and this one never
    /// flashes. Cancel maps to `cancelPendingRecording()`, the same action the
    /// hotkey policy already had for this state.
    func showPreparing(modelName: String, onCancel: @escaping @MainActor () -> Void) {
        state.mode = .preparing
        state.isRecording = false
        state.level = 0
        state.levelHistory = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
        state.preparingModelName = modelName
        state.preparingFraction = nil
        state.preparingMessage = ""
        state.reviewText = ""
        state.reviewBanner = nil
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.showsLiveText = false
        state.partialTranscript = ""
        state.recordingPrefix = ""
        state.recordingSuffix = ""
        state.resumedSession = false
        state.failureMessage = ""
        state.failureActionTitle = nil
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = onCancel
        state.onStop = nil
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil

        present()
        AppLog.hud.info("HUD preparing shown for \(modelName)")
    }

    /// Progress sample from `ModelRegistry`, polled while the preparing card is
    /// up. Pass nil for `fraction` to keep the bar indeterminate.
    func setPreparingProgress(fraction: Double?, message: String) {
        state.preparingFraction = fraction
        state.preparingMessage = message
    }

    func show(
        showsLiveText: Bool = false,
        onStop: (@MainActor () -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
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
        state.recordingPrefix = ""
        state.recordingSuffix = ""
        state.resumedSession = false
        state.failureMessage = ""
        state.failureActionTitle = nil
        state.preparingMessage = ""
        state.preparingFraction = nil
        state.selectedRange = NSRange(location: 0, length: 0)
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = onCancel
        state.onStop = onStop
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil

        present()
        AppLog.hud.info("HUD shown at \(String(describing: self.panel?.frame))")
    }

    /// Recording resumed from a review session: the prior transcript, split at
    /// the caret, stays visible while new speech streams in at the insertion
    /// point. The card keeps the review session's exact size so nothing shifts.
    func showResumeRecording(
        prefix: String,
        suffix: String,
        showsLiveText: Bool,
        onStop: (@MainActor () -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
        state.mode = .resumeRecording
        state.isRecording = true
        state.elapsedSeconds = 0
        state.level = 0
        state.levelHistory = Array(repeating: 0, count: LiveHUDState.levelHistoryCount)
        state.showsLiveText = showsLiveText
        state.partialTranscript = ""
        state.recordingPrefix = prefix
        state.recordingSuffix = suffix
        state.resumedSession = true
        state.reviewBanner = nil
        state.runningActionId = nil
        // Drive the resume HUD's Finish/Cancel buttons; without these the
        // leftover review-session callbacks (Paste/Resume) would still be bound.
        state.onStop = onStop
        state.onCancel = onCancel

        present()
        AppLog.hud.info("HUD resume-recording shown at \(String(describing: self.panel?.frame))")
    }

    /// Hand-off from "recording" to "transcribing" in the same card: the meter
    /// keeps its samples and freezes in place rather than being replaced.
    ///
    /// `onCancel` is rebound rather than inherited from the recording session:
    /// the control row still shows Cancel here (Finish is gone), and by this
    /// point cancelling means abandoning the transcription, not the recording.
    func showTranscribing(onCancel: @escaping @MainActor () -> Void) {
        state.mode = .transcribing
        state.isRecording = false
        state.level = 0
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.onCancel = onCancel
        state.onStop = nil

        present()
    }

    func showReview(
        text: String,
        cursorLocation: Int? = nil,
        banner: String? = nil,
        onPaste: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onResume: @escaping @MainActor () -> Void,
        onRetry: (@MainActor () -> Void)? = nil,
        onRunAction: (@MainActor (DictationAction) -> Void)? = nil
    ) {
        let nsLen = (text as NSString).length
        let caret = max(0, min(cursorLocation ?? nsLen, nsLen))

        state.mode = .reviewing
        state.isRecording = false
        state.level = 0
        state.reviewText = text
        state.reviewBanner = banner
        state.failureMessage = ""
        state.failureActionTitle = nil
        state.resumedSession = false
        state.selectedRange = NSRange(location: caret, length: 0)
        // Snapshot once per session: the chip list, the row's presence, and
        // the card height are decided together, so a mid-review settings
        // change (key added, action toggled) can't squeeze the editor inside
        // a fixed frame or desync ⌘1–⌘9 from the visible chips.
        state.reviewActions = ActionsStore.shared.enabledActions
        state.reviewShowsActions = ActionsStore.shared.showsInReview
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = onPaste
        state.onCancel = onCancel
        state.onResume = onResume
        // Retry on the failure banner: re-runs a failed Resume take's audio.
        state.onRetry = onRetry
        state.onRunAction = onRunAction

        present()
        AppLog.hud.info("HUD review shown at \(String(describing: self.panel?.frame))")
    }

    /// A failure, rendered as a banner inside the same card at the same width as
    /// review — the standalone failure panel is gone. `actionTitle` nil leaves
    /// only Close (e.g. "no speech detected", where re-running the audio won't
    /// help); "Retry" re-runs the audio; "Open Settings" is what a permission
    /// failure offers instead, since the hotkey can't fix itself.
    func showFailure(
        message: String,
        actionTitle: String?,
        actionIcon: String = "arrow.clockwise",
        actionHint: String? = nil,
        onRetry: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        state.mode = .failed
        state.isRecording = false
        state.level = 0
        state.failureMessage = message
        state.failureActionTitle = actionTitle
        state.failureActionIcon = actionIcon
        state.failureActionHint = actionHint
        state.preparingMessage = ""
        state.preparingFraction = nil
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.reviewText = ""
        state.reviewBanner = nil
        state.resumedSession = false
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onCancel = onCancel
        state.onRetry = onRetry
        state.onPaste = nil
        state.onResume = nil
        state.onRunAction = nil

        present()
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
        state.recordingPrefix = ""
        state.recordingSuffix = ""
        state.resumedSession = false
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.failureMessage = ""
        state.failureActionTitle = nil
        state.preparingModelName = ""
        state.preparingMessage = ""
        state.preparingFraction = nil
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = nil
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil
        panel?.orderOut(nil)
        panel?.acceptsKey = false
        morphDeadline = .distantPast
    }

    /// Whether the given key event was delivered to the HUD while it is showing
    /// the review transcript. Used to keep review-only shortcuts (⌘1–⌘9) from
    /// firing while the user is typing in another of our windows (e.g.
    /// Settings). The mode test is what the second panel used to provide.
    func isReviewPanelEvent(_ event: NSEvent) -> Bool {
        event.window === panel && state.mode == .reviewing
    }

    /// Current edited review text (read at paste time).
    var currentReviewText: String { state.reviewText }

    /// Current caret position inside the review editor (read at resume time
    /// to decide where to splice the next transcription).
    var currentCursorLocation: Int { state.selectedRange.location }

    // MARK: Panel lifecycle

    /// Orders the panel in for the mode already written into `state`, sizing it
    /// from the layout the card is about to produce and flipping key
    /// eligibility to match.
    private func present() {
        let panel = ensurePanel()
        let wasVisible = panel.isVisible
        let layout = HUDLayout(state: state)

        if !wasVisible {
            state.presentationCount &+= 1
            measuredCardSize = .zero
        }

        // The card animates on the same spring, starting in the same runloop
        // turn — that is the whole point of driving the frame from here rather
        // than waiting for SwiftUI to report its new size.
        let animate = wasVisible && HUDFeatureFlags.morphEnabled
        if animate { morphDeadline = Date().addingTimeInterval(HUDMetrics.morphDuration) }

        let estimate = layout.estimatedCardSize
        measuredCardSize = estimate

        // ORDERING. `setKeyEligible` re-orders the panel (an upgrade orders it
        // front and makes it key; a downgrade from key orders it OUT and back
        // in, which is the only way AppKit hands key status back to the target
        // app). Ordering a window out mid-flight tears down an in-progress
        // frame animation, so on a WARM show the key transition has to settle
        // first and the morph starts after it — otherwise resuming from review
        // and pressing Finish snaps instead of morphing.
        //
        // On a COLD show the frame has to be set first: the panel is not on
        // screen yet, and ordering it in at the previous session's size would
        // flash that size for a runloop turn before the correct frame lands.
        // Nothing is animating then either (`animate` is false), so there is no
        // in-flight animation for the ordering to interrupt.
        if wasVisible {
            setKeyEligible(layout.mode.acceptsKey, wasVisible: true)
            applyFrame(cardSize: estimate, animated: animate)
        } else {
            applyFrame(cardSize: estimate, animated: animate)
            setKeyEligible(layout.mode.acceptsKey, wasVisible: false)
        }
    }

    private func ensurePanel() -> HUDPanel {
        if let panel { return panel }

        let rect = NSRect(origin: .zero, size: NSSize(width: 468, height: 180))
        let p = HUDPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        // The shadow is drawn in the card's layer so it can travel with the
        // morph; a second AppKit shadow would lag it by a frame.
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hosting = FirstMouseHostingView(
            rootView: LiveHUDView(state: state) { size in
                LiveHUDPanel.shared.cardSizeChanged(size)
            }
        )
        hosting.frame = rect
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        panel = p
        return p
    }

    /// The one place `canBecomeKey` changes.
    ///
    /// Upgrade: flip, then order front — AppKit only re-evaluates key
    /// eligibility on an ordering operation, which is the trap this whole
    /// merge had to survive.
    ///
    /// Downgrade: the panel currently holds key status taken from the target
    /// app's window. `orderOut` is the only ordering that hands key back to the
    /// previously key window — and it is precisely what the two-panel version
    /// did on this transition — so we order out, flip, and order straight back
    /// in inside one runloop turn.
    private func setKeyEligible(_ eligible: Bool, wasVisible: Bool) {
        guard let panel else { return }

        if eligible {
            panel.acceptsKey = true
            panel.orderFrontRegardless()
            // Nonactivating panel: becomes key for keyboard input without
            // activating our app, so the Settings window stays where it is.
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let mustReleaseKey = wasVisible && panel.acceptsKey && panel.isKeyWindow
        if mustReleaseKey {
            panel.orderOut(nil)
        }
        panel.acceptsKey = false
        panel.orderFrontRegardless()
    }

    // MARK: Frame

    /// Called by the card once SwiftUI has laid it out. The estimate in
    /// `present()` is exact for every fixed-height section, so this only fires
    /// when content actually grew — a two-line failure banner, a localized
    /// button that widened the control row.
    func cardSizeChanged(_ size: CGSize) {
        let rounded = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard rounded.width > 1, rounded.height > 1 else { return }
        guard abs(rounded.width - measuredCardSize.width) > 0.5
                || abs(rounded.height - measuredCardSize.height) > 0.5 else { return }
        measuredCardSize = rounded

        let animated = HUDFeatureFlags.morphEnabled && Date() < morphDeadline
        // Deferred one turn: this arrives from inside SwiftUI's layout pass and
        // resizing the window synchronously from there re-enters it.
        Task { @MainActor [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.applyFrame(cardSize: rounded, animated: animated)
        }
    }

    private func applyFrame(cardSize: CGSize, animated: Bool) {
        guard let panel else { return }
        let frame = panelFrame(cardSize: cardSize)
        guard frame != panel.frame else { return }

        guard animated else {
            panel.setFrame(frame, display: true, animate: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDMetrics.morphDuration
            context.timingFunction = HUDMetrics.morphTiming
            // Lets the layer-backed content ride the same clock as the frame.
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Panel frame = card + an 88pt transparent shadow gutter on every side,
    /// anchored by the *card's* bottom edge and horizontal centre so growth
    /// happens upward and outward from where the user last put it.
    ///
    /// Every coordinate here is card space — the anchor is the card's
    /// bottom-centre, the clamp keeps the card on screen, and the gutter is
    /// added back only at the end. Measuring on the panel instead would tie a
    /// persisted position to `gutter`, so changing the shadow's size would
    /// silently move every HUD anyone had ever dragged.
    private func panelFrame(cardSize: CGSize) -> NSRect {
        let size = NSSize(
            width: cardSize.width + HUDMetrics.gutter * 2,
            height: cardSize.height + HUDMetrics.gutter * 2
        )
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let anchor = anchor(on: screen)

        let cardX = Self.clamp(
            (anchor.x - cardSize.width / 2).rounded(),
            visible.minX + HUDMetrics.screenMargin,
            visible.maxX - cardSize.width - HUDMetrics.screenMargin
        )
        let cardY = Self.clamp(
            anchor.y.rounded(),
            visible.minY + HUDMetrics.screenMargin,
            visible.maxY - cardSize.height - HUDMetrics.screenMargin
        )
        return NSRect(
            x: cardX - HUDMetrics.gutter,
            y: cardY - HUDMetrics.gutter,
            width: size.width,
            height: size.height
        )
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        guard high >= low else { return (low + high) / 2 }
        return min(max(value, low), high)
    }

    // MARK: Placement

    /// The screen the HUD belongs on: whatever screen it is already showing on
    /// (a morph must never teleport the card between displays), otherwise the
    /// screen holding the focused window of the frontmost app — which is where
    /// the transcript is about to be typed.
    private func activeScreen() -> NSScreen {
        if let panel, panel.isVisible, let screen = panel.screen { return screen }
        if let screen = Self.focusedWindowScreen() { return screen }
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// The screen containing the frontmost window of the frontmost application.
    ///
    /// Read from the window server rather than the Accessibility API: bounds and
    /// owner PID are readable without Screen Recording permission (only window
    /// *names* are gated), and the list is already in front-to-back order.
    private static func focusedWindowScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in infos {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 64, h > 64
            else { continue }
            // CGWindow bounds are top-left origin, measured from the top of the
            // primary display; NSScreen is bottom-left origin.
            guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
            let rect = NSRect(x: x, y: primaryTop - y - h, width: w, height: h)
            let centre = NSPoint(x: rect.midX, y: rect.midY)
            if let hit = NSScreen.screens.first(where: { NSMouseInRect(centre, $0.frame, false) }) {
                return hit
            }
            return NSScreen.screens.max { a, b in
                a.frame.intersection(rect).area < b.frame.intersection(rect).area
            }
        }
        return nil
    }

    /// The card's bottom-centre in screen coordinates: the user's dragged
    /// position for this display, or the default.
    private func anchor(on screen: NSScreen) -> NSPoint {
        storedAnchor(on: screen) ?? Self.defaultAnchor(on: screen)
    }

    private static func defaultAnchor(on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX, y: visible.minY + HUDMetrics.defaultBottomInset)
    }

    /// Per-display identity that survives a reconnect: the display's name plus
    /// its point size. `CGDirectDisplayID` is recycled across reconnects and
    /// `NSScreen.frame.origin` moves whenever the arrangement changes, so
    /// neither is usable as a key on its own.
    private static func screenKey(_ screen: NSScreen) -> String {
        let size = screen.frame.size
        return "\(screen.localizedName)|\(Int(size.width))x\(Int(size.height))"
    }

    /// v2 stores the card's bottom-centre. v1 stored the panel's, which tied
    /// every saved position to `gutter`; those values are dropped on upgrade
    /// and the HUD falls back to the unchanged default placement.
    private static let anchorsDefaultsKey = "hud.panelAnchors.v2"

    private func storedAnchor(on screen: NSScreen) -> NSPoint? {
        let store = UserDefaults.standard.dictionary(forKey: Self.anchorsDefaultsKey) as? [String: [Double]]
        guard let pair = store?[Self.screenKey(screen)], pair.count == 2 else { return nil }
        // Stored relative to the visible frame's origin so a rearranged desktop
        // keeps the HUD in the same place on this display rather than off it.
        let visible = screen.visibleFrame
        return NSPoint(x: visible.minX + pair[0], y: visible.minY + pair[1])
    }

    private func storeAnchor(_ point: NSPoint, on screen: NSScreen) {
        let visible = screen.visibleFrame
        var store = UserDefaults.standard.dictionary(forKey: Self.anchorsDefaultsKey) as? [String: [Double]] ?? [:]
        store[Self.screenKey(screen)] = [point.x - visible.minX, point.y - visible.minY]
        UserDefaults.standard.set(store, forKey: Self.anchorsDefaultsKey)
    }

    private func clearAnchor(on screen: NSScreen) {
        var store = UserDefaults.standard.dictionary(forKey: Self.anchorsDefaultsKey) as? [String: [Double]] ?? [:]
        store.removeValue(forKey: Self.screenKey(screen))
        UserDefaults.standard.set(store, forKey: Self.anchorsDefaultsKey)
    }

    // MARK: Dragging

    /// Screen-absolute drag: the window moves under the cursor, so a
    /// window-relative translation would chase itself and oscillate.
    func dragBegan() {
        dragStartPanelOrigin = panel?.frame.origin
        dragStartMouse = NSEvent.mouseLocation
    }

    func dragChanged() {
        guard let panel, let origin = dragStartPanelOrigin, let start = dragStartMouse else { return }
        let now = NSEvent.mouseLocation
        panel.setFrameOrigin(
            NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y)
        )
    }

    func dragEnded() {
        defer {
            dragStartPanelOrigin = nil
            dragStartMouse = nil
        }
        guard let panel, let screen = panel.screen else { return }
        storeAnchor(
            NSPoint(x: panel.frame.midX, y: panel.frame.minY + HUDMetrics.gutter),
            on: screen
        )
    }

    /// Double-click on the card: forget this display's stored origin and spring
    /// back to the default position.
    func resetPosition() {
        guard let panel, let screen = panel.screen else { return }
        clearAnchor(on: screen)
        let animated = HUDFeatureFlags.morphEnabled
        if animated { morphDeadline = Date().addingTimeInterval(HUDMetrics.morphDuration) }
        applyFrame(cardSize: measuredCardSize, animated: animated)
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
