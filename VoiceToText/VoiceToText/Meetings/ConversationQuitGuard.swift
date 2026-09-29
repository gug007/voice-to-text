import AppKit
import OSLog

/// Stands between a quit (⌘Q, the menu bar's Quit, logout or restart, an
/// update's relaunch) and a conversation that is still recording or
/// transcribing. Quitting there used to cut the capture off and bring the audio
/// back on the next launch as an untranscribed placeholder. Now the user
/// chooses: Stop & Save runs the normal stop → transcribe → archive and then
/// quits, Keep Recording cancels the quit, Quit Anyway quits at once and leaves
/// the audio for launch-time recovery.
@MainActor
final class ConversationQuitGuard {
    static let shared = ConversationQuitGuard()
    private init() {}

    /// Set while a deferred quit waits for its answer, so a second quit request
    /// meanwhile can't stack a second set of alerts.
    private var isDeciding = false
    /// Whether the main queue has drained since the pending quit was deferred.
    /// See `reply(to:)`.
    private var mainQueueIsLive = false
    /// A quit withdrawn only until a save finishes. Choosing to keep going in a
    /// later quit prompt clears it, so the app doesn't quit after all.
    private var quitAfterSave = false

    /// `applicationShouldTerminate`'s answer. With no conversation busy it is
    /// `.terminateNow`, so every other quit (the permission gate's relaunch, an
    /// update's) goes straight through.
    ///
    /// Otherwise the quit is deferred. While it waits, AppKit turns the main run
    /// loop in modal-panel mode, which runs run-loop callouts but drains the
    /// main queue (where all main-actor work runs, the conversation's included)
    /// only if `terminate` wasn't itself called from a main-queue block, such as
    /// an async hop or a main-actor task: a nested run loop never re-enters the
    /// queue it's running on. So the prompt runs as a run-loop callout, and a
    /// probe block on the main queue reports whether the save can progress while
    /// the quit waits. Nothing ever blocks the main thread on the save, and the
    /// reply comes only after it, so `applicationWillTerminate`'s History flush
    /// has nothing to wait for but the IO queue.
    func reply(to sender: NSApplication) -> NSApplication.TerminateReply {
        guard MeetingController.shared.isBusy else { return .terminateNow }
        guard !isDeciding else { return .terminateCancel }
        isDeciding = true
        mainQueueIsLive = false
        DispatchQueue.main.async {
            self.mainQueueIsLive = true
        }
        RunLoop.main.perform(inModes: [.default, .modalPanel]) {
            MainActor.assumeIsolated { self.decide() }
        }
        return .terminateLater
    }

    private enum Choice { case save, keepGoing, quitAnyway }

    private func decide() {
        let meetings = MeetingController.shared
        // The work may have finished on its own before the prompt could show.
        guard meetings.isBusy else { return answer(true) }
        switch askHowToQuit(recording: Self.isRecording(meetings.state)) {
        case .keepGoing:
            quitAfterSave = false
            answer(false)
        case .quitAnyway:
            AppLog.audio.notice("Quitting during a conversation; the audio is left for launch recovery")
            answer(true)
        case .save where mainQueueIsLive:
            saveWithProgress()
            answer(true)
        case .save:
            // The save can't progress while this quit waits (see `reply(to:)`).
            // Withdraw it, save with the app running, then quit again, which
            // goes straight through once nothing is busy.
            answer(false)
            quitAfterSave = true
            Task {
                WindowOpener.shared.showMain(section: .meetings)
                await meetings.finishForQuit()
                guard quitAfterSave else { return }
                quitAfterSave = false
                NSApp.terminate(nil)
            }
        }
    }

    private func answer(_ terminate: Bool) {
        isDeciding = false
        NSApp.reply(toApplicationShouldTerminate: terminate)
    }

    /// A start still in flight counts as recording: once it lands, Stop & Save
    /// stops it like any other recording.
    private static func isRecording(_ state: MeetingController.State) -> Bool {
        switch state {
        case .transcribing, .importing: return false
        case .recording, .idle, .error: return true
        }
    }

    private func askHowToQuit(recording: Bool) -> Choice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let aftermath = "If you quit anyway, the audio is kept and appears in History without a transcript the next time VoiceToText opens."
        if recording {
            alert.messageText = "A conversation is still recording"
            alert.informativeText = "Stop & Save ends the recording, transcribes it and saves it to History, then quits. \(aftermath)"
            alert.addButton(withTitle: "Stop & Save")
            alert.addButton(withTitle: "Keep Recording")
        } else {
            alert.messageText = "A conversation is still being transcribed"
            alert.informativeText = "VoiceToText can finish the transcript and save it to History, then quit. \(aftermath)"
            alert.addButton(withTitle: "Finish & Quit")
            alert.addButton(withTitle: "Don't Quit")
        }
        // Escape backs out of the quit, whatever the button is called.
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: "Quit Anyway").hasDestructiveAction = true

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .quitAnyway
        default: return .keepGoing
        }
    }

    /// Runs the save behind a "Saving…" alert and returns when it's done. While
    /// a quit is pending only modal panels take clicks, so this alert is both
    /// the progress and the way out of a long transcription: Quit Now leaves the
    /// audio for launch recovery, exactly like Quit Anyway.
    private func saveWithProgress() {
        let meetings = MeetingController.shared
        guard meetings.isBusy else { return }
        // Starts running inside the alert's modal loop, which drains the main
        // queue (the caller checked it can).
        let saving = Task { await meetings.finishForQuit() }

        let alert = NSAlert()
        alert.messageText = "Saving the conversation…"
        alert.informativeText = "VoiceToText quits as soon as it's transcribed and saved to History. A long conversation can take a few minutes. Quit Now keeps the audio for the next launch, without a transcript."
        alert.addButton(withTitle: "Quit Now")

        let closer = Task {
            await saving.value
            guard !Task.isCancelled else { return }
            // stopModal ends a modal loop only from inside its own event
            // handling; from here it takes effect on the next event, so post one.
            NSApp.stopModal()
            if let wake = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                NSApp.postEvent(wake, atStart: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        _ = alert.runModal()
        closer.cancel()
        if meetings.isBusy {
            AppLog.audio.notice("Quit Now while saving a conversation; the audio is left for launch recovery")
        }
    }
}
