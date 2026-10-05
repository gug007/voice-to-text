import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation
import Observation
import OSLog

private final class RecordingEscapeEventTapContext {
    weak var controller: DictationController?
    let swallowState: RecordingEscapeSwallowState
    let allowedModifierFlags: NSEvent.ModifierFlags
    let recordingShortcutKeyCode: UInt16?

    init(
        controller: DictationController,
        swallowState: RecordingEscapeSwallowState,
        allowedModifierFlags: NSEvent.ModifierFlags,
        recordingShortcutKeyCode: UInt16?
    ) {
        self.controller = controller
        self.swallowState = swallowState
        self.allowedModifierFlags = allowedModifierFlags
        self.recordingShortcutKeyCode = recordingShortcutKeyCode
    }
}

/// Backs the global Escape fallback for the review and failure HUDs. Those
/// panels are nonactivating, so when another app is frontmost their local key
/// monitors never fire and Esc is dead — this session-level tap catches Esc and
/// routes it to the right dismissal. `target` picks which HUD is showing (they
/// never overlap), so the same tap serves both. It only takes an Esc meant for
/// the dictation (`RecordingEscapePolicy.hudShouldTakeEscape`); every other
/// one reaches the app it was typed into.
private final class HUDEscapeEventTapContext {
    enum Target {
        case preparing
        case transcribing
        case review
        case failure
    }

    weak var controller: DictationController?
    let target: Target
    /// The app this dictation is aimed at, fixed for the tap's lifetime.
    let pasteTargetPID: pid_t?
    /// Pairs a taken Esc's key-up with its key-down, so the key-up of one the
    /// tap let through still reaches the app that got the key-down.
    let swallowState = RecordingEscapeSwallowState()

    init(controller: DictationController, target: Target, pasteTargetPID: pid_t?) {
        self.controller = controller
        self.target = target
        self.pasteTargetPID = pasteTargetPID
    }
}

@Observable
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case preparing(modelDisplayName: String)
        case recording
        case transcribing
        case reviewing(text: String)
        /// The transcript is committed and on its way into the target app. The
        /// card is already gone, but delivery waits out the hotkey chord and
        /// may hand focus back first — up to about a second in which a second
        /// ⌥Space, Return or toggle used to find `.reviewing` and paste twice.
        /// Always ends in `.idle`, or `.error` when the text fell back to the
        /// clipboard.
        case delivering
        case error(String)
    }

    static let shared = DictationController()

    private(set) var state: State = .idle

    /// Seconds since the current recording began, or nil when nothing is being
    /// recorded. Read by the menu-bar item, which shows the elapsed clock as a
    /// **menu row** rather than in the status-item title: a title that changes
    /// width every second relayouts the status item, and AppKit reflows every
    /// extra to its left each time it does.
    var recordingElapsedSeconds: TimeInterval? {
        guard state == .recording, let recordStart else { return nil }
        return Date().timeIntervalSince(recordStart)
    }

    private let recorder = AudioRecorder()
    private var recordStart: Date?
    private var elapsedTask: Task<Void, Never>?
    private var transcribingElapsedTask: Task<Void, Never>?
    /// Backstop that forces recovery if the machine wedges in `.transcribing`
    /// (a CoreML/VAD inference or network read that never returns). Without it
    /// the hotkey policy maps every press to `.none` and only relaunch recovers.
    private var transcribingWatchdog: Task<Void, Never>?
    /// The same backstop for `.preparing`. Model preparation and the audio
    /// engine each have their own timeouts, but this catches anything that slips
    /// past them — `.preparing` maps every hotkey press to `.none`, so without it
    /// a stuck start is indistinguishable from a dead app.
    private var preparingWatchdog: Task<Void, Never>?
    /// Bumped on each entry into `.transcribing` and on watchdog recovery so a
    /// late-returning pipeline can't clobber a newer state after the watchdog
    /// (or a newer run) has already moved on.
    @ObservationIgnored
    private var transcriptionRunID: UInt64 = 0
    /// Audio of the transcription currently in flight, kept so a watchdog
    /// recovery can preserve it and offer Retry instead of silently dropping a
    /// possibly-valid recording. Overwritten on each run.
    @ObservationIgnored
    private var inFlightTranscriptionSamples: [Float]?
    /// Whether that run is a "Transcribe Anyway", so a watchdog recovery's
    /// Retry doesn't send the audio back through the gate the user overruled.
    @ObservationIgnored
    private var inFlightSkipsSpeechGate = false
    /// The model that run transcribes with, so a cancel or a watchdog
    /// recovery that keeps the audio names the model it was meant for.
    @ObservationIgnored
    private var inFlightModel: ModelDescriptor?
    /// Generous backstop: local engines emit no transcribe progress, so this
    /// can't reset on liveness. Sized well beyond any realistic transcription so
    /// it only catches a genuine wedge; a false fire still preserves the audio.
    /// `nonisolated` so it can be `armTranscribingWatchdog`'s default.
    private nonisolated static let transcribingWatchdogTimeout: Duration = .seconds(600)
    /// The same backstop while the take waits on its model instead
    /// (`modelWait`). A failure card's "Download & Transcribe" fetches up to
    /// 632 MB inside the transcribing state, and on a slow connection that
    /// outlasts the 600 s that bound a transcription: failing a download that
    /// is still moving as "taking too long" throws away the one thing the
    /// user asked for. A dead download doesn't need this to catch it — the
    /// registry gives up on a preparation that makes no progress for two
    /// minutes — so this only bounds one that crawls, or a compile that
    /// never ends. The ordinary budget comes back once the model is ready.
    private static let modelWaitWatchdogTimeout: Duration = .seconds(30 * 60)
    /// Sized past a cold CoreML compile, which `ModelRegistry` deliberately
    /// exempts from its own stall detection and which can legitimately run for
    /// minutes. This only ever fires on a genuine wedge.
    private static let preparingWatchdogTimeout: Duration = .seconds(300)
    /// Pushes `ModelRegistry` progress into the preparing card while it's up.
    /// Polled rather than observed: readiness is written from the engine's own
    /// progress callback at whatever rate it emits, and a fixed 200ms sample is
    /// both smoother on screen and cheaper than an observation re-arm per file.
    private var preparingProgressTask: Task<Void, Never>?
    /// How long preparation may run before the HUD explains itself. A warm model
    /// is ready in milliseconds, so showing the card unconditionally would flash
    /// it on every hotkey press; past this, the wait is long enough that silence
    /// reads as a dead hotkey — which is exactly what a first-run 470MB download
    /// used to look like.
    private static let preparingRevealDelay: Duration = .milliseconds(250)
    /// How much audio a take may lose to mid-recording restarts before the
    /// review card says so.
    ///
    /// Measured restarts run 64–2240 ms. The cheap in-place re-wire lands in
    /// ~330 ms, which costs at most a syllable and is inaudible as a splice;
    /// the fallback rebuild took 2240 ms, which reliably swallows whole words.
    /// At ordinary speech rates a second is two or three words — the point at
    /// which the two halves stop sounding clipped and start joining into a
    /// fluent sentence that is simply wrong. Below it the app stays quiet: a
    /// Bluetooth take renegotiates on essentially every recording, and a
    /// banner that fires every time is a banner nobody reads.
    private static let interruptionBannerThreshold: TimeInterval = 1.0
    private static let preparingProgressInterval: Duration = .milliseconds(200)
    private var preparingEscMonitor: Any?
    private var transcribingEscMonitor: Any?
    private var reviewEscMonitor: Any?
    private var failureEscMonitor: Any?
    private var recordingLocalEscMonitor: Any?
    private var recordingEscEventTap: CFMachPort?
    private var recordingEscRunLoopSource: CFRunLoopSource?
    private var recordingEscEventTapContext: RecordingEscapeEventTapContext?
    /// Global Escape fallback shared by the transcribing, review and failure
    /// HUDs. Only one of those shows at a time, so a single tap serves all three;
    /// each install tears down the prior tap first, and each HUD's monitor
    /// teardown removes it.
    private var hudEscEventTap: CFMachPort?
    private var hudEscRunLoopSource: CFRunLoopSource?
    private var hudEscEventTapContext: HUDEscapeEventTapContext?
    @ObservationIgnored
    private let recordingEscapeSwallowState = RecordingEscapeSwallowState()
    private var recordingStartGate = RecordingStartGate()
    /// Identifies the recording a stop belongs to. `stopAndTranscribe` leaves
    /// `state == .recording` across `flushAndStop`, which can suspend for the
    /// recorder's full 5 s stop timeout when CoreAudio wedges — long enough
    /// for the user to give up, start again, and have a stale stop resume and
    /// take the new take's outcome.
    @ObservationIgnored
    private var takeRunID: UInt64 = 0
    private var standaloneModifierEventCoordinator = StandaloneModifierEventCoordinator()
    private var resumeContext: ResumeContext?
    /// Audio kept around after a recoverable transcription failure so the
    /// user's Retry button can re-run the pipeline on the same samples
    /// (e.g. after a network blip). Backs both the failure HUD's Retry and
    /// the review banner's Retry after a failed Resume take. Cleared on
    /// success, dismissal, paste, review cancel, or when a new recording
    /// starts.
    private var lastFailedSamples: [Float]?
    /// Whether retrying `lastFailedSamples` skips the speech gate — true when
    /// the gate is what failed them. Re-running a take through the gate that
    /// just rejected it would reject it again, so its retry is "Transcribe
    /// Anyway". Written wherever `lastFailedSamples` is, read only with it.
    @ObservationIgnored
    private var retrySkipsSpeechGate = false
    /// The model a failure card's button chose for this take: "Transcribe on
    /// Mac" or "Download & Transcribe", or "Retry OpenAI" taking it back to
    /// the cloud. Every later retry of the take runs on it too — the card's
    /// Retry, Transcribe Anyway, Return, the Resume banner's Retry — since
    /// the model that failed is still out of credit or offline, and a local
    /// model's own failure card doesn't offer it back. Never the dictation
    /// model: it belongs to the take, and goes wherever `lastFailedSamples`
    /// stops meaning this take. Dropped once the user picks another
    /// dictation model in Settings (`retryModel(choosing:)`): that newer
    /// choice is the one a Retry should honour.
    @ObservationIgnored
    private var retryModelOverride: RetryModelOverride?

    private struct RetryModelOverride {
        let model: ModelDescriptor
        /// The dictation model when this one was chosen over it.
        let chosenOverModelID: String?
    }

    /// What Return runs on the failure card: its primary button, when that
    /// button carries the ↩ hint. Stored with the card, because the primary
    /// is no longer always Retry — out of credit it is "Transcribe on Mac",
    /// and a Return that still ran Retry would send the take back to the
    /// account that just refused it. Lives exactly as long as the card's key
    /// monitor (`installFailureEscMonitor`).
    @ObservationIgnored
    private var failureReturnAction: (@MainActor () -> Void)?

    /// The transcribing card's wait on a model on this Mac, from just before
    /// the run prepares it until that returns: "Download & Transcribe"
    /// fetching it, or a model that isn't warm loading. Nil for a cloud
    /// model, a streaming take, and outside that window.
    @ObservationIgnored
    private var modelWait: TakeModelWait?

    private struct TakeModelWait {
        /// The run waiting. Every write to the card is fenced on it.
        let runID: UInt64
        let model: ModelDescriptor
        /// On disk when the run began: preparing it is a load, not a
        /// download — and a failure to prepare it is not a failed download.
        let wasOnDisk: Bool
        let poll: Task<Void, Never>
        /// The card has switched from "Transcribing" to the wait, and the
        /// watchdog to its budget for it.
        var isShown = false
        /// What the card says the run is waiting on, last it looked.
        var phase: DictationRescue.ModelWait
    }

    /// The History row holding the current take's audio. A take is saved the
    /// moment it stops, before the speech gate or any engine can fail it
    /// (`recordPending`), so quitting, a crash or an update relaunch while it
    /// transcribes leaves a row that can be transcribed again. From then on
    /// the take is one row however many tries it takes: the transcript fills
    /// it in, and a failure — or a retry that fails again — updates what it
    /// says went wrong. History off writes nothing ahead; a take that fails is
    /// saved then, when the card goes up. Belongs to the take: cleared when a
    /// new recording starts, or when the take ends with the audio no longer
    /// held for a retry.
    @ObservationIgnored
    private var takeHistoryRow: TakeHistoryRow?

    private struct TakeHistoryRow {
        let id: UUID
        /// Whether a failure card or banner has told the user this take is in
        /// History. Until one has, the row is write-ahead only, and to the
        /// user the take is an ordinary dictation: a review Cancel takes its
        /// row back, and a take of silence leaves none.
        var isSurfaced: Bool
    }

    private var takeRowStage: DictationTakePolicy.RowStage {
        DictationTakePolicy.rowStage(
            hasRow: takeHistoryRow != nil,
            isInHistory: takeRowIsInHistory,
            isSurfaced: takeHistoryRow?.isSurfaced ?? false
        )
    }

    /// Whether the take's row is in History's visible list. Not the store's
    /// own lookups, which also reach a row parked in its delete-undo window:
    /// that row is a timer away from losing its audio, so editing it and
    /// telling the user the take is saved would be a promise History breaks.
    private var takeRowIsInHistory: Bool {
        guard let id = takeHistoryRow?.id else { return false }
        return RecordingHistoryStore.shared.entries.contains { $0.id == id }
    }

    /// Takes the take's row back out of History's undo window, if the user
    /// deleted it — or cleared History — while a card held it for Retry,
    /// and the deletion hasn't committed. Called before anything decides
    /// what the take's row is: the take then settles in that one row, where
    /// filing a second would leave History's Undo to bring the first back
    /// beside it — saying what it said when it was deleted — or bring back
    /// a row of silence the card said was not saved. A row whose deletion
    /// has committed is gone, and the take saves itself afresh.
    private func reclaimTakeRow() {
        guard let id = takeHistoryRow?.id, !takeRowIsInHistory else { return }
        if RecordingHistoryStore.shared.reclaimFromPendingDeletion(id: id) {
            AppLog.dictation.notice("Took the take's row back out of History's undo window")
        }
    }

    /// The History row the failure card or the Resume banner holds for
    /// Retry, while it does. History's "Transcribe with…" refuses it: two
    /// requests on one take would bill twice and race to fill the same row.
    var heldTakeRowID: UUID? {
        guard lastFailedSamples != nil else { return nil }
        return takeHistoryRow?.id
    }

    /// Whether the HUD is showing something the user can still act on with
    /// the session idle: a discard's Undo, the cancelled-transcription
    /// notice, or a failure card. A modal from elsewhere (the update prompt)
    /// would block clicks on it — and a discard's Undo lapses on a timer that
    /// keeps running under the modal, taking the audio with it.
    var isHoldingUserAttention: Bool {
        if case .error = state { return true }
        return discardedRecording != nil || discardedReview != nil || cancelNoticeTask != nil
    }

    /// The row whose transcription is running right now. History shows it as
    /// "Transcribing…" — rather than as the failure its stored status
    /// describes, and without a "Transcribe Again" to race this run — until
    /// `releaseTakeInFlight`, which every way out of the run reaches.
    @ObservationIgnored
    private var inFlightHistoryID: UUID?

    /// A note the next review card must carry, set by a path that ended the
    /// recording early. A take cut short by a device change still produces a
    /// perfectly normal-looking transcript, and a user who is not told it was
    /// cut short will paste it believing it is complete. Kept as a field rather
    /// than threaded through `runTranscriptionPipeline`, which has no business
    /// knowing why its samples stop where they do.
    ///
    /// Setting it also forces the review card for that take, review-before-paste
    /// or not: a notice nobody is shown is not a notice.
    ///
    /// It belongs to the take, not to one card or one attempt: a Resume whose
    /// transcription fails restores the *prior* transcript, and that card must
    /// neither display this note nor destroy it, or the Retry that finally
    /// produces the take's text loses the warning for good. Cleared where the
    /// take itself ends — a new recording, a dismissal, a cancelled review.
    private var pendingReviewBanner: String?

    /// The app that was frontmost when this dictation started — where the
    /// user's caret was, and so where ⌘V is meant to land. Captured on a fresh
    /// start only: a resumed take belongs to the same dictation, and by then
    /// the review card is key. Consulted at delivery by `PasteFocusPolicy`,
    /// which hands activation back to it if something (an update alert, a
    /// Settings window) left *us* as the active app. Cleared where the session
    /// ends.
    @ObservationIgnored
    private var pasteTarget: NSRunningApplication?

    /// The last app other than us to become active. When a dictation starts
    /// with *us* frontmost and nothing of ours on screen — the Settings window
    /// closed, an update alert dismissed with "Later" — this is the app the
    /// user is actually looking at, and the paste is aimed at it instead.
    @ObservationIgnored
    private var lastExternalApp: NSRunningApplication?

    /// The note this take owes its review, consumed as that review is shown.
    /// Called only where the card is showing *this take's* transcript.
    private func takeReviewBanner() -> String? {
        defer { pendingReviewBanner = nil }
        return pendingReviewBanner
    }

    /// In-flight AI action transform on the review text. Cancelled whenever
    /// the review session ends (paste, cancel, resume) so a slow response
    /// can't rewrite text the user already acted on. The generation counter
    /// keeps a cancelled task's cleanup from clobbering a newer run's state.
    @ObservationIgnored
    private var reviewActionTask: Task<Void, Never>?
    @ObservationIgnored
    private var reviewActionGeneration = 0

    /// The active live-streaming session, when the selected engine streams
    /// (e.g. ElevenLabs). Audio is piped to it during recording and it produces
    /// the final transcript via `finishStream()`. Nil for buffered engines and
    /// on the retry path (which falls back to buffered `transcribe`).
    @ObservationIgnored
    private var streamingEngine: (any StreamingTranscriptionEngine)?

    /// The stream detached from `streamingEngine` while its `finishStream()`
    /// runs — which, for a session that dropped, includes re-sending the whole
    /// take. Held so Cancel and the watchdog can stop that too, not just fence
    /// its result.
    @ObservationIgnored
    private var finishingStream: (any StreamingTranscriptionEngine)?

    /// The model that owns the active streaming session, captured at recording
    /// start. Used for History attribution because a streaming transcript is
    /// produced by the already-open session, not by whatever model is active at
    /// stop time (the user can switch models mid-recording).
    @ObservationIgnored
    private var streamingModel: ModelDescriptor?

    /// Whether the active live stream has shown the user any words. A take
    /// the server already heard speech in skips the speech gate: the gate's
    /// only job is to keep silence away from the model, and throwing away
    /// words the user watched appear is the worst thing it could do.
    @ObservationIgnored
    private var streamingShowedText = false

    /// History entry ids for the current review session's takes that haven't
    /// been committed yet. Each successful take is saved immediately (so audio
    /// and transcript stay paired), but if the user discards the review the
    /// entries are retracted — a Cancel must not leave the audio on disk.
    @ObservationIgnored
    private var pendingHistoryIDs: [UUID] = []

    /// The review cancelled most recently, while its Undo notice is up.
    @ObservationIgnored
    private var discardedReview: DiscardedReview?
    @ObservationIgnored
    private var discardUndoTask: Task<Void, Never>?

    /// The recording cancelled most recently, while its Undo notice is up.
    @ObservationIgnored
    private var discardedRecording: DiscardedRecording?
    @ObservationIgnored
    private var discardedRecordingTask: Task<Void, Never>?

    /// Takes down the notice saying where a cancelled transcription went.
    @ObservationIgnored
    private var cancelNoticeTask: Task<Void, Never>?
    /// Long enough to read one line; there is nothing on it to act on.
    private static let cancelNoticeDuration: Duration = .seconds(3)

    /// Snapshot of the review text taken when the user clicks Resume.
    /// Splits the text at the caret so the next transcription can be
    /// spliced into the same position when recording finishes.
    private struct ResumeContext {
        let fullText: String
        let cursorLocation: Int
        let prefix: String
        let suffix: String

        init(fullText: String, cursorLocation: Int) {
            let ns = fullText as NSString
            let safeCursor = max(0, min(cursorLocation, ns.length))
            self.fullText = fullText
            self.cursorLocation = safeCursor
            self.prefix = ns.substring(to: safeCursor)
            self.suffix = ns.substring(from: safeCursor)
        }

        struct Splice {
            let text: String
            let caret: Int
        }

        /// Insert `transcript` at the original caret, adding a single space
        /// on each side only when neither neighbour already provides
        /// whitespace. Returns the caret position right after the insertion.
        func splicing(_ transcript: String) -> Splice {
            let leading = Self.needsSpace(after: prefix, before: transcript) ? " " : ""
            let trailing = Self.needsSpace(after: transcript, before: suffix) ? " " : ""
            let combined = prefix + leading + transcript + trailing + suffix
            let caret = (prefix as NSString).length
                + (leading as NSString).length
                + (transcript as NSString).length
            return Splice(text: combined, caret: caret)
        }

        private static func needsSpace(after left: String, before right: String) -> Bool {
            guard !left.isEmpty, !right.isEmpty else { return false }
            let leftEndsWhitespace = left.last?.isWhitespace ?? false
            let rightStartsWhitespace = right.first?.isWhitespace ?? false
            return !leftEndsWhitespace && !rightStartsWhitespace
        }
    }

    private var reviewBeforePaste: Bool {
        UserDefaults.standard.bool(forKey: "review.beforePaste")
    }

    private init() {
        Task.detached(priority: .utility) {
            await VoiceActivityGate.shared.prewarm()
        }
        // Build the audio engine now, in the background, so the first hotkey
        // press doesn't pay for CoreAudio's device enumeration.
        recorder.prewarm()
        // Quitting takes the discard notice down, so its discard is final —
        // retracted and flushed before exit, or the takes would outlive it.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.discardedReview != nil else { return }
                self.finalizeDiscardedReview()
                RecordingHistoryStore.shared.flush()
            }
        }
    }

    func installHotkey() {
        registerCurrentBinding()
        HotkeyStore.shared.onChange = { [weak self] in
            Task { @MainActor in self?.registerCurrentBinding() }
        }
        installHotkeyHealthObservers()
        installExternalAppTracking()
    }

    /// Keeps `lastExternalApp` current. Seeded from whatever is frontmost now,
    /// then updated on every activation that isn't ours.
    private func installExternalAppTracking() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            lastExternalApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
    }

    /// Headless recovery for the standalone-modifier event tap, which the OS can
    /// silently invalidate (sleep/wake, fast-user-switch, Input-Monitoring/TCC
    /// change) without `retryHotkeyRegistrationIfNeeded`'s window-bound callers
    /// ever firing. Re-checks tap liveness on the events that accompany those
    /// transitions. No-op for the default Carbon hotkey, which can't die this way.
    private func installHotkeyHealthObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retryHotkeyRegistrationIfNeeded() }
            }
        }
    }

    func retryHotkeyRegistrationIfNeeded() {
        guard !HotkeyManager.shared.isHealthy else { return }
        registerCurrentBinding()
    }

    private func registerCurrentBinding() {
        let binding = HotkeyStore.shared.binding
        HotkeyManager.shared.register(binding: binding) { [weak self] event in
            Task { @MainActor in self?.handleHotkeyEvent(event) }
        }
    }

    func toggle() {
        AppLog.dictation.info("toggle called, current state=\(String(describing: self.state))")
        performHotkeyAction(
            DictationHotkeyPolicy.action(
                mode: .toggle,
                state: hotkeyState,
                event: .pressed
            )
        )
    }

    /// Commands accepted from external triggers via the `voicetotext://` URL
    /// scheme. The URL host selects the command, e.g. `voicetotext://toggle`.
    /// Unknown or missing commands fall back to `.toggle`.
    enum ExternalCommand: String, CaseIterable {
        case toggle
        case start
        case stop
        case cancel

        init(url: URL) {
            let host = url.host.flatMap { $0.isEmpty ? nil : $0 }
            let raw = host ?? url.pathComponents.first { $0 != "/" }
            self = raw.flatMap { ExternalCommand(rawValue: $0.lowercased()) } ?? .toggle
        }
    }

    /// Entry point for external triggers (URL scheme). Routes through the same
    /// state-aware policy the global hotkey uses, so behaviour matches exactly.
    /// This never activates the app, so the transcript still pastes into the
    /// frontmost app — i.e. the one whose button was tapped.
    func handleExternalCommand(_ command: ExternalCommand) {
        AppLog.dictation.info(
            "external command \(command.rawValue), current state=\(String(describing: self.state))"
        )
        switch command {
        case .toggle:
            toggle()
        case .start:
            // Start only from a resting state; ignore if already busy.
            switch state {
            case .idle, .error:
                performHotkeyAction(.startRecording)
            default:
                break
            }
        case .stop:
            // Stop & transcribe only while actively recording.
            guard case .recording = state else { return }
            performHotkeyAction(.stopAndTranscribe)
        case .cancel:
            if recordingStartGate.hasActiveStart {
                cancelPendingRecording()
                return
            }
            performHotkeyAction(
                DictationHotkeyPolicy.action(mode: .toggle, state: hotkeyState, event: .cancel)
            )
        }
    }

    func handleHotkeyEvent(_ event: DictationHotkeyEvent) {
        AppLog.dictation.info("hotkey event \(String(describing: event)), current state=\(String(describing: self.state))")
        let mode = HotkeyStore.shared.mode
        let events = standaloneModifierEventCoordinator.normalize(
            event: event,
            mode: mode,
            state: hotkeyState
        )
        for normalizedEvent in events {
            handleNormalizedHotkeyEvent(normalizedEvent, mode: mode)
        }
    }

    private func handleNormalizedHotkeyEvent(
        _ event: DictationHotkeyEvent,
        mode: RecordingShortcutMode
    ) {
        if event == .cancel, recordingStartGate.hasActiveStart {
            cancelPendingRecording()
            return
        }

        if mode == .hold {
            if event == .pressed, recordingStartGate.hasPendingHoldStart {
                return
            }
            if event == .released, recordingStartGate.hasPendingHoldStart {
                cancelPendingRecording()
                return
            }
        }

        let action = DictationHotkeyPolicy.action(
            mode: mode,
            state: hotkeyState,
            event: event
        )
        performHotkeyAction(action, pendingHoldStart: mode == .hold && action == .startRecording)
    }

    private var hotkeyState: DictationHotkeyState {
        switch state {
        case .idle: return .idle
        case .preparing: return .preparing
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .reviewing: return .reviewing
        case .delivering: return .delivering
        case .error: return .error
        }
    }

    private func performHotkeyAction(
        _ action: DictationHotkeyAction,
        pendingHoldStart: Bool = false
    ) {
        switch action {
        case .startRecording:
            guard AccessibilityPermission.isGranted else {
                AccessibilityPermission.promptForPermission()
                AppLog.dictation.warning("Missing Accessibility permission, could not start global hotkey recording")
                // The card, not just the state: macOS only shows its own prompt
                // the first time we ask, so on every press after that this is
                // the sole explanation the user gets for a hotkey that appears
                // to do nothing.
                enterFailureHUD(
                    message: PermissionCopy.accessibilityHUDMessage,
                    action: .openSettings { AccessibilityPermission.openSystemSettings() }
                )
                return
            }
            let startID = recordingStartGate.beginStart(pendingHold: pendingHoldStart)
            Task { await startRecording(startID: startID) }
        case .stopAndTranscribe:
            Task { await stopAndTranscribe() }
        case .confirmPaste:
            confirmPaste()
        case .cancelRecording:
            cancelRecording()
        case .cancelPendingRecording:
            cancelPendingRecording()
        case .none:
            break
        }
    }

    private func cancelRecording() {
        guard state == .recording else { return }
        AppLog.dictation.info("Recording cancelled")
        stopRecording(cancelledByEscape: false)
    }

    private func cancelRecordingFromEscape() {
        guard state == .recording else { return }
        AppLog.dictation.info("Recording cancelled by Escape")
        stopRecording(cancelledByEscape: true)
    }

    private func stopRecording(cancelledByEscape: Bool) {
        standaloneModifierEventCoordinator.reset()
        // A resumed take returns to its review, which holds the card; the
        // notice would have to throw that transcript off screen to show.
        let heldSeconds = recordStart.map { Date().timeIntervalSince($0) } ?? 0
        let holdsForUndo = resumeContext == nil
            && DictationTakePolicy.holdsDiscardedRecording(seconds: heldSeconds)
        endRecordingPhase(removeEscMonitors: !cancelledByEscape)
        // Not awaited: the UI must return to idle immediately, and the engine
        // teardown is blocking CoreAudio work with its own timeout. A take
        // held for Undo keeps what the stop hands back; any other drops it.
        let stop = Task { await recorder.stop() }
        cancelStreamingSession()
        guard holdsForUndo else {
            finishRecordingSession(fallbackTo: .idle)
            return
        }
        offerRecordingUndo(samples: stop)
    }

    /// A recording cancelled mid-take, held in memory while its Undo is on
    /// screen. Nothing is written: a cancel means "not this", and the audio
    /// only survives the few seconds in which it may have been a slip.
    private struct DiscardedRecording {
        /// The take it belongs to, so Undo can never adopt a newer one's.
        let takeRunID: UInt64
        /// The cancelled stop's result. Usually in hand before the notice has
        /// finished appearing; a wedged CoreAudio can hold it up to the
        /// recorder's stop timeout. Replaced when a racing stop turns out to
        /// hold the audio instead (`handOffLateSamples`).
        var samples: Task<[Float], Never>
        let pasteTarget: NSRunningApplication?
    }

    /// The recording card becomes "Recording discarded" with Undo instead of
    /// vanishing: Cancel and Esc sit one slip away from Finish, and minutes of
    /// speech used to go with them for good. The session is over as far as
    /// the user can tell — idle, nothing aimed anywhere — exactly as
    /// `finishRecordingSession` leaves it; only the card stays, to become the
    /// notice. The window matches History's own Undo.
    private func offerRecordingUndo(samples: Task<[Float], Never>) {
        retireNotices()
        discardedRecording = DiscardedRecording(
            takeRunID: takeRunID,
            samples: samples,
            pasteTarget: pasteTarget
        )
        pendingReviewBanner = nil
        pasteTarget = nil
        state = .idle
        LiveHUDPanel.shared.showDiscarded(message: "Recording discarded") { [weak self] in
            self?.undoDiscardedRecording()
        }
        discardedRecordingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(RecordingHistoryStore.undoGraceSeconds))
            guard !Task.isCancelled else { return }
            self?.finalizeDiscardedRecording()
        }
    }

    /// Runs the cancelled take as if Finish had been pressed: transcribed,
    /// saved ahead, and pasted where the recording was aimed.
    private func undoDiscardedRecording() {
        // Idle is the only state the notice lives in; anything else means a
        // new dictation is already under way and owns the session fields.
        guard state == .idle, !recordingStartGate.hasActiveStart,
              let discarded = discardedRecording,
              discarded.takeRunID == takeRunID else { return }
        AppLog.dictation.info("Discarded recording restored")
        discardedRecordingTask?.cancel()
        discardedRecordingTask = nil
        discardedRecording = nil
        lastFailedSamples = nil
        retryModelOverride = nil
        takeHistoryRow = nil
        pendingReviewBanner = nil
        pendingHistoryIDs.removeAll()
        pasteTarget = discarded.pasteTarget
        // Into `.transcribing` before the stop's audio is awaited, as Retry
        // does, so a hotkey press in between maps to nothing instead of
        // starting a take that would race this one.
        enterTranscribing()
        let runID = transcriptionRunID
        Task { @MainActor [weak self] in
            let samples = await discarded.samples.value
            guard let self, self.state == .transcribing, self.transcriptionRunID == runID else { return }
            // Read now, while no newer take has reset it.
            self.noteInterruptionGapIfSignificant()
            switch RecordingSalvage.outcome(
                sampleCount: samples.count,
                minTranscribeSamples: DictationConfig.minTranscribeSamples
            ) {
            case .transcribe:
                await self.runTranscriptionPipeline(samples: samples)
            case .failWithSalvagedAudio:
                self.stopTranscribingElapsedTicker()
                self.enterFailureHUD(message: "Recording too short — try again.", samples: samples)
            case .failEmpty:
                self.stopTranscribingElapsedTicker()
                self.enterFailureHUD(message: "Recording too short — try again.")
            }
        }
    }

    /// Lets the cancelled recording go: its audio is dropped and its notice
    /// taken down if still up. Runs when the Undo window lapses, and early
    /// from anything that takes the card (`retireNotices`). A no-op when
    /// nothing is held.
    private func finalizeDiscardedRecording() {
        discardedRecordingTask?.cancel()
        discardedRecordingTask = nil
        guard discardedRecording != nil else { return }
        discardedRecording = nil
        LiveHUDPanel.shared.hideDiscardedNotice()
    }

    /// Where a cancelled transcription's audio went. It goes by itself and
    /// offers nothing to undo: the take is in History, whose "Transcribe
    /// Again" is the way back to it. A take cancelled while its model was
    /// still downloading says that the download carries on — the registry's,
    /// which the Models pane shows too — so cancelling doesn't read as
    /// having thrown the half-fetched model away.
    private func showCancelledTranscriptionNotice(downloadContinues: Bool) {
        retireNotices()
        LiveHUDPanel.shared.showDiscarded(
            message: downloadContinues
                ? FailureCardCopy.cancelledWhileDownloadingNotice
                : "Transcription cancelled — saved to History",
            onUndo: nil
        )
        cancelNoticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.cancelNoticeDuration)
            guard !Task.isCancelled else { return }
            self?.dismissCancelNotice()
        }
    }

    private func dismissCancelNotice() {
        guard let task = cancelNoticeTask else { return }
        task.cancel()
        cancelNoticeTask = nil
        LiveHUDPanel.shared.hideDiscardedNotice()
    }

    /// Takes down whichever one-line notice is up — making a review's or a
    /// recording's discard final, since its Undo goes with it — for anything
    /// that takes the card: a new dictation, a failure card, another notice.
    /// The notices share one card, so only one is ever up.
    private func retireNotices() {
        finalizeDiscardedReview()
        finalizeDiscardedRecording()
        dismissCancelNotice()
    }

    /// Stops feeding audio to a live-streaming engine and cancels its session
    /// without producing a transcript. Safe to call when no stream is active.
    /// Used on every recording exit path that isn't a normal finish.
    private func cancelStreamingSession() {
        recorder.onAudioChunk = nil
        streamingModel = nil
        streamingShowedText = false
        guard let streaming = streamingEngine else { return }
        streamingEngine = nil
        Task { await streaming.cancelStream() }
    }

    /// Stops a stream whose finish (or automatic re-send) is still running.
    private func cancelFinishingStream() {
        guard let finishing = finishingStream else { return }
        finishingStream = nil
        Task { await finishing.cancelStream() }
    }

    private func cancelPendingRecording() {
        AppLog.dictation.info("Pending recording cancelled")
        standaloneModifierEventCoordinator.reset()
        endPreparingPhase()
        recordingStartGate.cancelActiveStart()
        if case .preparing = state {
            finishRecordingSession(fallbackTo: .idle)
        }
    }

    /// Cancel (or Esc) on the review card. The dictation is gone from the
    /// user's point of view at once, but not yet in fact: for a few seconds the
    /// card shrinks to "Dictation discarded" with Undo, which puts the review
    /// back exactly as it was. Only when that lapses do the takes leave
    /// History (`finalizeDiscardedReview`) — one stray keypress used to
    /// destroy a long dictation for good.
    private func cancelReview() {
        guard case .reviewing = state else { return }
        AppLog.dictation.info("Review cancelled")
        cancelReviewAction()
        removeReviewEscMonitor()
        let discarded = DiscardedReview(
            text: LiveHUDPanel.shared.currentReviewText,
            cursorLocation: LiveHUDPanel.shared.currentCursorLocation,
            banner: LiveHUDState.shared.reviewBanner,
            actionRevertStack: LiveHUDState.shared.actionRevertStack,
            historyIDs: pendingHistoryIDs,
            pasteTarget: pasteTarget,
            bannerRetry: lastFailedSamples != nil ? LiveHUDState.shared.onRetry : nil,
            bannerAction: Self.reviewBannerAction(),
            failedSamples: lastFailedSamples,
            retrySkipsSpeechGate: retrySkipsSpeechGate,
            retryModelOverride: retryModelOverride,
            takeHistoryRow: takeHistoryRow
        )
        lastFailedSamples = nil
        retryModelOverride = nil
        takeHistoryRow = nil
        pendingReviewBanner = nil
        pasteTarget = nil
        pendingHistoryIDs.removeAll()
        state = .idle
        offerUndo(for: discarded)
    }

    /// A review the user just cancelled, held for as long as its Undo is on
    /// screen: what `enterReview` needs to put the card back, plus the session
    /// state the cancel cleared — so Undo is the cancel never having happened.
    private struct DiscardedReview {
        let text: String
        let cursorLocation: Int
        let banner: String?
        let actionRevertStack: [String]
        /// Takes still in History (and on disk) until the discard is final.
        let historyIDs: [UUID]
        let pasteTarget: NSRunningApplication?
        /// The banner's Retry for a failed Resume take, as it was: one the
        /// banner dropped — out of credit, where the empty balance would
        /// only refuse it again — stays dropped.
        let bannerRetry: (@MainActor () -> Void)?
        /// The banner's own action beside Retry ("Check API Key", "Transcribe
        /// on Mac"), if any.
        let bannerAction: FailureAction?
        /// A failed Resume take's audio, behind the banner's Retry, and the
        /// History row it was saved to. That row is not among `historyIDs`:
        /// a failed take stays in History whatever becomes of the review.
        let failedSamples: [Float]?
        let retrySkipsSpeechGate: Bool
        let retryModelOverride: RetryModelOverride?
        let takeHistoryRow: TakeHistoryRow?
    }

    /// Shown in place of the review card; the takes go when it lapses. The
    /// window matches History's own Undo, so a discard is exactly as
    /// recoverable wherever it happens.
    private func offerUndo(for discarded: DiscardedReview) {
        finalizeDiscardedReview()
        discardedReview = discarded
        // Says where the takes are going, so Undo reads as the way to keep
        // them. Sized for the notice's one line beside Undo. With nothing
        // pending in History (History off, or only a failed take, which stays)
        // there is nothing to say about it.
        let message = discarded.historyIDs.isEmpty ? "Dictation discarded" : "Discarded — leaving History"
        LiveHUDPanel.shared.showDiscarded(message: message) { [weak self] in
            self?.undoDiscardedReview()
        }
        discardUndoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(RecordingHistoryStore.undoGraceSeconds))
            guard !Task.isCancelled else { return }
            self?.finalizeDiscardedReview()
        }
    }

    private func undoDiscardedReview() {
        // Idle is the only state the notice lives in; anything else means a
        // new dictation is already under way and owns the session fields.
        guard state == .idle, !recordingStartGate.hasActiveStart,
              let discarded = discardedReview else { return }
        AppLog.dictation.info("Discarded review restored")
        discardUndoTask?.cancel()
        discardUndoTask = nil
        discardedReview = nil
        pendingHistoryIDs = discarded.historyIDs
        pasteTarget = discarded.pasteTarget
        lastFailedSamples = discarded.failedSamples
        retrySkipsSpeechGate = discarded.retrySkipsSpeechGate
        retryModelOverride = discarded.retryModelOverride
        takeHistoryRow = discarded.takeHistoryRow
        enterReview(
            text: discarded.text,
            cursorLocation: discarded.cursorLocation,
            banner: discarded.banner,
            bannerRetry: discarded.bannerRetry,
            bannerAction: discarded.bannerAction
        )
        LiveHUDState.shared.actionRevertStack = discarded.actionRevertStack
    }

    /// The extra action on the review banner right now, read back off the
    /// card so a discarded review's Undo can put it back.
    private static func reviewBannerAction() -> FailureAction? {
        let hud = LiveHUDState.shared
        guard let title = hud.secondaryActionTitle, let run = hud.onSecondaryAction else { return nil }
        return FailureAction(title: title, icon: hud.secondaryActionIcon ?? "key.fill", hint: nil, run: run)
    }

    /// Makes the last cancelled review's discard final: its takes leave
    /// History and the disk, and its notice goes if it is still up. Runs when
    /// the Undo window lapses, and early from anything that takes the notice
    /// off screen — a new dictation, a failure card, quitting — because its
    /// Undo goes with it. A no-op when nothing is pending.
    private func finalizeDiscardedReview() {
        discardUndoTask?.cancel()
        discardUndoTask = nil
        guard let discarded = discardedReview else { return }
        discardedReview = nil
        for id in discarded.historyIDs {
            RecordingHistoryStore.shared.retract(id: id)
        }
        LiveHUDPanel.shared.hideDiscardedNotice()
    }

    /// Keeps the current review session's saved takes in History.
    private func commitPendingHistory() {
        pendingHistoryIDs.removeAll()
    }

    /// Retracts (deletes) the current review session's saved takes at once,
    /// for a session that ends with no review to undo back to — a cancelled
    /// transcription, a dismissed failure. A cancelled review goes through
    /// `cancelReview`'s Undo instead.
    private func discardPendingHistory() {
        for id in pendingHistoryIDs {
            RecordingHistoryStore.shared.retract(id: id)
        }
        pendingHistoryIDs.removeAll()
    }

    private func dismissFailure() {
        guard case .error = state else { return }
        AppLog.dictation.info("Failure HUD dismissed")
        removeFailureEscMonitor()
        lastFailedSamples = nil
        retryModelOverride = nil
        // Its row stays in History, where "Transcribe Again" picks it up.
        takeHistoryRow = nil
        pendingReviewBanner = nil
        pasteTarget = nil
        // Safety net: a discarded session shouldn't leave takes behind.
        discardPendingHistory()
        LiveHUDPanel.shared.hide()
        state = .idle
    }

    /// The "Esc cancels dictation" setting is read once here, as the phase
    /// begins: a change in Settings takes effect on the next dictation rather
    /// than arming or tearing down a session-wide tap mid-recording. Off means
    /// neither the tap nor the local monitor is installed, so Esc reaches the
    /// frontmost app untouched — and there is nothing to fail, hence `true`.
    private func installRecordingEscMonitors() -> Bool {
        removeRecordingEscMonitors()
        guard HotkeyStore.shared.escapeCancelsDictation else { return true }
        let escapeSwallowState = recordingEscapeSwallowState
        let allowedModifierFlags = recordingEscapeAllowedModifierFlags
        let recordingShortcutKeyCode = recordingEscapeShortcutKeyCode
        recordingLocalEscMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.type == .keyUp,
               RecordingEscapePolicy.isEscape(keyCode: event.keyCode),
               escapeSwallowState.finishIfNeeded() {
                Task { @MainActor in self?.removeRecordingEscMonitors() }
                return nil
            }

            guard RecordingEscapePolicy.shouldStartCancel(
                isKeyDown: event.type == .keyDown,
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                allowedModifierFlags: allowedModifierFlags,
                recordingShortcutKeyCode: recordingShortcutKeyCode
            ) else { return event }
            if escapeSwallowState.begin() {
                Task { @MainActor in self?.cancelRecordingFromEscape() }
            }
            return nil
        }

        let context = RecordingEscapeEventTapContext(
            controller: self,
            swallowState: recordingEscapeSwallowState,
            allowedModifierFlags: allowedModifierFlags,
            recordingShortcutKeyCode: recordingShortcutKeyCode
        )
        recordingEscEventTapContext = context
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<RecordingEscapeEventTapContext>.fromOpaque(userData).takeUnretainedValue()
                guard let controller = context.controller else { return Unmanaged.passUnretained(event) }

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { controller.enableRecordingEscEventTap() }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                if type == .keyUp,
                   RecordingEscapePolicy.isEscape(keyCode: keyCode),
                   context.swallowState.finishIfNeeded() {
                    DispatchQueue.main.async { controller.removeRecordingEscMonitors() }
                    return nil
                }

                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                guard RecordingEscapePolicy.shouldStartCancel(
                    isKeyDown: type == .keyDown,
                    keyCode: keyCode,
                    modifierFlags: flags,
                    allowedModifierFlags: context.allowedModifierFlags,
                    recordingShortcutKeyCode: context.recordingShortcutKeyCode
                ) else {
                    return Unmanaged.passUnretained(event)
                }

                if context.swallowState.begin() {
                    DispatchQueue.main.async { controller.cancelRecordingFromEscape() }
                }
                return nil
            },
            userInfo: contextPtr
        ) else {
            AppLog.dictation.error("Recording Escape event tap creation failed")
            removeRecordingEscMonitors()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        recordingEscEventTap = tap
        recordingEscRunLoopSource = source
        enableRecordingEscEventTap()
        return true
    }

    private var recordingEscapeAllowedModifierFlags: NSEvent.ModifierFlags {
        guard HotkeyStore.shared.mode == .hold else { return [] }
        return Self.eventModifierFlags(forCarbonModifiers: HotkeyStore.shared.binding.modifiers)
    }

    private var recordingEscapeShortcutKeyCode: UInt16? {
        guard HotkeyStore.shared.mode == .hold else { return nil }
        return UInt16(truncatingIfNeeded: HotkeyStore.shared.binding.keyCode)
    }

    private static func eventModifierFlags(forCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    private func enableRecordingEscEventTap() {
        guard let recordingEscEventTap else { return }
        CGEvent.tapEnable(tap: recordingEscEventTap, enable: true)
    }

    private func removeRecordingEscMonitors() {
        recordingEscapeSwallowState.reset()
        if let recordingLocalEscMonitor {
            NSEvent.removeMonitor(recordingLocalEscMonitor)
            self.recordingLocalEscMonitor = nil
        }
        if let recordingEscRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), recordingEscRunLoopSource, .commonModes)
            self.recordingEscRunLoopSource = nil
        }
        if let recordingEscEventTap {
            CFMachPortInvalidate(recordingEscEventTap)
            self.recordingEscEventTap = nil
        }
        recordingEscEventTapContext = nil
    }

    /// Esc during transcribing aborts the in-flight transcription — the same
    /// thing the HUD's Cancel button does. The recording taps are already gone
    /// by this point and the panel deliberately isn't key here (the caret has to
    /// stay in the target app), so the global tap does the real work and the
    /// local monitor only covers the case where our app happens to be active.
    /// Skipped entirely when "Esc cancels dictation" is off, read once as this
    /// phase begins for the same reason `installRecordingEscMonitors` does.
    /// The review and failure cards differ only in that Esc typed into them
    /// while they are key always works (see `hudTakesLocalEscape`).
    private func installTranscribingEscMonitor() {
        removeTranscribingEscMonitor()
        guard HotkeyStore.shared.escapeCancelsDictation else { return }
        transcribingEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let takes = MainActor.assumeIsolated {
                self?.hudTakesLocalEscape(event, escapeCancelsDictation: true) ?? false
            }
            guard takes else { return event }
            Task { @MainActor in self?.cancelTranscription() }
            return nil
        }
        installHUDEscapeEventTap(target: .transcribing)
    }

    /// Whether an Esc that reached one of our local monitors belongs to the
    /// dictation's card. Local monitors see every key event our app gets, so
    /// without this an Esc typed into Settings — while the dictation is aimed
    /// at another app — would discard it too.
    private func hudTakesLocalEscape(_ event: NSEvent, escapeCancelsDictation: Bool) -> Bool {
        RecordingEscapePolicy.shouldCancel(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
            && RecordingEscapePolicy.hudShouldTakeEscape(
                escapeCancelsDictation: escapeCancelsDictation,
                panelIsKey: LiveHUDPanel.shared.isPanelEvent(event),
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                pasteTargetPID: pasteTarget?.processIdentifier
            )
    }

    private func removeTranscribingEscMonitor() {
        if let transcribingEscMonitor {
            NSEvent.removeMonitor(transcribingEscMonitor)
            self.transcribingEscMonitor = nil
        }
        removeHUDEscapeEventTap()
    }

    private func installReviewEscMonitor() {
        removeReviewEscMonitor()
        let escapeCancels = HotkeyStore.shared.escapeCancelsDictation
        // Local monitor: our review panel is key, so Esc is dispatched into our app.
        reviewEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                let takes = MainActor.assumeIsolated {
                    self?.hudTakesLocalEscape(event, escapeCancelsDictation: escapeCancels) ?? false
                }
                guard takes else { return event }
                // One press, one step, as the tap does it: the first Esc may
                // only stop an action, so a held one's auto-repeat would go on
                // to cancel the review. Swallowed, so it reaches nothing else.
                guard !event.isARepeat else { return nil }
                // Stops a running action, or clears its failure, before it
                // cancels anything (`handleReviewEscape`).
                Task { @MainActor in self?.handleReviewEscape() }
                return nil
            }
            // ⌘R resumes recording with the new transcript spliced at the caret.
            // Matched like a menu key equivalent, so it survives a Cyrillic
            // layout (whose R key types "к") without breaking Dvorak.
            // ⌘ and nothing else that changes a shortcut. Caps Lock (and the
            // numeric-pad / fn bits) are ignored, as menu key equivalents
            // ignore them.
            let isCommandOnly = event.modifierFlags
                .intersection([.command, .option, .control, .shift]) == .command
            if ReviewResumeShortcut.matches(
                isCommandOnly: isCommandOnly,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                commandLayerCharacters: event.characters(byApplyingModifiers: .command)
            ) {
                Task { @MainActor in self?.resumeRecording() }
                return nil
            }
            // ⌘1–⌘9 run the matching review action. Matched by physical key
            // (kVK_ANSI_*) so layouts with shifted digit rows (e.g. AZERTY)
            // work; checked synchronously against this session's snapshot so
            // the shortcut always mirrors the visible chips and the event
            // passes through untouched otherwise; scoped to the review panel
            // so keystrokes in Settings can't rewrite the transcript.
            if isCommandOnly,
               let digit = Self.reviewActionDigitKeyCodes[event.keyCode] {
                let handlesDigit = MainActor.assumeIsolated {
                    LiveHUDPanel.shared.isReviewPanelEvent(event)
                        && LiveHUDState.shared.reviewShowsActions
                        && LiveHUDState.shared.reviewActions.indices.contains(digit - 1)
                }
                guard handlesDigit else { return event }
                Task { @MainActor in self?.runReviewAction(atIndex: digit - 1) }
                return nil
            }
            return event
        }
        // Global fallback: the local monitor above only fires while our app is
        // active. When the user has switched back to the app they were
        // dictating into, this session-level tap keeps Esc-to-cancel working
        // there — and only there. ⌘R / ⌘1–9 stay local-only on purpose (they
        // must never fire from another app's keystrokes).
        installHUDEscapeEventTap(target: .review)
    }

    private func removeReviewEscMonitor() {
        if let reviewEscMonitor {
            NSEvent.removeMonitor(reviewEscMonitor)
            self.reviewEscMonitor = nil
        }
        removeHUDEscapeEventTap()
    }

    /// Failure HUD shares the key-accepting review panel, so Esc and Return
    /// land as local key events: Esc dismisses, Return runs the card's
    /// primary button — Retry, Transcribe Anyway, Transcribe on Mac — when it
    /// shows the ↩ (`failureReturnAction`, set once this is installed).
    private func installFailureEscMonitor() {
        removeFailureEscMonitor()
        let escapeCancels = HotkeyStore.shared.escapeCancelsDictation
        failureEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                let takes = MainActor.assumeIsolated {
                    self?.hudTakesLocalEscape(event, escapeCancelsDictation: escapeCancels) ?? false
                }
                guard takes else { return event }
                Task { @MainActor in self?.dismissFailure() }
                return nil
            }
            // Return only when typed into the card: this monitor sees every
            // window of ours, and Return in Settings — submitting the API key
            // the card just sent the user to fix — is that field's.
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter),
               MainActor.assumeIsolated({ LiveHUDPanel.shared.isPanelEvent(event) }) {
                // The card takes key as it appears, so the editor's next
                // Return — or the auto-repeat of one still held — lands here
                // instead. A primary may start a download, so only a fresh,
                // bare Return runs it; the rest are swallowed, as a stray key
                // on the card should be.
                let isBare = event.modifierFlags.intersection([.command, .option, .control]).isEmpty
                guard !event.isARepeat, isBare else { return nil }
                Task { @MainActor in self?.runFailureReturnAction() }
                return nil
            }
            return event
        }
        // Global fallback for Esc-to-dismiss when another app is frontmost (see
        // installReviewEscMonitor). Return stays local-only: pressing Return
        // in another app must not fire the card's primary.
        installHUDEscapeEventTap(target: .failure)
    }

    private func removeFailureEscMonitor() {
        failureReturnAction = nil
        if let failureEscMonitor {
            NSEvent.removeMonitor(failureEscMonitor)
            self.failureEscMonitor = nil
        }
        removeHUDEscapeEventTap()
    }

    /// Return on the failure card. Each primary guards its own state too; a
    /// card with no ↩ on its primary (Open Settings) has nothing bound. It
    /// goes through the same guard as a click (`LiveHUDState.click`): a
    /// Return typed while the card was still "Transcribing" was meant for
    /// the editor, not for a card nobody has read yet.
    private func runFailureReturnAction() {
        guard case .error = state, let action = failureReturnAction else { return }
        LiveHUDState.shared.click(action)
    }

    /// Installs the session-level Escape tap that backs the review/failure HUDs
    /// when our app is inactive. Mirrors the recording-Escape tap's lifecycle but
    /// stays deliberately narrow: it takes only a bare Escape meant for the
    /// dictation (`RecordingEscapePolicy.hudShouldTakeEscape`) — both edges, so
    /// no stray key-up leaks to the frontmost app — and acts on key-down; every
    /// other key, and every other Escape, passes straight through untouched.
    /// Not installed at all with "Esc cancels dictation" off. Non-fatal on
    /// failure — the local monitor still covers the app-active case, so unlike
    /// the recording tap a creation failure doesn't tear the HUD down.
    private func installHUDEscapeEventTap(target: HUDEscapeEventTapContext.Target) {
        removeHUDEscapeEventTap()
        guard HotkeyStore.shared.escapeCancelsDictation else { return }

        let context = HUDEscapeEventTapContext(
            controller: self,
            target: target,
            pasteTargetPID: pasteTarget?.processIdentifier
        )
        hudEscEventTapContext = context
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<HUDEscapeEventTapContext>.fromOpaque(userData).takeUnretainedValue()
                guard let controller = context.controller else { return Unmanaged.passUnretained(event) }

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { controller.enableHUDEscapeEventTap() }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                guard RecordingEscapePolicy.isEscape(keyCode: keyCode) else {
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyUp {
                    return context.swallowState.finishIfNeeded() ? nil : Unmanaged.passUnretained(event)
                }
                // An Esc still held from before this tap existed — the one
                // that just cancelled a resumed recording, say — repeats into
                // it; acting on that would discard the review it restored.
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                   !context.swallowState.isSwallowing {
                    return Unmanaged.passUnretained(event)
                }
                // The tap's run-loop source is on the main run loop, so this
                // callback is already on the main thread. Read at the keypress,
                // not at install: the user moves between apps while the card
                // is up.
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                let takes = MainActor.assumeIsolated {
                    RecordingEscapePolicy.shouldCancel(keyCode: keyCode, modifierFlags: flags)
                        && RecordingEscapePolicy.hudShouldTakeEscape(
                            // Installed only while the setting is on.
                            escapeCancelsDictation: true,
                            panelIsKey: LiveHUDPanel.shared.isKey,
                            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                            pasteTargetPID: context.pasteTargetPID
                        )
                }
                guard takes else { return Unmanaged.passUnretained(event) }
                // Swallow both edges and any auto-repeat; dismiss once.
                if context.swallowState.begin() {
                    DispatchQueue.main.async {
                        controller.handleHUDEscape(target: context.target)
                    }
                }
                return nil
            },
            userInfo: contextPtr
        ) else {
            AppLog.dictation.error("HUD Escape event tap creation failed")
            hudEscEventTapContext = nil
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        hudEscEventTap = tap
        hudEscRunLoopSource = source
        enableHUDEscapeEventTap()
    }

    private func enableHUDEscapeEventTap() {
        guard let hudEscEventTap else { return }
        CGEvent.tapEnable(tap: hudEscEventTap, enable: true)
    }

    private func removeHUDEscapeEventTap() {
        if let hudEscRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hudEscRunLoopSource, .commonModes)
            self.hudEscRunLoopSource = nil
        }
        if let hudEscEventTap {
            CFMachPortInvalidate(hudEscEventTap)
            self.hudEscEventTap = nil
        }
        hudEscEventTapContext = nil
    }

    /// Routes a global-tap Escape to the dismissal for whichever HUD is showing.
    /// Every dismissal guards its own state and tears the tap down, so a late
    /// Escape after the HUD already closed is a harmless no-op. The review's
    /// first Esc may only stop an action or clear its failure, leaving the card
    /// — and this tap — up for the next one.
    private func handleHUDEscape(target: HUDEscapeEventTapContext.Target) {
        switch target {
        case .preparing:
            cancelPendingRecording()
        case .transcribing:
            cancelTranscription()
        case .review:
            handleReviewEscape()
        case .failure:
            dismissFailure()
        }
    }

    // MARK: - Start

    private func startRecording(startID: RecordingStartGate.StartID) async {
        guard recordingStartGate.accepts(startID) else { return }
        // A new dictation takes the card, and any notice's Undo with it.
        retireNotices()
        removeFailureEscMonitor()
        lastFailedSamples = nil
        retryModelOverride = nil
        // A row left by the previous take stays in History; it just isn't
        // this take's.
        takeHistoryRow = nil
        releaseTakeInFlight()
        pendingReviewBanner = nil
        // A fresh dictation (not a Resume) starts a new review session: forget
        // any uncommitted history ids left over from a prior session so they
        // aren't retracted by this one's Cancel. (Resume keeps accumulating.)
        if resumeContext == nil { pendingHistoryIDs.removeAll() }
        // Where this dictation is aimed, taken before the first await so a
        // slow permission prompt or model load can't change the answer. A
        // Resume keeps the original: the review card is key by now, and the
        // resumed take pastes wherever the first one was going.
        if resumeContext == nil { pasteTarget = capturePasteTarget() }
        AppLog.dictation.info("startRecording: requesting mic permission (current=\(String(describing: MicPermission.status.rawValue)))")
        let granted = await MicPermission.request()
        AppLog.dictation.info("startRecording: mic permission granted=\(granted)")
        guard recordingStartGate.accepts(startID) else { return }
        guard granted else {
            recordingStartGate.finish(startID)
            enterFailureHUD(
                message: PermissionCopy.microphoneHUDMessage,
                action: .openSettings { MicPermission.openSystemSettings() }
            )
            return
        }

        guard let descriptor = ModelRegistry.shared.activeModel else {
            AppLog.dictation.error("startRecording: no active model")
            recordingStartGate.finish(startID)
            enterFailureHUD(message: "No active model selected.")
            return
        }

        // A cloud model with no key can only fail deep inside `prepareModel`,
        // with a message that sends the user hunting through Settings. Catch it
        // here and put the key field one click away instead.
        if let provider = descriptor.backend.cloudProvider, !provider.hasAPIKey {
            AppLog.dictation.error("startRecording: \(descriptor.id) has no API key")
            recordingStartGate.finish(startID)
            enterFailureHUD(
                message: "\(descriptor.displayName) needs an \(provider.displayName) API key.",
                action: .addAPIKey { WindowOpener.shared.showMain(section: .cloud) }
            )
            return
        }

        AppLog.dictation.info("startRecording: active model=\(descriptor.id)")
        guard recordingStartGate.accepts(startID) else { return }
        state = .preparing(modelDisplayName: descriptor.displayName)
        beginPreparingPhase(
            startID: startID,
            descriptor: descriptor,
            isResume: resumeContext != nil
        )
        let preparedModel = await ModelRegistry.shared.prepareModel(id: descriptor.id)
        guard recordingStartGate.accepts(startID) else { return }
        guard let engine = preparedModel else {
            AppLog.dictation.error("startRecording: prepareModel returned nil")
            recordingStartGate.finish(startID)
            enterFailureHUD(message: preparationErrorMessage(for: descriptor))
            return
        }

        do {
            guard recordingStartGate.accepts(startID) else { return }
            recorder.onConfigurationChange = { [weak self] samples in
                Task { await self?.handleAudioConfigurationChange(salvagedSamples: samples) }
            }
            recorder.onLevel = { level in
                LiveHUDPanel.shared.setLevel(level)
            }

            // Live-streaming engines: open the session and pipe audio in as it's
            // captured so partial transcripts show in the HUD while recording.
            // If the session can't open (auth/network), fall back to buffered.
            streamingEngine = nil
            streamingModel = nil
            streamingShowedText = false
            recorder.onAudioChunk = nil
            if let streaming = engine as? any StreamingTranscriptionEngine {
                do {
                    try await streaming.startStream(contextPrompt: nil) { live in
                        Task { @MainActor in
                            LiveHUDPanel.shared.setPartialTranscript(live)
                            DictationController.shared.noteLiveText(live, from: streaming)
                        }
                    }
                    guard recordingStartGate.accepts(startID) else {
                        await streaming.cancelStream()
                        return
                    }
                    streamingEngine = streaming
                    streamingModel = descriptor
                    recorder.onAudioChunk = { samples in
                        streaming.feedAudio(samples)
                    }
                } catch {
                    AppLog.dictation.error("ElevenLabs stream failed to open: \(error.localizedDescription); using buffered transcription")
                }
            }

            // Awaited, not called inline: the engine lifecycle is blocking
            // CoreAudio IPC that used to freeze the main thread — and with it
            // the global hotkey — for as long as the device took to answer.
            try await recorder.start()
            guard recordingStartGate.accepts(startID) else {
                _ = await recorder.stop()
                cancelStreamingSession()
                return
            }
            state = .recording
            takeRunID &+= 1
            // Before the recording card and its own Esc tap go up: the preparing
            // card hands over to them, and two session taps must never coexist.
            endPreparingPhase()
            recordingStartGate.finish(startID)
            let start = Date()
            recordStart = start
            // Resuming from review: keep the prior transcript on screen and
            // stream new words in at the caret, instead of the fresh-recording
            // HUD which clears the screen.
            if let resume = resumeContext {
                LiveHUDPanel.shared.showResumeRecording(
                    prefix: resume.prefix,
                    suffix: resume.suffix,
                    showsLiveText: streamingEngine != nil,
                    onStop: { [weak self] in Task { await self?.stopAndTranscribe() } },
                    onCancel: { [weak self] in self?.cancelRecording() }
                )
            } else {
                LiveHUDPanel.shared.show(
                    showsLiveText: streamingEngine != nil,
                    onStop: { [weak self] in Task { await self?.stopAndTranscribe() } },
                    onCancel: { [weak self] in self?.cancelRecording() }
                )
            }
            guard installRecordingEscMonitors() else {
                _ = await recorder.stop()
                cancelStreamingSession()
                enterFailureHUD(
                    message: "Esc cancel could not be enabled. Check Accessibility or Input Monitoring in System Settings, then try again.",
                    action: .openSettings { AccessibilityPermission.openSystemSettings() }
                )
                return
            }
            startElapsedTicker(from: start)
            AppLog.dictation.notice("startRecording: recording started")
        } catch {
            recordingStartGate.finish(startID)
            cancelStreamingSession()
            AppLog.dictation.error("Recorder start failed: \(error.localizedDescription)")
            enterFailureHUD(message: "Could not start recording: \(error.localizedDescription)")
        }
    }

    /// Only this take's own session counts: a torn-down one's last update
    /// must not vouch for the next take.
    private func noteLiveText(_ text: String, from stream: any StreamingTranscriptionEngine) {
        guard streamingEngine === stream,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        streamingShowedText = true
    }

    private func startElapsedTicker(from start: Date) {
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .recording else { return }
                LiveHUDPanel.shared.setElapsed(Date().timeIntervalSince(start))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopElapsedTicker() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private func enterTranscribing() {
        // Idempotent: retryTranscription enters transcribing synchronously
        // to close a state-race, and runTranscriptionPipeline calls this
        // again on its normal path. Skipping the duplicate keeps the elapsed
        // ticker from resetting to 0 mid-retry.
        guard state != .transcribing else { return }
        transcriptionRunID &+= 1
        state = .transcribing
        LiveHUDPanel.shared.showTranscribing(
            onCancel: { [weak self] in self?.cancelTranscription() }
        )
        installTranscribingEscMonitor()
        startTranscribingElapsedTicker(from: Date())
        armTranscribingWatchdog(runID: transcriptionRunID)
    }

    /// Abandons an in-flight transcription from the HUD's Cancel button or Esc
    /// — the only way out of a hung cloud request short of the 10-minute
    /// watchdog. The pipeline is fenced on the run ID rather than cancelled:
    /// every `await` in `runTranscriptionPipeline` re-checks it, so the
    /// abandoned run returns silently instead of pushing a review or a failure
    /// HUD onto an app the user already sent back to idle.
    ///
    /// Cancelling the request is not cancelling the words: a take long enough
    /// to be real dictation stays in History as untranscribed
    /// (`settleCancelledTake`), and the card says so on its way out.
    private func cancelTranscription() {
        guard state == .transcribing else { return }
        AppLog.dictation.info("Transcription cancelled")
        // Read before the run fence moves: only this run's wait counts. The
        // download itself is the registry's and is left running, for next
        // time — this take no longer waits for it.
        let downloadContinues = isWaitingOnDownload(runID: transcriptionRunID)
        transcriptionRunID &+= 1
        cancelModelWait()
        removeTranscribingEscMonitor()
        stopTranscribingElapsedTicker()
        cancelStreamingSession()
        cancelFinishingStream()
        let saved = settleCancelledTake()
        inFlightTranscriptionSamples = nil
        inFlightModel = nil
        lastFailedSamples = nil
        retryModelOverride = nil
        // A resumed take returns to the review it came from (whose earlier
        // takes are still pending and must survive); a first-pass take ends the
        // session, so anything it left behind goes with it.
        if resumeContext == nil { discardPendingHistory() }
        guard resumeContext == nil, saved else {
            finishRecordingSession(
                fallbackTo: .idle,
                banner: saved ? "Transcription cancelled — recording saved to History." : nil
            )
            return
        }
        // The session ends as `finishRecordingSession` ends it, but the card
        // stays to say where the audio went rather than vanishing with it.
        pendingReviewBanner = nil
        pasteTarget = nil
        state = .idle
        showCancelledTranscriptionNotice(downloadContinues: downloadContinues)
    }

    /// What a cancel leaves of the take in flight, per `DictationTakePolicy`:
    /// a real take stays in History as untranscribed, a few seconds' worth is
    /// let go, and one the user was already told is saved stays as it was.
    /// Returns whether the take is in History now. Ends the take's hold on
    /// its row either way — a late result from the cancelled run is fenced
    /// off, so nothing will come back to fill it.
    private func settleCancelledTake() -> Bool {
        defer {
            takeHistoryRow = nil
            releaseTakeInFlight()
        }
        reclaimTakeRow()
        let samples = inFlightTranscriptionSamples ?? []
        let seconds = Double(samples.count) / AudioConfig.targetSampleRate
        switch DictationTakePolicy.disposition(for: .cancelled(seconds: seconds), row: takeRowStage) {
        case .keepFailed:
            AppLog.dictation.notice("Kept the cancelled take in History (\(seconds, format: .fixed(precision: 1))s)")
            return holdFailedTakeInHistory(
                samples: samples,
                model: inFlightModel,
                status: .init(kind: .failed, message: "Transcription was cancelled before it finished.")
            )
        case .retract:
            retractTakeRow()
            return false
        case .leave:
            guard let id = takeHistoryRow?.id else { return false }
            return RecordingHistoryStore.shared.entries.contains { $0.id == id }
        case .keepTranscript:
            return false
        }
    }

    /// Everything that runs for the length of the `.preparing` state: the
    /// watchdog, and — unless this start came out of a review — the card that
    /// tells the user what the app is waiting on.
    ///
    /// A resumed take deliberately shows nothing: its review card is still on
    /// screen holding the transcript, and its model is the one that just
    /// transcribed (so preparation is a cache hit). Replacing that card with a
    /// compact progress card would throw the transcript off screen to report a
    /// wait that isn't happening.
    private func beginPreparingPhase(
        startID: RecordingStartGate.StartID,
        descriptor: ModelDescriptor,
        isResume: Bool
    ) {
        armPreparingWatchdog(startID: startID)
        guard !isResume else { return }
        preparingProgressTask?.cancel()
        preparingProgressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.preparingRevealDelay)
            guard let self, !Task.isCancelled, self.isPreparing(startID) else { return }

            LiveHUDPanel.shared.showPreparing(modelName: descriptor.displayName) { [weak self] in
                self?.cancelPendingRecording()
            }
            self.installPreparingEscMonitor()
            AppLog.dictation.info("Preparing HUD shown for \(descriptor.id)")

            while !Task.isCancelled, self.isPreparing(startID) {
                if case .preparing(let fraction, let message) =
                    ModelRegistry.shared.readiness(for: descriptor.id) {
                    // The registry publishes 0.0 the moment preparation starts,
                    // and the phases that report nothing (the CoreML compile
                    // tail) never move it. A bar pinned at 0% is what a wedged
                    // download looks like, so "no progress yet" is passed as
                    // unknown and the card runs its indeterminate sweep instead.
                    LiveHUDPanel.shared.setPreparingProgress(
                        fraction: fraction > 0 ? fraction : nil,
                        message: message
                    )
                }
                try? await Task.sleep(for: Self.preparingProgressInterval)
            }
        }
    }

    /// True while this exact start is still the one being prepared. Both halves
    /// matter: the gate fences a superseded start, and the state check catches
    /// the window after preparation finished but before the task is cancelled.
    private func isPreparing(_ startID: RecordingStartGate.StartID) -> Bool {
        guard case .preparing = state else { return false }
        return recordingStartGate.accepts(startID)
    }

    /// Tears down everything `beginPreparingPhase` armed. Safe to call from any
    /// exit path, including one where the card was never revealed.
    private func endPreparingPhase() {
        stopPreparingWatchdog()
        preparingProgressTask?.cancel()
        preparingProgressTask = nil
        removePreparingEscMonitor()
    }

    /// Esc during preparing cancels the pending start — the same thing the
    /// card's Cancel button does, and what the hotkey policy already maps this
    /// state to. The panel isn't key here (the caret stays in the target app),
    /// so the global tap does the real work. Off with "Esc cancels dictation",
    /// like the transcribing card's.
    private func installPreparingEscMonitor() {
        removePreparingEscMonitor()
        guard HotkeyStore.shared.escapeCancelsDictation else { return }
        preparingEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let takes = MainActor.assumeIsolated {
                self?.hudTakesLocalEscape(event, escapeCancelsDictation: true) ?? false
            }
            guard takes else { return event }
            Task { @MainActor in self?.cancelPendingRecording() }
            return nil
        }
        installHUDEscapeEventTap(target: .preparing)
    }

    private func removePreparingEscMonitor() {
        if let preparingEscMonitor {
            NSEvent.removeMonitor(preparingEscMonitor)
            self.preparingEscMonitor = nil
        }
        removeHUDEscapeEventTap()
    }

    /// Fenced on the start ID rather than cancelled from every exit path: once
    /// the gate has finished or cancelled this start, the timer is a no-op
    /// wherever it fires from.
    private func armPreparingWatchdog(startID: RecordingStartGate.StartID) {
        preparingWatchdog?.cancel()
        preparingWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.preparingWatchdogTimeout)
            guard let self, !Task.isCancelled,
                  case .preparing = self.state,
                  self.recordingStartGate.accepts(startID) else { return }
            AppLog.dictation.error("Preparing watchdog fired; forcing recovery")
            self.recordingStartGate.cancelActiveStart()
            self.enterFailureHUD(
                message: "Could not start recording — the model or audio device didn't respond. Try again."
            )
        }
    }

    private func stopPreparingWatchdog() {
        preparingWatchdog?.cancel()
        preparingWatchdog = nil
    }

    /// Arms (or re-arms) the backstop for run `runID`. `timeout` is the
    /// ordinary transcription budget, except while the run waits on its
    /// model (`modelWaitWatchdogTimeout`).
    private func armTranscribingWatchdog(
        runID: UInt64,
        timeout: Duration = DictationController.transcribingWatchdogTimeout
    ) {
        transcribingWatchdog?.cancel()
        transcribingWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled,
                  self.state == .transcribing,
                  self.transcriptionRunID == runID else { return }
            AppLog.dictation.error("Transcription watchdog fired; forcing recovery")
            self.recoverFromStuckTranscribing()
        }
    }

    /// Forces the machine out of a wedged `.transcribing` so the hotkey works
    /// again. Fences the in-flight pipeline (bumping the run ID), tears down any
    /// streaming session, and surfaces a recoverable failure (which lands in
    /// `.error`/`.reviewing` — both re-arm the hotkey per the policy).
    private func recoverFromStuckTranscribing() {
        transcriptionRunID &+= 1
        cancelModelWait()
        stopTranscribingElapsedTicker()
        cancelStreamingSession()
        cancelFinishingStream()
        let message = "Transcription is taking too long. Try again."
        // The run's own exit is fenced off by the bump above, so its hold on
        // the take — the samples, the row — is released here instead.
        let samples = inFlightTranscriptionSamples
        let model = inFlightModel ?? ModelRegistry.shared.activeModel
        inFlightTranscriptionSamples = nil
        inFlightModel = nil
        releaseTakeInFlight()
        guard let samples else {
            enterFailureHUD(message: message)
            return
        }
        failTake(
            message: message,
            samples: samples,
            model: model,
            retrySkipsSpeechGate: inFlightSkipsSpeechGate
        )
    }

    private func startTranscribingElapsedTicker(from start: Date) {
        transcribingElapsedTask?.cancel()
        transcribingElapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .transcribing else { return }
                LiveHUDPanel.shared.setTranscribingElapsed(Date().timeIntervalSince(start))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopTranscribingElapsedTicker() {
        transcribingElapsedTask?.cancel()
        transcribingElapsedTask = nil
        transcribingWatchdog?.cancel()
        transcribingWatchdog = nil
    }

    // MARK: - Waiting on a model on this Mac

    /// Watches run `runID` wait for `model` to be prepared, on the card it is
    /// already on: the model a failure card's "Download & Transcribe" sent the
    /// take to is fetched here, with no state of its own — still
    /// `.transcribing`, Cancel and Esc still the way out.
    ///
    /// Polled at the preparing card's rate, as `beginPreparingPhase` polls,
    /// and only once a poll finds the registry preparing does the card switch
    /// to the wait: a warm model is ready before the first one, and a load
    /// over within it never flashes "Loading". From then the watchdog runs on
    /// the wait's budget rather than the transcription's. A cloud model has
    /// nothing to wait for.
    private func beginModelWait(for model: ModelDescriptor, runID: UInt64) {
        cancelModelWait()
        guard !model.isCloud else { return }
        let wasOnDisk = ModelRegistry.shared.readiness(for: model.id).isInstalled
        let poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.preparingProgressInterval)
                guard let self, !Task.isCancelled, self.showModelWait(runID: runID) else { return }
            }
        }
        modelWait = TakeModelWait(
            runID: runID,
            model: model,
            wasOnDisk: wasOnDisk,
            poll: poll,
            phase: wasOnDisk ? .loading : .downloading
        )
    }

    /// One sample of the wait onto the card. Returns whether to keep polling:
    /// not once the run has ended or a newer one owns the card.
    private func showModelWait(runID: UInt64) -> Bool {
        guard var wait = modelWait, wait.runID == runID,
              transcriptionRunID == runID, state == .transcribing else { return false }
        guard case .preparing(let fraction, let message) = ModelRegistry.shared.readiness(for: wait.model.id) else {
            return true
        }
        if !wait.isShown {
            wait.isShown = true
            armTranscribingWatchdog(runID: runID, timeout: Self.modelWaitWatchdogTimeout)
            AppLog.dictation.info("Transcription waiting on \(wait.model.id, privacy: .public) (on disk: \(wait.wasOnDisk))")
        }
        wait.phase = DictationRescue.modelWait(message: message, wasOnDisk: wait.wasOnDisk)
        modelWait = wait
        LiveHUDPanel.shared.setTranscribingWait(
            phase: FailureCardCopy.preparePhaseTitle(isLoading: wait.phase == .loading),
            modelName: wait.model.displayName,
            fraction: DictationRescue.shownFraction(fraction, during: wait.phase),
            message: message
        )
        return true
    }

    /// The run's model is prepared, or failed to be. Stops the poll, and if
    /// the card had switched to the wait, hands it back to "Transcribing" —
    /// on a fresh clock, so "Transcribing 1.2s" counts the transcription and
    /// not the download, and on the ordinary watchdog. A run that has been
    /// cancelled or superseded leaves the card to whoever owns it now.
    private func endModelWait(runID: UInt64) {
        guard let wait = modelWait, wait.runID == runID else { return }
        cancelModelWait()
        guard wait.isShown, transcriptionRunID == runID, state == .transcribing else { return }
        LiveHUDPanel.shared.setTranscribingWait(phase: nil)
        startTranscribingElapsedTicker(from: Date())
        armTranscribingWatchdog(runID: runID)
    }

    /// Stops watching. Never the preparation: that is the registry's, shared
    /// with the Models pane, and a download the user has waited this long for
    /// is worth finishing for next time.
    private func cancelModelWait() {
        modelWait?.poll.cancel()
        modelWait = nil
    }

    /// Whether run `runID` is waiting on its model's download right now —
    /// what a cancel's notice says carries on without it.
    private func isWaitingOnDownload(runID: UInt64) -> Bool {
        guard let wait = modelWait, wait.runID == runID, wait.phase == .downloading,
              case .preparing = ModelRegistry.shared.readiness(for: wait.model.id) else { return false }
        return true
    }

    /// The model the run waited on didn't come: a download that failed or
    /// stalled (`ModelRegistry` gives up after five minutes without
    /// download progress), in the registry's words when it has any. Retry — Return —
    /// runs the take on the same model again, which starts the download
    /// over; Choose Model is for a user who would rather pick another.
    private func failModelDownload(
        _ model: ModelDescriptor,
        samples: [Float],
        retrySkipsSpeechGate: Bool
    ) {
        var reason: String?
        if case .failed(let message) = ModelRegistry.shared.readiness(for: model.id) { reason = message }
        AppLog.dictation.error("Couldn't download \(model.id, privacy: .public) for the take: \(reason ?? "no reason given", privacy: .public)")
        let choose = DictationTakePolicy.CardAction.chooseModel
        failTake(
            message: FailureCardCopy.downloadFailed(modelName: model.displayName, reason: reason),
            samples: samples,
            model: model,
            retrySkipsSpeechGate: retrySkipsSpeechGate,
            action: cardAction(
                choose,
                labelled: .init(
                    title: FailureCardCopy.title(of: choose, provider: nil),
                    icon: FailureCardCopy.icon(of: choose),
                    hint: nil
                ),
                failedModel: model
            )
        )
    }

    /// A device change the recorder could not restart capture through. The
    /// benign ones — a Bluetooth mic switching into its voice profile, which is
    /// most of them — never reach here; the recorder re-wires and the take
    /// carries on. This is the genuinely fatal remainder, and it arrives
    /// carrying everything that was captured before the device went.
    private func handleAudioConfigurationChange(salvagedSamples samples: [Float]) async {
        let seconds = Double(samples.count) / AudioConfig.targetSampleRate
        AppLog.dictation.warning("Audio configuration change ended the take; salvaged \(samples.count) samples (\(seconds, format: .fixed(precision: 2))s)")
        guard state == .recording else {
            // A concurrent Stop reached the controller first. Only one of the
            // two drained the buffer, and if it was us we are holding the only
            // copy — returning here is how a long take became "Recording too
            // short" with nothing to retry.
            handOffLateSamples(samples, note: "Microphone disconnected — the recording stopped early.")
            return
        }
        // Cleared here and nowhere else on this path. `endRecordingPhase`
        // leaves the latch alone because on a *normal* stop the user's pending
        // key release is what ends the take — but this take is already over,
        // so the release has nothing left to stop and would instead replay as
        // a fresh press into whatever card the salvage puts up.
        standaloneModifierEventCoordinator.reset()
        endRecordingPhase()

        switch RecordingSalvage.outcome(
            sampleCount: samples.count,
            minTranscribeSamples: DictationConfig.minTranscribeSamples
        ) {
        case .transcribe:
            // Deliberately not `cancelStreamingSession()`: the pipeline's own
            // branch detaches the stream and calls `finishStream()`, which
            // returns the server's transcript of everything fed before the
            // change — strictly better than re-transcribing a buffer that
            // stops at the same moment.
            pendingReviewBanner = "Microphone disconnected — transcribed what was captured."
            await runTranscriptionPipeline(samples: samples)

        case .failWithSalvagedAudio:
            // No special case for a live partial transcript here. Routing one
            // into review would be the only path that reaches the editor
            // without `TranscriptPostProcessor` and without a History entry,
            // so Paste would commit nothing and hand over raw stream text —
            // and it needs under half a second of audio to have produced a
            // non-empty partial in the first place.
            cancelStreamingSession()
            enterFailureHUD(
                message: "Microphone disconnected after \(String(format: "%.1f", seconds))s — too short to transcribe.",
                samples: samples
            )

        case .failEmpty:
            cancelStreamingSession()
            enterFailureHUD(message: "Audio input device changed. Try again.")
        }
    }

    /// A take that survived a device change still lost the audio the hardware
    /// spent renegotiating, spliced silently out of the middle of the buffer.
    /// A truncated take at least reads as truncated; a hole in the middle is
    /// invisible, and the model bridges it into a sentence that is fluent and
    /// wrong.
    ///
    /// Only the normal stop path calls this. A take that ended *because* the
    /// device went already sets its own banner saying so, which subsumes this
    /// one — the interruption wins rather than stacking with it.
    private func noteInterruptionGapIfSignificant() {
        let gap = recorder.interruptionGapSeconds()
        guard gap >= Self.interruptionBannerThreshold, pendingReviewBanner == nil else { return }
        AppLog.dictation.warning("Take lost \(gap, format: .fixed(precision: 2))s to mid-recording restarts; flagging the review")
        pendingReviewBanner = "Microphone dropped out for \(String(format: "%.1f", gap))s mid-recording — some words may be missing."
    }

    /// Audio that arrived after its take had already moved on. Both stop
    /// paths can be in flight at once — a user Stop landing as the recorder
    /// gives up on a device change — and the buffer drains exactly once, so
    /// the loser of that race is the one holding the audio. Hand it to the
    /// card the winner already put up rather than dropping it. `take` is the
    /// recording the samples belong to, when the caller knows it: only that
    /// take's discarded recording may adopt them.
    private func handOffLateSamples(_ samples: [Float], note: String, take: UInt64? = nil) {
        guard !samples.isEmpty else { return }
        let retryable = samples.count >= DictationConfig.minTranscribeSamples
        switch state {
        case .error:
            AppLog.dictation.warning("Recovered \(samples.count) late samples onto the failure card")
            guard retryable else {
                enterFailureHUD(message: note, samples: samples)
                return
            }
            // Different audio from whatever the card already holds: a row of
            // its own, not an update to one, and none of the model that
            // take's buttons chose for it.
            takeHistoryRow = nil
            retryModelOverride = nil
            failTake(message: note, samples: samples, model: ModelRegistry.shared.activeModel)

        // A resumed take has no failure card: `enterFailureHUD` restores the
        // review it came from instead, so the loser of the race arrives to
        // find `.reviewing` and used to drop the only copy of the audio. The
        // banner's Retry is the same one a failed Resume offers, and it
        // rebuilds the splice from whatever the editor holds now — so it stays
        // correct even though this take's own text never existed.
        case .reviewing:
            guard retryable else {
                AppLog.dictation.warning("Dropped \(samples.count) late samples; too short to offer a retry")
                return
            }
            AppLog.dictation.warning("Recovered \(samples.count) late samples onto the resumed review")
            lastFailedSamples = samples
            retrySkipsSpeechGate = false
            retryModelOverride = nil
            takeHistoryRow = nil
            let saved = holdFailedTakeInHistory(
                samples: samples,
                model: ModelRegistry.shared.activeModel,
                status: .init(kind: .failed, message: note)
            )
            enterReview(
                text: LiveHUDPanel.shared.currentReviewText,
                cursorLocation: LiveHUDPanel.shared.currentCursorLocation,
                banner: Self.reviewFailureBanner(note, savedToHistory: saved),
                bannerRetry: { [weak self] in self?.retryFailedResumeTranscription() }
            )

        // A take cancelled into "Recording discarded · Undo" whose cancelled
        // stop lost the race: its hold would come back empty, and Undo would
        // say "Recording too short" about minutes of speech.
        case .idle:
            guard let held = discardedRecording, held.takeRunID == (take ?? takeRunID) else {
                AppLog.dictation.warning("Dropped \(samples.count) late samples; the take had already moved on")
                return
            }
            AppLog.dictation.warning("Recovered \(samples.count) late samples into the discarded recording's Undo")
            let earlier = held.samples
            discardedRecording?.samples = Task {
                DictationTakePolicy.heldRecordingSamples(held: await earlier.value, late: samples)
            }

        case .preparing, .recording, .transcribing, .delivering:
            AppLog.dictation.warning("Dropped \(samples.count) late samples; the take had already moved on")
        }
    }

    /// The teardown every exit from `.recording` shares.
    ///
    /// Deliberately without `standaloneModifierEventCoordinator.reset()`: in
    /// toggle mode with a standalone-modifier binding, the press that started
    /// the take set a latch and the matching release is what stops it, so
    /// clearing the latch mid-gesture swallows the user's stop. The normal stop
    /// path resets it at its own call site, where the gesture is already done.
    ///
    /// `removeEscMonitors` is false only for a cancel that came *from* Escape:
    /// the monitor that delivered the keystroke tears itself down, and pulling
    /// the session tap out from under an event it is still dispatching is what
    /// that path has always avoided.
    private func endRecordingPhase(removeEscMonitors: Bool = true) {
        recordingStartGate.reset()
        stopElapsedTicker()
        if removeEscMonitors { removeRecordingEscMonitors() }
    }

    private func preparationErrorMessage(for descriptor: ModelDescriptor) -> String {
        if case .failed(let reason) = ModelRegistry.shared.readiness(for: descriptor.id) {
            return "Failed to load \(descriptor.displayName): \(reason)"
        }
        return "Failed to load \(descriptor.displayName)."
    }

    // MARK: - Stop

    private func stopAndTranscribe() async {
        guard state == .recording else { return }
        let takeRunID = self.takeRunID
        standaloneModifierEventCoordinator.reset()
        endRecordingPhase()
        let samples = await recorder.flushAndStop()
        AppLog.dictation.notice("Captured \(samples.count) samples (\(Double(samples.count) / AudioConfig.targetSampleRate, format: .fixed(precision: 2))s)")
        // `state` is still `.recording` across the await above, so the salvage
        // path can have taken this take while we were draining. It owns the
        // outcome from here — running our own pipeline would clobber its state
        // and clear the interruption banner it set.
        // Noted before the guard, not after: this take lost the audio either
        // way, and the path below hands its samples to a card that can still
        // paste them. Skipped silently if the salvage already set its own.
        noteInterruptionGapIfSignificant()
        guard state == .recording, self.takeRunID == takeRunID else {
            handOffLateSamples(samples, note: "Microphone disconnected — the recording stopped early.", take: takeRunID)
            return
        }

        switch RecordingSalvage.outcome(
            sampleCount: samples.count,
            minTranscribeSamples: DictationConfig.minTranscribeSamples
        ) {
        case .transcribe:
            await runTranscriptionPipeline(samples: samples)
        case .failWithSalvagedAudio:
            // Handed over even though Retry is withheld, purely so the card
            // can report how much was captured: telling a user who just spoke
            // that there is "nothing to review" is a lie.
            enterFailureHUD(message: "Recording too short — try again.", samples: samples)
        case .failEmpty:
            enterFailureHUD(message: "Recording too short — try again.")
        }
    }

    /// `model` is the one a failure card's button chose — "Transcribe on
    /// Mac", "Retry OpenAI": this take's retries run on it from now on
    /// (`retryModelOverride`), and the dictation model stays whatever the
    /// user chose.
    private func retryTranscription(using model: ModelDescriptor? = nil) {
        guard case .error = state, let samples = lastFailedSamples,
              !heldTakeIsRegenerating() else { return }
        let model = retryModel(choosing: model)
        let skipSpeechGate = retrySkipsSpeechGate
        AppLog.dictation.info("Retrying transcription on \(samples.count) cached samples (speech gate \(skipSpeechGate ? "skipped" : "on"), model \(model?.id ?? "active", privacy: .public))")
        removeFailureEscMonitor()
        lastFailedSamples = nil
        // Synchronously transition to .transcribing so a hotkey press queued
        // between this click and the Task firing maps to .none (per policy)
        // instead of starting a competing recording that would race with the
        // pipeline's own enterTranscribing call below.
        enterTranscribing()
        Task { await runTranscriptionPipeline(samples: samples, skipSpeechGate: skipSpeechGate, model: model) }
    }

    /// Retry for a failed Resume take: the review HUD is back up showing the
    /// prior text with a failure banner, and the failed take's audio sits in
    /// `lastFailedSamples`. Rebuilds the splice context from the *current*
    /// text and caret — the user may have edited while the banner was showing
    /// — then re-runs the pipeline on the stashed samples, so on success the
    /// take lands at the caret exactly like a successful Resume would have.
    /// `model` is the one the banner's button chose, as for
    /// `retryTranscription`.
    private func retryFailedResumeTranscription(using model: ModelDescriptor? = nil) {
        guard case .reviewing = state, let samples = lastFailedSamples,
              !heldTakeIsRegenerating() else { return }
        let model = retryModel(choosing: model)
        let skipSpeechGate = retrySkipsSpeechGate
        AppLog.dictation.info("Retrying failed resume transcription on \(samples.count) cached samples (speech gate \(skipSpeechGate ? "skipped" : "on"), model \(model?.id ?? "active", privacy: .public))")
        cancelReviewAction()
        lastFailedSamples = nil
        resumeContext = ResumeContext(
            fullText: LiveHUDPanel.shared.currentReviewText,
            cursorLocation: LiveHUDPanel.shared.currentCursorLocation
        )
        removeReviewEscMonitor()
        enterTranscribing()
        Task { await runTranscriptionPipeline(samples: samples, skipSpeechGate: skipSpeechGate, model: model) }
    }

    /// Whether History's "Transcribe with…" is already running on the row
    /// this take's Retry would fill. It refuses a row a card holds, but one
    /// it started on first — before a discarded review's Undo put the card
    /// back — is still running: a second request would bill twice, and if
    /// it failed after the regeneration landed, the card would report a
    /// failure about a row that is transcribed. The regeneration's own
    /// result is the retry.
    ///
    /// Said on the card or banner whose button was pressed, since Retry,
    /// Return and "Transcribe on Mac" otherwise just do nothing for as long
    /// as the regeneration — perhaps a model download — runs.
    private func heldTakeIsRegenerating() -> Bool {
        guard let id = takeHistoryRow?.id, TranscriptRegenerator.shared.activeID == id else { return false }
        AppLog.dictation.notice("Retry skipped; History is already transcribing this take's row")
        let notice = "History is already transcribing this recording."
        let hud = LiveHUDState.shared
        // Said for a moment, then the card's own line comes back: nothing
        // here watches the regeneration, so a notice left standing would
        // outlive it and hide the failure the card is still about.
        switch state {
        case .error:
            let previous = hud.failureDetail
            hud.failureDetail = notice
            Task { @MainActor in
                try? await Task.sleep(for: Self.cancelNoticeDuration)
                if hud.failureDetail == notice { hud.failureDetail = previous }
            }
        case .reviewing:
            let previous = hud.reviewBanner
            hud.reviewBanner = notice
            Task { @MainActor in
                try? await Task.sleep(for: Self.cancelNoticeDuration)
                if hud.reviewBanner == notice { hud.reviewBanner = previous }
            }
        default:
            break
        }
        return true
    }

    /// The model this take's retry runs on: `chosen`, a card button's model,
    /// from now on; otherwise the one chosen before, while the dictation
    /// model is still the one it was chosen over; otherwise nil, the
    /// dictation model. A Retry after the user picked another model in
    /// Settings runs that model, not the override — which may be the very
    /// model whose own run just failed.
    private func retryModel(choosing chosen: ModelDescriptor?) -> ModelDescriptor? {
        let activeModelID = ModelRegistry.shared.activeModel?.id
        if let chosen {
            retryModelOverride = RetryModelOverride(model: chosen, chosenOverModelID: activeModelID)
        } else if let override = retryModelOverride,
                  !DictationTakePolicy.keepsRetryModelOverride(
                      chosenOverModelID: override.chosenOverModelID,
                      activeModelID: activeModelID
                  ) {
            AppLog.dictation.info("Retry follows the dictation model the user picked since choosing \(override.model.id, privacy: .public) for the take")
            retryModelOverride = nil
        }
        return retryModelOverride?.model
    }

    /// Runs the failed take again from whichever surface offered it: the
    /// failure card, or the banner of a failed Resume take. `model` as for
    /// `retryTranscription`; nil runs it as the last attempt did.
    private func retryFailedTake(using model: ModelDescriptor? = nil) {
        switch state {
        case .error:
            retryTranscription(using: model)
        case .reviewing:
            retryFailedResumeTranscription(using: model)
        case .idle, .preparing, .recording, .transcribing, .delivering:
            break
        }
    }

    /// Runs VAD + transcription + post-processing on the given audio.
    /// On any recoverable failure, surfaces the error through the failure
    /// HUD with Retry; on success, hands off to the review/deliver flow.
    /// Reusable across first-pass and retry so they share one code path.
    ///
    /// `skipSpeechGate` is the "Transcribe Anyway" retry of a take the gate
    /// rejected — the user has overruled it. `model` overrides the active
    /// model for this run only (a failure card's "Transcribe on Mac", "Retry
    /// OpenAI"). A model on this Mac that isn't ready is downloaded or loaded
    /// on the transcribing card first (`beginModelWait`).
    ///
    /// Before the gate or any engine runs, the take is saved to History and
    /// marked as transcribing there (`holdTakeWhileTranscribing`); every way
    /// out of the run decides what that row becomes (`DictationTakePolicy`).
    private func runTranscriptionPipeline(
        samples: [Float],
        skipSpeechGate: Bool = false,
        model override: ModelDescriptor? = nil
    ) async {
        guard let descriptor = override ?? ModelRegistry.shared.activeModel else {
            // Still words the user spoke: kept like any failed take, with
            // Retry for once a model is chosen.
            failTake(
                message: "No active model selected.",
                samples: samples,
                model: nil,
                retrySkipsSpeechGate: skipSpeechGate
            )
            return
        }

        enterTranscribing()
        let pipelineStart = Date()
        let runID = transcriptionRunID
        // The model that actually produces this transcript — for History
        // attribution. A streaming transcript comes from the session opened at
        // recording start (its model captured then), not whatever is active now.
        let recordedModel = streamingEngine != nil ? (streamingModel ?? descriptor) : descriptor
        inFlightTranscriptionSamples = samples
        inFlightSkipsSpeechGate = skipSpeechGate
        inFlightModel = recordedModel
        defer {
            // Fenced as a whole: a run the user cancelled (or the watchdog gave
            // up on) can outlive its own HUD, and by the time it unwinds the
            // ticker, the watchdog and the samples may already belong to a newer
            // run — stopping that run's clock from here would leave it with no
            // watchdog at all. Holding the samples any longer than the run that
            // owns them would keep the last dictation's raw audio (megabytes per
            // minute) alive for the rest of the session. The canceller and the
            // watchdog release the History row themselves.
            if runID == transcriptionRunID {
                stopTranscribingElapsedTicker()
                inFlightTranscriptionSamples = nil
                inFlightModel = nil
                finishingStream = nil
                releaseTakeInFlight()
            }
        }
        holdTakeWhileTranscribing(samples: samples, model: recordedModel)

        // A live stream that has already shown words has heard speech, and
        // all the gate could do to its take is throw those words away.
        let streamHeardSpeech = streamingEngine != nil && streamingShowedText
        if !skipSpeechGate, !streamHeardSpeech {
            let voiced = await VoiceActivityGate.shared.isVoiced(samples)
            guard runID == transcriptionRunID else { return }
            guard voiced else {
                AppLog.dictation.notice("Speech gate found no speech in \(samples.count) samples; offering Transcribe Anyway")
                cancelStreamingSession()
                // The gate can be wrong — soft speech, a mic turned down — so
                // the card keeps the audio and offers to transcribe it anyway
                // rather than dropping what may be the user's words. Its row
                // is taken back: past this gate a rejection is almost always
                // real silence, and silent rows would push real dictations out
                // of the cap. A "Transcribe Anyway" that then fails is saved
                // like any failed take.
                settleUnusableTake(
                    message: "No speech detected.",
                    samples: samples,
                    model: recordedModel,
                    retrySkipsSpeechGate: skipSpeechGate,
                    speechGateRejected: true
                )
                return
            }
        }

        // Pick how the final transcript is produced: flush the live stream if
        // one is active, otherwise transcribe the buffered samples (local
        // engines, or a retry of a failed stream). Both share one error path.
        let produce: () async throws -> String
        if let streaming = streamingEngine {
            // The audio source is done, so stop feeding it. finishStream tears
            // the socket down itself — this isn't a cancelStreamingSession case.
            streamingEngine = nil
            finishingStream = streaming
            streamingModel = nil
            recorder.onAudioChunk = nil
            AppLog.dictation.info("Finishing live stream transcription")
            produce = { try await streaming.finishStream() }
        } else {
            beginModelWait(for: descriptor, runID: runID)
            let wasOnDisk = modelWait?.wasOnDisk ?? true
            let prepared = await ModelRegistry.shared.prepareModel(id: descriptor.id)
            endModelWait(runID: runID)
            // Logged before the run fence on purpose: a user who gives up on a
            // long "Transcribing" and cancels is exactly the case to diagnose.
            if prepared != nil {
                AppLog.dictation.notice("Engine acquired after \(Date().timeIntervalSince(pipelineStart), format: .fixed(precision: 2))s")
            }
            guard runID == transcriptionRunID else { return }
            guard let engine = prepared else {
                // A model this run had to fetch, and still doesn't have on
                // disk, failed as a download and says so. One whose files did
                // land but wouldn't load is a load failure: blaming the
                // connection would send the user to retry a download that
                // already worked.
                let readiness = ModelRegistry.shared.readiness(for: descriptor.id)
                guard wasOnDisk || ModelStorage.isDownloaded(descriptor, readiness: readiness) else {
                    failModelDownload(descriptor, samples: samples, retrySkipsSpeechGate: skipSpeechGate)
                    return
                }
                if !wasOnDisk {
                    var reason: String?
                    if case .failed(let message) = readiness { reason = message }
                    failTake(
                        message: FailureCardCopy.loadFailed(modelName: descriptor.displayName, reason: reason),
                        samples: samples,
                        model: descriptor,
                        retrySkipsSpeechGate: skipSpeechGate
                    )
                    return
                }
                failTake(
                    message: "Failed to prepare model for transcription.",
                    samples: samples,
                    model: descriptor,
                    retrySkipsSpeechGate: skipSpeechGate
                )
                return
            }
            AppLog.dictation.info("Transcribing full buffer: \(samples.count) samples")
            produce = {
                try await engine.transcribe(
                    samples: samples,
                    contextPrompt: nil,
                    progress: { current, total in
                        Task { @MainActor in
                            LiveHUDPanel.shared.setTranscribingProgress(current: current, total: total)
                        }
                    }
                )
            }
        }

        let rawText: String
        let produceStart = Date()
        do {
            rawText = try await produce()
            AppLog.dictation.notice("Transcription produced after \(Date().timeIntervalSince(pipelineStart), format: .fixed(precision: 2))s (inference: \(Date().timeIntervalSince(produceStart), format: .fixed(precision: 2))s)")
            // Before the run fence: a request that worked says the balance
            // isn't empty whether or not anyone is still waiting for its text.
            CloudCreditStatus.shared.noteSuccess(provider: recordedModel.backend.cloudProvider)
        } catch {
            guard runID == transcriptionRunID else { return }
            // Classified so the card can say what would actually help: a
            // refused key needs Settings — beside Retry, which is what works
            // once it's fixed; a rate limit needs a wait; an empty balance or
            // no network needs a model on this Mac.
            let failure = TranscriptionFailure.classify(error)
            AppLog.dictation.error("Transcription failed (\(String(describing: failure), privacy: .public)): \(error.localizedDescription)")
            // After the run fence: only a refusal the card below is about to
            // show flags the provider, so a later card's "still out of
            // credit" is never the first the user hears of it. Read and
            // marked in one step: whether it was flagged before this one.
            let isRepeatRefusal = CloudCreditStatus.shared.noteFailure(
                failure,
                provider: recordedModel.backend.cloudProvider
            )
            failTranscription(
                failure,
                isRepeatRefusal: isRepeatRefusal,
                engineMessage: Self.transcriptionFailureMessage(for: error),
                samples: samples,
                model: recordedModel,
                retrySkipsSpeechGate: skipSpeechGate
            )
            return
        }
        guard runID == transcriptionRunID else { return }

        let processed = TranscriptPostProcessor.process(rawText)
        if processed.isEmpty {
            // An engine that ran fine and wrote nothing heard nothing worth
            // keeping — room noise the gate let through, a stray press. Like a
            // gate rejection it isn't kept in History (silent rows would push
            // real dictations out of the cap); the card still keeps the audio
            // for Retry. A take that already has a row from an earlier failure
            // keeps it, with this as its latest reason.
            settleUnusableTake(
                message: "Transcription returned empty text. Try speaking closer to the mic.",
                samples: samples,
                model: recordedModel,
                retrySkipsSpeechGate: skipSpeechGate,
                speechGateRejected: false
            )
            return
        }

        lastFailedSamples = nil
        retryModelOverride = nil
        fileTranscript(processed, samples: samples, model: recordedModel)
        releaseTakeInFlight()

        // Resume always returns to review with the new transcript spliced at
        // the original caret; otherwise honor the user's review preference —
        // unless this take carries a notice the user has to see. A take cut
        // short by a device change produces a perfectly normal-looking
        // transcript, and pasting it straight into their document gives them
        // no moment at which they could notice it stops mid-sentence. The
        // setting means "don't slow me down", and it is answering the normal
        // case; this one is already abnormal.
        if let resume = resumeContext {
            resumeContext = nil
            let spliced = resume.splicing(processed)
            enterReview(text: spliced.text, cursorLocation: spliced.caret, banner: takeReviewBanner())
        } else if reviewBeforePaste || pendingReviewBanner != nil {
            enterReview(text: processed, banner: takeReviewBanner())
        } else {
            // No review step: the text is delivered and kept right away.
            commitPendingHistory()
            removeTranscribingEscMonitor()
            state = .delivering
            LiveHUDPanel.shared.hide()
            await deliver(text: processed, path: .direct, modifierWait: nil)
        }
    }

    /// Saves the take before anything can fail it — unless it has a row
    /// already (a retry of one saved on failure) or History is off — and
    /// marks its row as being transcribed.
    private func holdTakeWhileTranscribing(samples: [Float], model: ModelDescriptor) {
        let store = RecordingHistoryStore.shared
        reclaimTakeRow()
        if DictationTakePolicy.writesAhead(historyEnabled: store.isEnabled, row: takeRowStage),
           let id = store.recordPending(samples: samples, model: model) {
            takeHistoryRow = TakeHistoryRow(id: id, isSurfaced: false)
        }
        if let id = takeHistoryRow?.id { markTakeInFlight(id) }
    }

    private func markTakeInFlight(_ id: UUID) {
        // A row still marked belongs to a run this one superseded.
        releaseTakeInFlight()
        inFlightHistoryID = id
        RecordingHistoryStore.shared.markInFlight(id)
    }

    /// Idempotent, so every exit can call it without knowing whether another
    /// already has. A leaked mark would leave its row reading "Transcribing…"
    /// for the rest of the session.
    private func releaseTakeInFlight() {
        guard let id = inFlightHistoryID else { return }
        inFlightHistoryID = nil
        RecordingHistoryStore.shared.endInFlight(id)
    }

    /// Deletes the take's write-ahead row.
    private func retractTakeRow() {
        guard let row = takeHistoryRow else { return }
        takeHistoryRow = nil
        releaseTakeInFlight()
        RecordingHistoryStore.shared.retract(id: row.id)
    }

    /// Puts the finished transcript in History. Each take is its own entry,
    /// so its audio matches its transcript exactly (Resume splices text in the
    /// review buffer, but the saved audio is only this take).
    ///
    /// The take's row is normally already there, written ahead when it
    /// stopped, and the text fills it in. A row the user never heard about is
    /// an ordinary dictation's, held as "pending" until the user keeps it
    /// (paste/deliver) so a review Cancel can retract it — discarded dictation
    /// must not stay on disk. A row a failure card already said was saved
    /// stays out of the pending list, so cancelling this review can't take
    /// back what the card promised. If History's "Transcribe Again" filled it
    /// in meanwhile, this text joins it as another version, not a second row.
    private func fileTranscript(_ text: String, samples: [Float], model: ModelDescriptor) {
        reclaimTakeRow()
        let disposition = DictationTakePolicy.disposition(for: .transcribed, row: takeRowStage)
        let row = takeHistoryRow
        takeHistoryRow = nil
        guard case .keepTranscript(let pending) = disposition else { return }
        let store = RecordingHistoryStore.shared
        // No row — History was off when the take stopped — or the user
        // deleted it and the deletion has committed: saved like any
        // finished dictation, if History is on.
        guard let row, let entry = store.entries.first(where: { $0.id == row.id }) else {
            if let id = store.record(samples: samples, transcript: text, model: model) {
                pendingHistoryIDs.append(id)
            }
            return
        }
        if entry.needsTranscript {
            store.resolveFailedTranscript(id: row.id, transcript: text, model: model)
        } else if entry.transcript != text.trimmingCharacters(in: .whitespacesAndNewlines) {
            store.addRegeneratedTranscript(id: row.id, transcript: text, model: model)
        }
        if pending { pendingHistoryIDs.append(row.id) }
    }

    /// A take that produced nothing worth keeping: the speech gate heard no
    /// speech, or the engine ran and wrote nothing. Its write-ahead row is
    /// taken back and the card says the audio isn't saved, while still
    /// holding it for Retry or Transcribe Anyway. A take the user was already
    /// told is in History keeps its row, with this as its latest reason.
    private func settleUnusableTake(
        message: String,
        samples: [Float],
        model: ModelDescriptor,
        retrySkipsSpeechGate: Bool,
        speechGateRejected: Bool
    ) {
        reclaimTakeRow()
        switch DictationTakePolicy.disposition(for: .unusable, row: takeRowStage) {
        case .keepFailed:
            failTake(
                message: message,
                samples: samples,
                model: model,
                retrySkipsSpeechGate: retrySkipsSpeechGate,
                speechGateRejected: speechGateRejected
            )
            return
        case .retract:
            retractTakeRow()
        case .leave, .keepTranscript:
            // No row in History: none was written, or the user deleted it
            // and the deletion has committed.
            takeHistoryRow = nil
            releaseTakeInFlight()
        }
        enterFailureHUD(
            message: message,
            samples: samples,
            canRetry: true,
            retrySkipsSpeechGate: retrySkipsSpeechGate,
            speechGateRejected: speechGateRejected
        )
    }

    /// A take an engine failed. Kept in History like any failed take, behind
    /// a card whose buttons fit what went wrong (`DictationTakePolicy
    /// .failureCard`) and whose words say why (`FailureCardCopy`).
    ///
    /// Out of credit or offline, a model on this Mac leads and Return runs it
    /// — downloading it on the card first, if it isn't here yet — with Retry
    /// beside it named for the provider it goes back to; refused again, the
    /// switch to it for dictation takes Retry's place. A refused key gets
    /// Check API Key beside Retry; anything else, Retry alone. A failed
    /// Resume take gets the same choice on its review banner, as far as the
    /// banner has room for it (`DictationRescue.resumeBanner`).
    private func failTranscription(
        _ failure: TranscriptionFailure,
        isRepeatRefusal: Bool,
        engineMessage: String,
        samples: [Float],
        model: ModelDescriptor,
        retrySkipsSpeechGate: Bool
    ) {
        // Weighed only for the two failures a model on this Mac answers: it
        // walks the model folders and the input sources. Offline, only a
        // model already here can help.
        var fallback: DictationTakePolicy.LocalFallback?
        let actions = DictationTakePolicy.failureCard(
            failure: failure,
            local: {
                fallback = ModelRegistry.shared.localFallback(
                    replacing: model.id,
                    canDownload: failure != .offline
                )
                return fallback
            },
            isRepeatRefusal: isRepeatRefusal
        )
        let provider = model.backend.cloudProvider?.displayName

        // History keeps the failure's own sentence: the card's banner talks
        // about the buttons under it, which a History row doesn't have.
        releaseTakeInFlight()
        let saved = holdFailedTakeInHistory(
            samples: samples,
            model: model,
            status: .init(kind: .failed, message: failure.message(provider: provider, fallback: engineMessage))
        )

        let localModel = fallback.flatMap { ModelCatalog.model(for: $0.modelID) }
        let copy = FailureCardCopy.card(
            failure: failure,
            actions: actions,
            provider: provider,
            local: fallback,
            localName: localModel?.displayName,
            localLanguages: localModel?.languages,
            capturedSeconds: Double(samples.count) / AudioConfig.targetSampleRate,
            savedToHistory: saved,
            isRepeatRefusal: isRepeatRefusal,
            engineMessage: engineMessage
        )
        let primary = cardAction(actions.primary, labelled: copy.primary, failedModel: model)
        var secondary: FailureAction?
        if let action = actions.secondary, let button = copy.secondary {
            secondary = cardAction(action, labelled: button, failedModel: model)
        }

        let banner = DictationRescue.resumeBanner(failure: failure, actions: actions)
        var bannerRetry: (@MainActor () -> Void)?
        if let action = banner.retry {
            bannerRetry = { [weak self] in self?.runCardAction(action, failedModel: model) }
        }
        let resumeBanner = ResumeFailureBanner(
            message: FailureCardCopy.reviewBanner(
                failure: failure,
                primary: actions.primary,
                provider: provider,
                engineMessage: engineMessage
            ),
            retry: bannerRetry,
            action: banner.action.map { action in
                cardAction(
                    action,
                    labelled: .init(
                        title: FailureCardCopy.title(of: action, provider: provider),
                        icon: FailureCardCopy.icon(of: action),
                        hint: nil
                    ),
                    failedModel: model
                )
            }
        )

        enterFailureHUD(
            message: copy.banner,
            samples: samples,
            canRetry: true,
            retrySkipsSpeechGate: retrySkipsSpeechGate,
            primary: primary,
            action: secondary,
            detail: copy.detail,
            savedToHistory: saved,
            resumeBanner: resumeBanner
        )
    }

    /// A card or banner button that runs `action` for a take `failedModel`
    /// failed, worded as `FailureCardCopy` words it.
    private func cardAction(
        _ action: DictationTakePolicy.CardAction,
        labelled button: FailureCardCopy.Button,
        failedModel: ModelDescriptor
    ) -> FailureAction {
        FailureAction(title: button.title, icon: button.icon, hint: button.hint) { [weak self] in
            self?.runCardAction(action, failedModel: failedModel)
        }
    }

    /// What a failure card's or a Resume banner's button does.
    ///
    /// "Retry <provider>" passes the cloud model that failed explicitly: a
    /// plain retry keeps whatever model an earlier button chose for the take
    /// (`retryModel(choosing:)`), and after "Transcribe on Mac" that is the
    /// model on this Mac — which is not what a button named for the provider
    /// promises. The models on this Mac run the take once, as its override;
    /// the dictation model doesn't change. "Use for Dictation" is the one
    /// button that does change it, remembering the cloud model so the Models
    /// pane can switch back, and then runs the take on it too.
    private func runCardAction(_ action: DictationTakePolicy.CardAction, failedModel: ModelDescriptor) {
        switch action {
        case .retry:
            retryFailedTake()
        case .retryCloud:
            retryFailedTake(using: failedModel)
        case .transcribeOnMac(let id), .downloadAndTranscribe(let id, _):
            guard let local = ModelCatalog.model(for: id) else { return }
            retryFailedTake(using: local)
        case .useForDictation(let id):
            guard let local = ModelCatalog.model(for: id) else { return }
            AppLog.dictation.notice("Dictation model switched to \(id, privacy: .public) from \(failedModel.id, privacy: .public), out of credit")
            ModelRegistry.shared.useForDictation(id, switchingFrom: failedModel.id)
            retryFailedTake(using: local)
        case .chooseModel:
            WindowOpener.shared.showMain(section: .models)
        case .checkAPIKey:
            WindowOpener.shared.showMain(section: .cloud)
        }
    }

    /// Engine errors already read as complete sentences ("Transcription
    /// failed: …", "Model load failed: …"); only foreign errors need the
    /// prefix added for context.
    private static func transcriptionFailureMessage(for error: Error) -> String {
        if error is TranscriptionEngineError || error is CloudTranscriptionError {
            return error.localizedDescription
        }
        return "Transcription failed: \(error.localizedDescription)"
    }

    /// A failed Resume take's banner. The failure card has its own line for
    /// whether the take is in History; the banner only has its one message,
    /// so it says so up front — at the end it would be the first thing a long
    /// message's truncation cut.
    private static func reviewFailureBanner(_ message: String, savedToHistory: Bool) -> String {
        savedToHistory ? "Recording saved to History. \(message)" : message
    }

    /// Single entry point for transcription failures. Surfaces the error
    /// visually instead of silently hiding the HUD. When a Resume was in
    /// flight, restores the prior review text with the message as a banner —
    /// keeping the failed take's audio so the banner can offer Retry;
    /// otherwise shows the failure HUD with optional Retry. Retry is offered
    /// only when re-running the same audio could plausibly succeed.
    /// `retrySkipsSpeechGate` makes that retry skip the speech gate, for audio
    /// the user already told to be transcribed anyway; `speechGateRejected`
    /// is the gate's own rejection, whose retry is "Transcribe Anyway".
    /// `primary` takes Retry's place when the card leads with something else
    /// ("Transcribe on Mac"). `action` sits beside it when there is one, and
    /// replaces it when not. `resumeBanner` is what a failed Resume take's
    /// review banner says and offers instead, when that differs from the card.
    private func enterFailureHUD(
        message: String,
        samples: [Float]? = nil,
        canRetry: Bool = false,
        retrySkipsSpeechGate: Bool = false,
        speechGateRejected: Bool = false,
        primary: FailureAction? = nil,
        action: FailureAction? = nil,
        detail: String? = nil,
        savedToHistory: Bool = false,
        resumeBanner: ResumeFailureBanner? = nil
    ) {
        // A start that failed before recording began still has its preparing
        // card up (and its Esc route armed); this hands both over.
        endPreparingPhase()
        // This card replaces the discard notice, if one is up, and its Undo.
        retireNotices()
        // Leaving `.transcribing` (or never having reached it): its Esc route
        // hands over to the review banner's or the failure HUD's, installed
        // below. A no-op on the paths that never armed it.
        removeTranscribingEscMonitor()
        let retryAvailable = canRetry && samples != nil
        self.retrySkipsSpeechGate = retrySkipsSpeechGate || speechGateRejected

        if let resume = resumeContext {
            resumeContext = nil
            lastFailedSamples = retryAvailable ? samples : nil
            if !retryAvailable { retryModelOverride = nil }
            let banner = resumeBanner ?? ResumeFailureBanner(
                message: message,
                retry: { [weak self] in self?.retryFailedResumeTranscription() },
                action: action
            )
            enterReview(
                text: resume.fullText,
                cursorLocation: resume.cursorLocation,
                banner: Self.reviewFailureBanner(banner.message, savedToHistory: savedToHistory),
                bannerRetry: retryAvailable ? banner.retry : nil,
                bannerAction: banner.action
            )
            return
        }

        lastFailedSamples = retryAvailable ? samples : nil
        if !retryAvailable { retryModelOverride = nil }
        state = .error(message)

        // Retry leads whenever the same audio could plausibly succeed on a
        // second pass — or what the caller leads with in its place — with
        // the caller's action beside it (Check API Key, Retry OpenAI);
        // otherwise the caller's action leads (Open Settings for a
        // permission failure, where pressing the hotkey again can never
        // help); otherwise Close alone.
        let resolvedAction: FailureAction?
        let secondaryAction: FailureAction?
        if retryAvailable {
            let retry: @MainActor () -> Void = { [weak self] in self?.retryTranscription() }
            resolvedAction = primary ?? (speechGateRejected ? .transcribeAnyway(retry) : .retry(retry))
            secondaryAction = action
        } else {
            resolvedAction = action
            secondaryAction = nil
        }

        LiveHUDPanel.shared.showFailure(
            message: message,
            actionTitle: resolvedAction?.title,
            actionIcon: resolvedAction?.icon ?? "arrow.clockwise",
            actionHint: resolvedAction?.hint,
            // Independent of `retryAvailable`, and only ever a count: the
            // card states how much was captured, which stays true whether
            // those samples were retained for Retry or dropped just above.
            salvagedSampleCount: samples?.count ?? 0,
            savedToHistory: savedToHistory,
            detail: detail,
            secondaryActionTitle: secondaryAction?.title,
            secondaryActionIcon: secondaryAction?.icon,
            onRetry: { resolvedAction?.run() },
            onSecondaryAction: secondaryAction?.run,
            onCancel: { [weak self] in self?.dismissFailure() }
        )
        installFailureEscMonitor()
        // Return is bound where the card says it is — the ↩ on its primary.
        failureReturnAction = resolvedAction?.hint != nil ? resolvedAction?.run : nil
    }

    /// What a failed Resume take's review banner says and offers, where that
    /// differs from the failure card a first-pass take would get. The banner
    /// has one Retry, one action beside it and no Return of its own (Return
    /// pastes the review), so the card's buttons are fitted to it
    /// (`DictationRescue.resumeBanner`).
    private struct ResumeFailureBanner {
        /// Prefixed with "Recording saved to History." when it is.
        let message: String
        /// The banner's Retry, or nil to offer none.
        let retry: (@MainActor () -> Void)?
        let action: FailureAction?
    }

    /// A take whose transcription failed. The audio goes to History before
    /// the card goes up — whether or not History is on, since it can't be
    /// recorded again — so closing the card, starting another dictation,
    /// quitting or a crash can't lose it; the row then offers "Transcribe
    /// Again". A take already saved ahead keeps that row, now saying what
    /// went wrong. A failed Resume take is kept the same way, behind the
    /// review banner's Retry. Retry is always offered: even a refused key is
    /// one fix away from the same audio working.
    private func failTake(
        message: String,
        samples: [Float],
        model: ModelDescriptor?,
        retrySkipsSpeechGate: Bool = false,
        speechGateRejected: Bool = false,
        action: FailureAction? = nil
    ) {
        releaseTakeInFlight()
        let saved = holdFailedTakeInHistory(
            samples: samples,
            model: model,
            status: .init(kind: .failed, message: message)
        )
        enterFailureHUD(
            message: message,
            samples: samples,
            canRetry: true,
            retrySkipsSpeechGate: retrySkipsSpeechGate,
            speechGateRejected: speechGateRejected,
            action: action,
            savedToHistory: saved
        )
    }

    /// Saves the take's audio once: a take saved ahead of transcription, or a
    /// retry of one that failed before, only updates what its row says went
    /// wrong. Returns whether the take is in History now — and if it is, the
    /// caller is about to say so, so the row counts as surfaced.
    ///
    /// "In History" is the row being in the visible list, whatever the update
    /// changed: a row "Transcribe with…" filled in meanwhile has no failure
    /// left to replace, and is saved all the same. A row the user deleted
    /// while the card held it is taken back first if its deletion is still
    /// in History's undo window (`reclaimTakeRow`); one whose deletion has
    /// committed no longer holds the take, so the audio is saved as a row
    /// of its own: the card is the only other copy, and a failed take is
    /// kept whatever happened to its first row.
    @discardableResult
    private func holdFailedTakeInHistory(
        samples: [Float],
        model: ModelDescriptor?,
        status: RecordingHistoryEntry.Status
    ) -> Bool {
        let store = RecordingHistoryStore.shared
        reclaimTakeRow()
        if let id = takeHistoryRow?.id, takeRowIsInHistory {
            store.updateFailedStatus(id: id, status: status)
            takeHistoryRow?.isSurfaced = true
            return true
        }
        takeHistoryRow = nil
        guard let id = store.recordFailed(samples: samples, model: model, status: status) else {
            return false
        }
        takeHistoryRow = TakeHistoryRow(id: id, isSurfaced: true)
        return true
    }

    /// The failure card's optional action button. The out-of-credit and
    /// offline rescue's buttons are worded by `FailureCardCopy` and built by
    /// `cardAction(_:labelled:failedModel:)`.
    struct FailureAction {
        let title: String
        let icon: String
        /// Only set where the key is really bound — on the card's primary,
        /// Return runs it (`failureReturnAction`); nothing is bound to Open
        /// Settings.
        let hint: String?
        let run: @MainActor () -> Void

        static func retry(_ run: @escaping @MainActor () -> Void) -> FailureAction {
            FailureAction(title: "Retry", icon: "arrow.clockwise", hint: "↩", run: run)
        }

        /// The retry for audio the speech gate rejected: the same re-run, with
        /// the gate overruled.
        static func transcribeAnyway(_ run: @escaping @MainActor () -> Void) -> FailureAction {
            FailureAction(title: "Transcribe Anyway", icon: "waveform", hint: "↩", run: run)
        }

        static func openSettings(_ run: @escaping @MainActor () -> Void) -> FailureAction {
            FailureAction(title: "Open Settings", icon: "gear", hint: nil, run: run)
        }

        static func addAPIKey(_ run: @escaping @MainActor () -> Void) -> FailureAction {
            FailureAction(title: "Add API Key", icon: "key.fill", hint: nil, run: run)
        }

        /// The provider refused the key: fix it here, then Retry. Kept for
        /// the review's action failures; a take's card words it through
        /// `FailureCardCopy`, the same words.
        static func checkAPIKey(_ run: @escaping @MainActor () -> Void) -> FailureAction {
            FailureAction(title: "Check API Key", icon: "key.fill", hint: nil, run: run)
        }
    }

    // MARK: - Review flow

    private func enterReview(
        text: String,
        cursorLocation: Int? = nil,
        banner: String? = nil,
        bannerRetry: (@MainActor () -> Void)? = nil,
        bannerAction: FailureAction? = nil
    ) {
        // Invalidate any action that slipped in during a previous session's
        // exit window (e.g. ⌘R then ⌘1 in quick succession) so a stale
        // transform can never overwrite this session's transcript.
        cancelReviewAction()
        // Hands the Escape route over from the transcribing HUD to this one
        // (`installReviewEscMonitor` below re-arms the shared global tap).
        removeTranscribingEscMonitor()
        state = .reviewing(text: text)
        LiveHUDPanel.shared.showReview(
            text: text,
            cursorLocation: cursorLocation,
            banner: banner,
            onPaste: { [weak self] in self?.confirmPaste() },
            onCancel: { [weak self] in self?.cancelReview() },
            onResume: { [weak self] in self?.resumeRecording() },
            onRetry: bannerRetry,
            secondaryActionTitle: bannerAction?.title,
            secondaryActionIcon: bannerAction?.icon,
            onSecondaryAction: bannerAction?.run,
            onRunAction: { [weak self] action in self?.runReviewAction(action) }
        )
        installReviewEscMonitor()
    }

    // MARK: - Review actions

    /// Physical digit-row keys for ⌘1–⌘9 (kVK_ANSI_* codes are not
    /// contiguous). Positional matching keeps the shortcuts working on
    /// layouts where digits live on the shifted layer (e.g. AZERTY).
    private static let reviewActionDigitKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1, UInt16(kVK_ANSI_2): 2, UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4, UInt16(kVK_ANSI_5): 5, UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7, UInt16(kVK_ANSI_8): 8, UInt16(kVK_ANSI_9): 9,
    ]

    /// What the review banner held when an action took it over: a take's own
    /// notice ("Microphone dropped out…"), or a failed Resume take's message
    /// with its Retry and key action. An action hides it while it runs and
    /// covers it with its own failure, but it is about the dictation, not the
    /// action, so it comes back whenever the action is done with the banner.
    private struct ReviewNotice {
        let message: String?
        let onRetry: (@MainActor () -> Void)?
        let secondaryActionTitle: String?
        let secondaryActionIcon: String?
        let onSecondaryAction: (@MainActor () -> Void)?
    }

    /// The notice an action has the banner over, set from the moment it starts
    /// until it succeeds, is stopped, or its failure is dismissed. Non-nil means
    /// exactly that: an action is running, or its failure is on the banner.
    @ObservationIgnored
    private var noticeUnderAction: ReviewNotice?
    @ObservationIgnored
    private var reviewActionStartedAt = Date.distantPast

    private func runReviewAction(atIndex index: Int) {
        let hud = LiveHUDState.shared
        guard hud.reviewShowsActions else { return }
        // A second ⌘-digit while one runs does nothing, as before: stopping a
        // request that may already be billed is for Esc or a click on its chip,
        // not a repeated shortcut.
        guard hud.runningActionId == nil else { return }
        // ⌘1–⌘9 index into this session's snapshot, matching the chip order.
        let actions = hud.reviewActions
        guard actions.indices.contains(index) else { return }
        runReviewAction(actions[index])
    }

    /// Runs an AI action against the current review text. On success the
    /// transcript is replaced in place (with a Revert snapshot); failures
    /// surface as a banner above the editor. Paste/Cancel/Resume mid-run
    /// cancel the request and keep the text the user was looking at. Clicking
    /// the running action's chip again stops it.
    ///
    /// A failed Resume take's audio and its History row stay exactly where
    /// they were: its Retry is hidden while the action has the banner and comes
    /// back with the notice. Those samples can be the only copy of the take —
    /// History may be off — and dropping them for an unrelated rewrite of the
    /// text above lost a dictation the banner had just promised to retry.
    private func runReviewAction(_ action: DictationAction) {
        guard case .reviewing = state else { return }
        let hud = LiveHUDState.shared
        if hud.runningActionId == action.id {
            // The second click of a double-click is not a Stop: it would end
            // the action before the user saw it start.
            guard Date().timeIntervalSince(reviewActionStartedAt) > 0.5 else { return }
            AppLog.dictation.info("Review action stopped: \(action.name)")
            cancelReviewAction()
            return
        }
        // A pending resume means this review session is already on its way
        // out — don't start a transform that would race the next session.
        guard resumeContext == nil else { return }
        guard hud.runningActionId == nil else { return }
        let original = LiveHUDPanel.shared.currentReviewText
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        AppLog.dictation.info("Running review action: \(action.name) (\(original.count) chars)")
        // A previous action's failure goes, and with it its key action; what
        // it covered is the notice this one holds.
        restoreNoticeUnderAction()
        reviewActionGeneration += 1
        let generation = reviewActionGeneration
        noticeUnderAction = ReviewNotice(
            message: hud.reviewBanner,
            onRetry: hud.onRetry,
            secondaryActionTitle: hud.secondaryActionTitle,
            secondaryActionIcon: hud.secondaryActionIcon,
            onSecondaryAction: hud.onSecondaryAction
        )
        hud.reviewBanner = nil
        hud.onRetry = nil
        hud.secondaryActionTitle = nil
        hud.secondaryActionIcon = nil
        hud.onSecondaryAction = nil
        hud.onActionUndone = { [weak self] in self?.reviewActionUndone() }
        hud.runningActionId = action.id
        reviewActionStartedAt = Date()

        reviewActionTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.reviewActionGeneration == generation {
                    hud.runningActionId = nil
                    self.reviewActionTask = nil
                }
            }
            do {
                let transformed = try await ActionRunner.run(instruction: action.prompt, on: original)
                guard let self, self.reviewActionGeneration == generation,
                      case .reviewing = self.state else { return }
                self.restoreNoticeUnderAction()
                // User edited the transcript while the action was in flight;
                // their edit wins — drop the now-stale transform.
                guard LiveHUDPanel.shared.currentReviewText == original else {
                    AppLog.dictation.info("Review action result dropped (text edited mid-run): \(action.name)")
                    return
                }
                // Unchanged result: applying it would only desync the recorded
                // caret from the visible one (the editor skips no-op syncs).
                guard transformed != original else {
                    AppLog.dictation.info("Review action returned unchanged text: \(action.name)")
                    return
                }
                hud.actionRevertStack.append(original)
                hud.selectedRange = NSRange(location: (transformed as NSString).length, length: 0)
                hud.reviewText = transformed
                self.state = .reviewing(text: transformed)
                AppLog.dictation.info("Review action succeeded: \(action.name)")
            } catch is CancellationError {
                // Stopped, or the review session ended first: nothing to
                // surface. `cancelReviewAction` has put the notice back and
                // moved the generation on; a cancellation from anywhere else
                // still has to hand the banner back.
                guard let self, self.reviewActionGeneration == generation,
                      case .reviewing = self.state else { return }
                self.restoreNoticeUnderAction()
            } catch {
                guard let self, self.reviewActionGeneration == generation,
                      case .reviewing = self.state else { return }
                AppLog.dictation.error("Review action failed: \(action.name): \(error.localizedDescription)")
                self.showReviewActionFailure(ReviewActionFailure(actionName: action.name, error: error))
            }
        }
    }

    /// Puts the action's failure on the banner, over the notice it holds. A
    /// refused or missing key gets the same way to fix it the failure card
    /// offers; nothing else gets a button, since Retry here would be the take's.
    private func showReviewActionFailure(_ failure: ReviewActionFailure) {
        let hud = LiveHUDState.shared
        let fix: FailureAction? = switch failure.keyAction {
        case .check: .checkAPIKey { WindowOpener.shared.showMain(section: .cloud) }
        case .add: .addAPIKey { WindowOpener.shared.showMain(section: .cloud) }
        case nil: nil
        }
        hud.reviewBanner = failure.message
        hud.onRetry = nil
        hud.secondaryActionTitle = fix?.title
        hud.secondaryActionIcon = fix?.icon
        hud.onSecondaryAction = fix?.run
    }

    /// Hands the banner back to the notice an action took it from. A no-op
    /// when no action has it.
    private func restoreNoticeUnderAction() {
        guard let notice = noticeUnderAction else { return }
        noticeUnderAction = nil
        let hud = LiveHUDState.shared
        hud.reviewBanner = notice.message
        hud.onRetry = notice.onRetry
        hud.secondaryActionTitle = notice.secondaryActionTitle
        hud.secondaryActionIcon = notice.secondaryActionIcon
        hud.onSecondaryAction = notice.onSecondaryAction
    }

    /// Undo on the review card stepped back an action. A failure still on the
    /// banner is from a later attempt the user has just moved past; the
    /// take's notice is not, so it stays — or comes back.
    private func reviewActionUndone() {
        guard case .reviewing = state, LiveHUDState.shared.runningActionId == nil else { return }
        restoreNoticeUnderAction()
    }

    /// Stops the running action, if any, and takes its failure off the banner,
    /// putting back whatever the action covered. Also the first thing every
    /// way out of review does, so a transform landing late can't rewrite text
    /// the user already acted on.
    private func cancelReviewAction() {
        reviewActionGeneration += 1
        reviewActionTask?.cancel()
        reviewActionTask = nil
        LiveHUDState.shared.runningActionId = nil
        restoreNoticeUnderAction()
    }

    /// Esc on the review card, from the card itself or from the paste target.
    /// A running action is what Esc stops, and an action's failure is what it
    /// clears; only a review with neither is cancelled. Discarding the whole
    /// dictation was never what a user pressing Esc at a stuck "Improve
    /// prompt" meant.
    private func handleReviewEscape() {
        guard case .reviewing = state else { return }
        if LiveHUDState.shared.runningActionId != nil || noticeUnderAction != nil {
            AppLog.dictation.info("Review Esc: stopping action / clearing its failure")
            cancelReviewAction()
            return
        }
        cancelReview()
    }

    private func resumeRecording() {
        guard case .reviewing = state else { return }
        // Before any early return: a transform landing after review ends
        // would otherwise leave a shimmering chip on a dead session.
        cancelReviewAction()

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.promptForPermission()
            AppLog.dictation.warning("Missing Accessibility permission, could not resume recording")
            // Stay in review with the reason on a banner. Dropping to `.error`
            // here left the review card on screen over a state that no longer
            // matched it, and took the user's transcript out of reach of Paste.
            LiveHUDState.shared.reviewBanner = PermissionCopy.accessibilityHUDMessage
            // Whatever the banner offered was about the failed take, not this.
            LiveHUDState.shared.secondaryActionTitle = nil
            LiveHUDState.shared.onSecondaryAction = nil
            return
        }

        let context = ResumeContext(
            fullText: LiveHUDPanel.shared.currentReviewText,
            cursorLocation: LiveHUDPanel.shared.currentCursorLocation
        )
        AppLog.dictation.info("Resuming recording at cursor=\(context.cursorLocation) (prefix=\(context.prefix.count)ch, suffix=\(context.suffix.count)ch)")
        resumeContext = context
        removeReviewEscMonitor()

        let startID = recordingStartGate.beginStart(pendingHold: false)
        Task { await startRecording(startID: startID) }
    }

    /// Closes a recording session when the user cancels or the session ends
    /// without producing a transcript. Restores the Review HUD if a Resume
    /// was in flight (so the prior text isn't lost), otherwise hides the
    /// HUD and returns to idle. Failures go through `enterFailureHUD` instead.
    /// `banner` is for the restored review only: what became of the take
    /// that was just abandoned, when there is something to say.
    private func finishRecordingSession(fallbackTo fallbackState: State, banner: String? = nil) {
        // The take produced no transcript, so its note describes audio nobody
        // will ever see — and the review restored below is the *prior* text,
        // which the note would be flatly wrong about.
        pendingReviewBanner = nil
        if let resume = resumeContext {
            resumeContext = nil
            enterReview(
                text: resume.fullText,
                cursorLocation: resume.cursorLocation,
                banner: banner
            )
            return
        }
        // No resume to return to, so the dictation is over and its paste
        // target with it.
        pasteTarget = nil
        LiveHUDPanel.shared.hide()
        state = fallbackState
    }

    private func confirmPaste() {
        guard case .reviewing = state else { return }
        cancelReviewAction()
        lastFailedSamples = nil
        retryModelOverride = nil
        takeHistoryRow = nil
        // The user kept this dictation — its takes stay in History.
        commitPendingHistory()
        let edited = LiveHUDPanel.shared.currentReviewText
        removeReviewEscMonitor()
        // Out of `.reviewing` now, not when delivery finishes: everything
        // that can confirm a paste (the hotkey, Return, the Paste button, the
        // menu, a URL toggle) is gated on `.reviewing`, and delivery is about
        // to spend up to a second awaiting.
        state = .delivering
        LiveHUDPanel.shared.hide()

        // Wait for the hotkey-chord modifiers to release first — otherwise
        // Cmd+V lands as Cmd+Opt+V (or similar) and most apps drop it.
        Task { @MainActor [weak self] in
            let modifierWait = await Self.waitForModifiersClear()
            await self?.deliver(text: edited, path: .review, modifierWait: modifierWait)
        }
    }

    private static func waitForModifiersClear() async -> PasteDeliveryReport.ModifierWait {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: PasteTiming.maxModifierWait)
        while !NSEvent.modifierFlags.intersection(PasteTiming.trackedModifiers).isEmpty,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: PasteTiming.pollInterval)
        }
        let held = NSEvent.modifierFlags.intersection(PasteTiming.trackedModifiers)
        let wait = PasteDeliveryReport.ModifierWait(
            elapsedMs: Self.milliseconds(ContinuousClock.now - start),
            timedOut: !held.isEmpty,
            held: Self.symbols(for: held)
        )
        // Lets the previously-focused app fully accept first-responder
        // status before the synthetic Cmd+V key event lands.
        try? await Task.sleep(for: PasteTiming.focusSettleDelay)
        return wait
    }

    /// The frontmost app — unless that is us with nothing on screen, in which
    /// case the last other app the user was in (see
    /// `PasteFocusPolicy.aimsAtLastExternalApp`). Delivery then finds us
    /// holding activation with the target elsewhere and hands it back.
    private func capturePasteTarget() -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        guard front?.processIdentifier == ownPID else { return front }
        let ownFocusIsEditable = Self.keyWindowAcceptsText()
        let focusedAppPID = ownFocusIsEditable ? nil : Self.axFocusedApplicationPID()
        let last = lastExternalApp.flatMap { $0.isTerminated ? nil : $0 }
        guard PasteFocusPolicy.aimsAtLastExternalApp(
            ownPID: ownPID,
            frontmostPID: front?.processIdentifier,
            ownWindowOnScreen: Self.ownWindowOnScreen(),
            ownFocusIsEditable: ownFocusIsEditable,
            focusedAppPID: focusedAppPID,
            lastExternalPID: last?.processIdentifier
        ), let last else { return front }
        AppLog.dictation.notice(
            "Paste target: we were frontmost with nowhere to type; aiming at \(Self.appLabel(last), privacy: .public)"
        )
        return last
    }

    /// Whether the user can see a window of ours: an alert, or a window that
    /// can be main (Settings). The status item and the HUD panel can't be
    /// main, so they don't count.
    private static func ownWindowOnScreen() -> Bool {
        NSApp.modalWindow != nil
            || NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }
    }

    /// Whether our key window's first responder can take a paste. The field
    /// editor behind a SwiftUI TextField / SecureField and a TextEditor are
    /// both NSTextViews.
    private static func keyWindowAcceptsText() -> Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable == true
    }

    /// The app holding keyboard focus according to Accessibility — unlike
    /// `frontmostApplication`, this sees another app's nonactivating panel
    /// (Spotlight, Raycast) sitting over ours. Nil if it can't be read.
    private static func axFocusedApplicationPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &value
        ) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(value as! AXUIElement, &pid) == .success ? pid : nil
    }

    private enum PasteTiming {
        static let trackedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        static let pollInterval: Duration = .milliseconds(15)
        static let maxModifierWait: Duration = .milliseconds(400)
        static let focusSettleDelay: Duration = .milliseconds(40)
        /// How long a handed-back activation may take to show up as the
        /// frontmost app. Cooperative activation normally lands in one or two
        /// polls; past this, something is holding on to activation and a ⌘V
        /// posted anyway would go wherever that is.
        static let maxHandOffWait: Duration = .milliseconds(500)
    }

    // MARK: - Output

    /// Posts ⌘V into the app the dictation was aimed at, or — when that can't
    /// be done safely — leaves the transcript on the clipboard and says so.
    /// Shared by the review path and the no-review path; both enter
    /// `.delivering` before calling, and every exit below leaves it for
    /// `.idle` or `.error`.
    ///
    /// Everything that decides where ⌘V goes is read *after* the last await
    /// that precedes the post, never carried across one.
    private func deliver(
        text: String,
        path: PasteDeliveryReport.Path,
        modifierWait: PasteDeliveryReport.ModifierWait?
    ) async {
        // Spent whatever happens below: this dictation is over.
        let target = pasteTarget
        pasteTarget = nil

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.promptForPermission()
            AppLog.dictation.warning("Missing Accessibility permission, could not type \(text.count) characters")
            enterFailureHUD(
                message: PermissionCopy.accessibilityHUDMessage,
                action: .openSettings { AccessibilityPermission.openSystemSettings() }
            )
            return
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ownAppActive = NSApp.isActive
        // The review panel is already ordered out, so this reads a Settings
        // window of ours, or nothing.
        let ownFocusIsEditable = Self.keyWindowAcceptsText()
        // Only the aimed-at-us branch of the policy reads it, so the ordinary
        // paste never pays for the Accessibility round trip.
        let aimedAtUsOrNowhere = target == nil || target?.processIdentifier == ownPID
        let focusedApp = aimedAtUsOrNowhere ? Self.axFocusedApplicationPID() : nil
        let decision = PasteFocusPolicy.decide(
            ownPID: ownPID,
            targetPID: target?.processIdentifier,
            targetTerminated: target?.isTerminated ?? false,
            frontmostPID: frontmost?.processIdentifier,
            ownAppActive: ownAppActive,
            ownFocusIsEditable: ownFocusIsEditable,
            focusedAppPID: focusedApp
        )
        var report = PasteDeliveryReport(
            path: path,
            target: Self.appLabel(target),
            frontmost: Self.appLabel(frontmost),
            ownAppActive: ownAppActive,
            decision: decision,
            ownFocusIsEditable: ownFocusIsEditable,
            focusedApp: aimedAtUsOrNowhere
                ? PasteDeliveryReport.appLabel(
                    bundleID: focusedApp.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
                    pid: focusedApp
                )
                : nil,
            modifierWait: modifierWait,
            postEventAccess: CGPreflightPostEventAccess(),
            secureInput: IsSecureEventInputEnabled(),
            textLength: text.count
        )

        switch decision {
        case .post, .postAfterAppSwitch, .postToSelf:
            break
        case .handOff:
            guard let target else { break }
            let handOff = await handActivationBack(to: target)
            report.handOff = handOff
            guard handOff.arrived else {
                fallBackToClipboard(text: text, appName: target.localizedName ?? "the other app", report: report)
                return
            }
        case .copyOnly:
            // Aimed at us or nowhere: there is no other app to name.
            let appName = aimedAtUsOrNowhere ? nil : (target?.localizedName ?? "the other app")
            fallBackToClipboard(text: text, appName: appName, report: report)
            return
        }

        report.eventsCreated = KeystrokeOutput.type(text)
        AppLog.dictation.notice("\(report.description, privacy: .public)")
        // Guarded rather than assigned: nothing reachable from `.delivering`
        // can move the state today, but if something ever does, it owns it.
        if state == .delivering { state = .idle }
    }

    /// Gives activation back to the dictation's target and waits until it is
    /// really frontmost. Cooperative activation (macOS 14+): yielding first is
    /// what lets the target's `activate()` succeed without the old
    /// ignoring-other-apps hammer.
    private func handActivationBack(
        to target: NSRunningApplication
    ) async -> PasteDeliveryReport.HandOff {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: PasteTiming.maxHandOffWait)
        NSApp.yieldActivation(to: target)
        let requested = target.activate()
        var frontmost = NSWorkspace.shared.frontmostApplication
        while frontmost?.processIdentifier != target.processIdentifier,
              ContinuousClock.now < deadline {
            try? await Task.sleep(for: PasteTiming.pollInterval)
            frontmost = NSWorkspace.shared.frontmostApplication
        }
        let arrivedDuringWait = frontmost?.processIdentifier == target.processIdentifier
        if arrivedDuringWait {
            // Let the target's key window take first responder, then read
            // again: ⌘V is posted right after this returns with no further
            // await, so this is the reading it actually goes out against.
            // Activation that bounced back to us during the settle shows up
            // here as frontmost ≠ target.
            try? await Task.sleep(for: PasteTiming.focusSettleDelay)
            frontmost = NSWorkspace.shared.frontmostApplication
        }
        let arrived = frontmost?.processIdentifier == target.processIdentifier
        return PasteDeliveryReport.HandOff(
            elapsedMs: Self.milliseconds(ContinuousClock.now - start),
            requested: requested,
            arrived: arrived,
            lostAfterSettle: arrivedDuringWait && !arrived,
            frontmostAfter: Self.appLabel(frontmost)
        )
    }

    /// The paste had nowhere safe to go. Posting ⌘V anyway would drop it into
    /// our own process and the clipboard restore would then erase it, so the
    /// transcript stays on the clipboard — no ⌘V, no restore — and the card
    /// says where it is. Close only: re-running the audio can't fix focus.
    ///
    /// `appName` nil means the paste was aimed at us or nowhere known, so
    /// there is no other app to name.
    private func fallBackToClipboard(
        text: String,
        appName: String?,
        report: PasteDeliveryReport
    ) {
        KeystrokeOutput.copyOnly(text)
        AppLog.dictation.error("\(report.description, privacy: .public)")
        // The card takes key, and we may well still be the active app, so a
        // ⌘V pressed straight away would land on the card: the user has to
        // click into the destination first.
        enterFailureHUD(
            message: Self.pasteFallbackMessage(appName: appName),
            detail: "Click where it goes, then press ⌘V."
        )
    }

    private static func pasteFallbackMessage(appName: String?) -> String {
        guard let appName else {
            return "Nothing had keyboard focus to paste into — the text is on your clipboard."
        }
        return "Couldn't paste into \(appName) — the text is on your clipboard."
    }

    private static func appLabel(_ app: NSRunningApplication?) -> String {
        PasteDeliveryReport.appLabel(bundleID: app?.bundleIdentifier, pid: app?.processIdentifier)
    }

    private static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
