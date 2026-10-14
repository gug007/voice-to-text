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
final class HUDPanel: NSPanel {
    /// Flipped per mode by `LiveHUDPanel.setKeyEligible(_:)`. Never write it
    /// directly — the panel must be re-ordered after every change. The
    /// conversation panel never sets it: nothing on that card takes typing.
    var acceptsKey = false

    override var canBecomeKey: Bool { acceptsKey }
    /// Never main: the app must not come forward, the Settings window must stay
    /// wherever the user left it.
    override var canBecomeMain: Bool { false }

    /// A borderless, nonactivating, clear panel on every Space. Both HUD panels
    /// are built here so they cannot drift apart; the caller adds the content.
    static func makeFloating() -> HUDPanel {
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
        // The card is up while another app is active — that is its whole job —
        // and AppKit suppresses tooltips for an inactive app's windows by
        // default. The compact sizes keep their controls' keys in tooltips, so
        // without this they would never show.
        p.allowsToolTipsWhenApplicationIsInactive = true
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return p
    }
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
    /// A few seconds of one-line notice after a cancel: "Dictation discarded"
    /// or "Recording discarded" with Undo, or where a cancelled transcription's
    /// audio went. The user has already moved on, so it neither takes key nor
    /// stays.
    case discarded

    /// Whether the panel accepts key status (and therefore keyboard input) in
    /// this mode. Preparing, recording and transcribing must NOT: the user is
    /// typing in another app and the caret has to stay there. Nor must the
    /// discard notice — the Esc that raised it may have been the user leaving
    /// the card to type elsewhere, and a notice that took key would swallow
    /// their next keystrokes. Undo still works on first click.
    var acceptsKey: Bool {
        switch self {
        case .preparing, .recording, .transcribing, .discarded: return false
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

// MARK: - Size

/// Settings → Recording HUD. Small is the default; Large is the full stacked
/// card. Small and Medium draw a fresh take's preparing, recording and
/// transcribing card as one row (`HUDLayout.compactRow`). Everything after
/// that — review, failure, the discard notice — is the same card at every size.
nonisolated enum HUDSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    static let defaultsKey = "hud.size"
    /// What `current` and the Settings picker fall back to when nothing is
    /// stored. One value, so the two cannot disagree about a fresh install.
    static let defaultValue: HUDSize = .small

    /// The stored choice. Read once per session, when a fresh take's card
    /// first appears (`LiveHUDPanel.showPreparing` / `show`) — never by the
    /// card itself, so flipping the setting mid-take cannot resize it.
    static var current: HUDSize {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(HUDSize.init(rawValue:)) ?? defaultValue
    }
}

// MARK: - State

@Observable
@MainActor
final class LiveHUDState {
    static let shared = LiveHUDState()
    static let levelHistoryCount = 140

    var mode: LiveHUDMode = .recording {
        didSet {
            if mode != oldValue { modeChangedAt = ProcessInfo.processInfo.systemUptime }
        }
    }
    /// When `mode` last changed, or the card last appeared from hidden, on
    /// the monotonic clock. See `click(_:)`.
    @ObservationIgnored fileprivate var modeChangedAt: TimeInterval = 0
    /// How long the card's buttons ignore clicks after it changes mode. A
    /// double-click is two clicks about 200–400 ms apart, and the first one
    /// usually *is* the mode change: Finish turns the card into transcribing,
    /// Cancel into the discard notice. The second click then lands on
    /// whatever button now sits under the pointer — Cancel, Undo — and does
    /// the opposite of what the user meant.
    static let clickGuardAfterModeChange: TimeInterval = 0.4
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

    /// The size setting as it stood when this session's card first appeared.
    /// Snapshotted rather than read live, like `showsLiveText`: the panel is
    /// sized from it at the same moment, and a setting flipped while a take
    /// is on screen must not jump the card under the user's pointer.
    var hudSize: HUDSize = HUDSize.defaultValue

    /// Last error surfaced through the failure HUD. Cleared whenever the HUD
    /// transitions away from `.failed`.
    var failureMessage: String = ""
    /// Title of the failure card's action button, or nil for Close only.
    /// Failures whose audio can't possibly succeed on a second pass (too
    /// short) offer nothing; transcription failures offer "Retry"; audio the
    /// speech gate rejected offers "Transcribe Anyway"; a missing permission
    /// offers "Open Settings", because pressing the hotkey again cannot fix it
    /// and the message alone leaves the user hunting.
    var failureActionTitle: String?
    var failureActionIcon: String = "arrow.clockwise"
    /// Samples the failed take captured, at the target rate. Non-zero replaces
    /// the card's "Nothing to review." with how much was captured — the empty
    /// state is for failures that recorded nothing, and a take cut short
    /// mid-sentence is not one of them.
    ///
    /// Deliberately says nothing about whether that audio was *retained*.
    /// Most failures that reach this card cannot offer Retry, so the app has
    /// already dropped the samples by the time it renders; a note promising
    /// they were kept would be a lie on the commonest card in the app.
    var salvagedSampleCount: Int = 0
    /// Whether the failed take's audio was saved to History, which the card
    /// then says — closing it no longer loses anything. Only ever true when
    /// the save really happened; false, with audio captured, makes the card
    /// say it is not saved (the speech gate's rejections aren't kept).
    var failureSavedToHistory: Bool = false
    /// Replaces the failure card's empty-state line ("Nothing to review." /
    /// "N s captured.") when the failure has something more useful to say
    /// there — the paste fallback's "click where it goes" instruction.
    var failureDetail: String?
    /// Key hint on that button — only set where the key is really bound
    /// (Return runs it — Retry, Transcribe on Mac — and nothing is bound to
    /// Open Settings).
    var failureActionHint: String?
    /// A second action beside the first — on the failure card's control row,
    /// or on the review banner after a failed Resume take. "Check API Key"
    /// for a refused key, beside the Retry that works once it's fixed;
    /// "Retry OpenAI" beside a model on this Mac when the balance is empty.
    var secondaryActionTitle: String?
    var secondaryActionIcon: String?

    /// The discard notice's one line ("Dictation discarded").
    var noticeMessage: String = ""
    /// Whether the notice offers Undo. A notice that only says where a
    /// cancelled take went ("saved to History") has nothing to undo.
    var noticeOffersUndo: Bool = false

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
    /// What a transcribing take is waiting on before it can transcribe —
    /// "Downloading" or "Loading" — while a failure card's "Download &
    /// Transcribe" fetches the model on this Mac it chose, or loads one that
    /// isn't warm. Named in the control row in place of "Transcribing", with
    /// the model and its progress in the three `preparing…` fields above. Nil
    /// the rest of the time — for a model that is already warm, the whole
    /// take.
    var transcribingWaitPhase: String?

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
    /// The discard notice's Undo.
    @ObservationIgnored var onUndo: (@MainActor () -> Void)?
    @ObservationIgnored var onSecondaryAction: (@MainActor () -> Void)?
    /// Called when Undo steps back an action.
    @ObservationIgnored var onActionUndone: (@MainActor () -> Void)?

    /// Steps back one action at a time: each call restores the text from
    /// before the most recent transform, so chained actions unwind in order
    /// until the original transcript is back (then the Undo button hides).
    func undoLastAction() {
        guard let original = actionRevertStack.popLast() else { return }
        // The controller decides what the banner shows now: an action's
        // failure goes, a take's own notice stays.
        onActionUndone?()
        // No-op restore would desync the recorded caret from the visible one
        // (the editor skips syncs when the text is unchanged).
        guard original != reviewText else { return }
        selectedRange = NSRange(location: (original as NSString).length, length: 0)
        reviewText = original
    }

    /// Runs a card button's action — unless the card changed mode within
    /// `clickGuardAfterModeChange`, in which case the click was aimed at the
    /// card it replaced and is dropped.
    func click(_ action: (@MainActor () -> Void)?) {
        let sinceModeChange = ProcessInfo.processInfo.systemUptime - modeChangedAt
        guard sinceModeChange >= Self.clickGuardAfterModeChange else {
            AppLog.hud.info("HUD click ignored \(Int(sinceModeChange * 1000)) ms after a mode change")
            return
        }
        action?()
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

    /// Size, position and drag, anchored by the card's bottom-centre so the
    /// card grows upward from where the user last put it.
    let placement = HUDPanelPlacement(
        edge: .bottom,
        anchorsDefaultsKey: LiveHUDPanel.anchorsDefaultsKey
    ) { visible in
        NSPoint(x: visible.midX, y: visible.minY + HUDMetrics.defaultBottomInset)
    }

    /// v2 stores the card's bottom-centre. v1 stored the panel's, which tied
    /// every saved position to `gutter`; those values are dropped on upgrade
    /// and the HUD falls back to the unchanged default placement.
    private static let anchorsDefaultsKey = "hud.panelAnchors.v2"

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
        state.hudSize = HUDSize.current
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
        // A preparing card still on screen is this same take, which took its
        // snapshot when that card appeared. Re-reading here would let a
        // setting flipped during a long download resize the card at the very
        // moment it turns into the recording card.
        let handsOverFromPreparing = state.mode == .preparing && panel?.isVisible == true
        if !handsOverFromPreparing { state.hudSize = HUDSize.current }
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
    /// the control row still shows Cancel here, at the same spot (Finish's
    /// slot is held empty), and by this point cancelling means abandoning the
    /// transcription, not the recording.
    func showTranscribing(onCancel: @escaping @MainActor () -> Void) {
        state.mode = .transcribing
        state.isRecording = false
        state.level = 0
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.transcribingWaitPhase = nil
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
        secondaryActionTitle: String? = nil,
        secondaryActionIcon: String? = nil,
        onSecondaryAction: (@MainActor () -> Void)? = nil,
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
        state.secondaryActionTitle = secondaryActionTitle
        state.secondaryActionIcon = secondaryActionIcon
        state.onSecondaryAction = onSecondaryAction
        state.onRunAction = onRunAction

        present()
        AppLog.hud.info("HUD review shown at \(String(describing: self.panel?.frame))")
    }

    /// A failure, rendered as a banner inside the same card at the same width as
    /// review — the standalone failure panel is gone. `actionTitle` nil leaves
    /// only Close (e.g. "recording too short", where re-running the audio
    /// won't help); "Retry" re-runs the audio; "Open Settings" is what a
    /// permission failure offers instead, since the hotkey can't fix itself.
    func showFailure(
        message: String,
        actionTitle: String?,
        actionIcon: String = "arrow.clockwise",
        actionHint: String? = nil,
        salvagedSampleCount: Int = 0,
        savedToHistory: Bool = false,
        detail: String? = nil,
        secondaryActionTitle: String? = nil,
        secondaryActionIcon: String? = nil,
        onRetry: @escaping @MainActor () -> Void,
        onSecondaryAction: (@MainActor () -> Void)? = nil,
        onCancel: @escaping @MainActor () -> Void
    ) {
        state.mode = .failed
        state.isRecording = false
        state.level = 0
        state.failureMessage = message
        state.failureActionTitle = actionTitle
        state.failureActionIcon = actionIcon
        state.failureActionHint = actionHint
        state.salvagedSampleCount = salvagedSampleCount
        state.failureSavedToHistory = savedToHistory
        state.failureDetail = detail
        state.secondaryActionTitle = secondaryActionTitle
        state.secondaryActionIcon = secondaryActionIcon
        state.onSecondaryAction = onSecondaryAction
        state.preparingMessage = ""
        state.preparingFraction = nil
        state.transcribingWaitPhase = nil
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

    /// The review, a recording or a transcription was just cancelled: the
    /// card shrinks to one line — with Undo when `onUndo` is given — and stops
    /// taking key, which hands the keyboard straight back to the app the user
    /// is in. `DictationController` owns how long it stays.
    func showDiscarded(message: String, onUndo: (@MainActor () -> Void)?) {
        state.mode = .discarded
        state.isRecording = false
        state.level = 0
        state.noticeMessage = message
        state.noticeOffersUndo = onUndo != nil
        state.failureMessage = ""
        state.failureActionTitle = nil
        state.salvagedSampleCount = 0
        state.failureDetail = nil
        state.transcribingElapsedSeconds = 0
        state.transcribingProgress = nil
        state.reviewText = ""
        state.reviewBanner = nil
        state.showsLiveText = false
        state.partialTranscript = ""
        state.resumedSession = false
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = nil
        state.onStop = nil
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil
        state.onUndo = onUndo

        present()
        AppLog.hud.info("HUD discard notice shown")
    }

    /// Takes the discard notice down if it is still what the card shows —
    /// and nothing else: by the time its window lapses a new dictation may
    /// own the panel.
    func hideDiscardedNotice() {
        guard state.mode == .discarded, panel?.isVisible == true else { return }
        hide()
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

    /// The transcribing take is waiting on `modelName` — downloading or
    /// loading it, per `phase` — rather than transcribing. Polled while the
    /// wait lasts; pass nil for `phase` once the model is ready, and the card
    /// goes back to "Transcribing". `fraction` nil keeps the progress
    /// indeterminate.
    func setTranscribingWait(
        phase: String?,
        modelName: String = "",
        fraction: Double? = nil,
        message: String = ""
    ) {
        state.transcribingWaitPhase = phase
        state.preparingModelName = modelName
        state.preparingFraction = fraction
        state.preparingMessage = message
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
        state.salvagedSampleCount = 0
        state.failureSavedToHistory = false
        state.failureDetail = nil
        state.preparingModelName = ""
        state.preparingMessage = ""
        state.preparingFraction = nil
        state.transcribingWaitPhase = nil
        state.reviewShowsActions = false
        state.reviewActions = []
        state.runningActionId = nil
        state.actionRevertStack = []
        state.onPaste = nil
        state.onCancel = nil
        state.onResume = nil
        state.onRetry = nil
        state.onRunAction = nil
        state.onUndo = nil
        state.noticeMessage = ""
        state.noticeOffersUndo = false
        state.secondaryActionTitle = nil
        state.secondaryActionIcon = nil
        state.onSecondaryAction = nil
        panel?.orderOut(nil)
        panel?.acceptsKey = false
        placement.panelHidden()
    }

    /// Whether the given key event was delivered to the HUD while it is showing
    /// the review transcript. Used to keep review-only shortcuts (⌘1–⌘9) from
    /// firing while the user is typing in another of our windows (e.g.
    /// Settings). The mode test is what the second panel used to provide.
    func isReviewPanelEvent(_ event: NSEvent) -> Bool {
        event.window === panel && state.mode == .reviewing
    }

    /// Whether the given key event was delivered to the HUD at all — i.e. the
    /// user was typing into the card, not into another of our windows.
    func isPanelEvent(_ event: NSEvent) -> Bool {
        event.window === panel
    }

    /// Whether the card currently holds key status, so keystrokes go to it
    /// rather than to the app in front.
    var isKey: Bool {
        panel?.isKeyWindow == true
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
            // A card that pops up under a moving pointer is as easy to
            // misclick as one that changed mode under it.
            state.modeChangedAt = ProcessInfo.processInfo.systemUptime
        }

        // The card animates on the same spring, starting in the same runloop
        // turn — that is the whole point of driving the frame from here rather
        // than waiting for SwiftUI to report its new size.
        let animate = wasVisible && HUDFeatureFlags.morphEnabled
        let estimate = layout.estimatedCardSize
        placement.expect(cardSize: estimate, animated: animate)

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
            placement.applyFrame(cardSize: estimate, animated: animate)
        } else {
            placement.applyFrame(cardSize: estimate, animated: animate)
            setKeyEligible(layout.mode.acceptsKey, wasVisible: false)
        }
    }

    private func ensurePanel() -> HUDPanel {
        if let panel { return panel }

        let p = HUDPanel.makeFloating()
        let hosting = FirstMouseHostingView(
            rootView: LiveHUDView(state: state) { size in
                LiveHUDPanel.shared.placement.cardSizeChanged(size)
            }
        )
        hosting.frame = NSRect(origin: .zero, size: p.frame.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        placement.attach(p)
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
}
