import Foundation

struct PasteFocusPolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw PasteFocusPolicyHarnessFailure(description: message)
    }
}

private let us: pid_t = 100
private let notes: pid_t = 200
private let safari: pid_t = 300
private let raycast: pid_t = 400

private func decide(
    target: pid_t?,
    terminated: Bool = false,
    frontmost: pid_t?,
    active: Bool = false,
    ownText: Bool = false,
    focused: pid_t? = nil
) -> PasteFocusPolicy.Decision {
    PasteFocusPolicy.decide(
        ownPID: us,
        targetPID: target,
        targetTerminated: terminated,
        frontmostPID: frontmost,
        ownAppActive: active,
        ownFocusIsEditable: ownText,
        focusedAppPID: focused
    )
}

private func aimsElsewhere(
    frontmost: pid_t?,
    ownWindow: Bool = false,
    ownText: Bool = false,
    focused: pid_t? = nil,
    last: pid_t?
) -> Bool {
    PasteFocusPolicy.aimsAtLastExternalApp(
        ownPID: us,
        frontmostPID: frontmost,
        ownWindowOnScreen: ownWindow,
        ownFocusIsEditable: ownText,
        focusedAppPID: focused,
        lastExternalPID: last
    )
}

@main
struct PasteFocusPolicyHarness {
    static func main() throws {
        try theTargetStillFrontmostPostsStraightAway()
        try aDeliberateAppSwitchPastesWhereTheUserIs()
        try weStoleActivationSoItIsHandedBack()
        try anActiveFlagAloneStillHandsBack()
        try dictatingIntoOurOwnWindowPostsIntoIt()
        try aimedAtUsWithNowhereToTypeFallsBackToTheClipboard()
        try aimedAtUsWhileAnotherAppHoldsFocusPosts()
        try anUnknownTargetPostsAsBefore()
        try aTargetThatQuitFallsBackToTheClipboard()
        try aTargetThatQuitDoesNotMatterWhileAnotherAppIsFrontmost()
        try noFrontmostAppAtAllStillPosts()
        try aFreshStartWithUsFrontmostAimsAtTheLastOtherApp()
        try theReportNamesEveryFieldAndNeverTheText()
        print("Paste focus policy harness passed")
    }

    private static func theTargetStillFrontmostPostsStraightAway() throws {
        try expect(decide(target: notes, frontmost: notes) == .post, "target frontmost → post")
        try expect(
            decide(target: notes, terminated: false, frontmost: notes, active: false) == .post,
            "the normal path never waits on a hand-off"
        )
    }

    /// A third-party app is frontmost and it is not the target: the user moved
    /// on purpose, so the paste follows them.
    private static func aDeliberateAppSwitchPastesWhereTheUserIs() throws {
        try expect(
            decide(target: notes, frontmost: safari) == .postAfterAppSwitch,
            "frontmost ≠ target, neither is us → paste where the user is"
        )
        try expect(
            decide(target: us, frontmost: safari) == .postAfterAppSwitch,
            "started in our Settings, then switched away → paste where the user is"
        )
    }

    /// The reproduced failure: something activated us while the user was
    /// dictating into Notes, and ⌘V would land in our own process.
    private static func weStoleActivationSoItIsHandedBack() throws {
        try expect(
            decide(target: notes, frontmost: us, active: true) == .handOff,
            "we are frontmost and active, target elsewhere → hand activation back"
        )
        try expect(
            decide(target: notes, frontmost: us, active: false) == .handOff,
            "frontmost alone is enough"
        )
    }

    /// `NSApp.isActive` without being frontmost — the key-thief state a
    /// nonactivating key panel leaves. Harmless to hand back: the target is
    /// already frontmost, so the hand-off completes on its first poll.
    private static func anActiveFlagAloneStillHandsBack() throws {
        try expect(
            decide(target: notes, frontmost: notes, active: true) == .handOff,
            "active flag with the target frontmost → hand-off (a no-op in practice)"
        )
    }

    private static func dictatingIntoOurOwnWindowPostsIntoIt() throws {
        try expect(
            decide(target: us, frontmost: us, active: true, ownText: true, focused: us) == .postToSelf,
            "target is us, a text field of ours has focus → post into it"
        )
        try expect(
            decide(target: us, terminated: true, frontmost: us, active: true, ownText: true) == .postToSelf,
            "our own pid is never treated as a quit target"
        )
    }

    /// The reported symptom's other ordering: we were already active when the
    /// dictation started (an update alert dismissed with "Later", Settings
    /// left behind), and nothing of ours can take a paste.
    private static func aimedAtUsWithNowhereToTypeFallsBackToTheClipboard() throws {
        try expect(
            decide(target: us, frontmost: us, active: true, ownText: false, focused: us) == .copyOnly,
            "target us, no text field, focus ours → clipboard, never a dropped ⌘V"
        )
        try expect(
            decide(target: us, frontmost: us, active: true, ownText: false, focused: nil) == .copyOnly,
            "Accessibility couldn't say where focus is → clipboard"
        )
        try expect(
            decide(target: nil, frontmost: us, active: true, ownText: false, focused: us) == .copyOnly,
            "no target, no text field → clipboard"
        )
        try expect(
            decide(target: us, terminated: true, frontmost: us, active: true, ownText: false, focused: us) == .copyOnly,
            "our own pid as target, quit flag or not → clipboard"
        )
    }

    /// A nonactivating panel of another app (Raycast, Spotlight) holds focus
    /// over our active app: ⌘V reaches the panel today, so keep posting.
    private static func aimedAtUsWhileAnotherAppHoldsFocusPosts() throws {
        try expect(
            decide(target: us, frontmost: us, active: true, ownText: false, focused: raycast) == .post,
            "another app's panel has keyboard focus → post into it"
        )
        try expect(
            decide(target: nil, frontmost: notes, active: true, ownText: false) == .post,
            "no target, active flag only, another app frontmost → post"
        )
    }

    private static func anUnknownTargetPostsAsBefore() throws {
        try expect(
            decide(target: nil, frontmost: us, active: true, ownText: true) == .postToSelf,
            "no target captured, a text field of ours has focus → post into it"
        )
        try expect(
            decide(target: nil, frontmost: notes) == .post,
            "no target captured and another app is frontmost → post"
        )
    }

    private static func aTargetThatQuitFallsBackToTheClipboard() throws {
        try expect(
            decide(target: notes, terminated: true, frontmost: us, active: true) == .copyOnly,
            "target quit and we are frontmost → clipboard, never a ⌘V into ourselves"
        )
        try expect(
            decide(target: notes, terminated: true, frontmost: nil, active: true) == .copyOnly,
            "target quit, active flag only → clipboard"
        )
    }

    private static func aTargetThatQuitDoesNotMatterWhileAnotherAppIsFrontmost() throws {
        try expect(
            decide(target: notes, terminated: true, frontmost: safari) == .postAfterAppSwitch,
            "target quit, another app frontmost → paste where the user is"
        )
    }

    private static func noFrontmostAppAtAllStillPosts() throws {
        try expect(
            decide(target: notes, frontmost: nil) == .post,
            "no frontmost app and we are not active → post as before"
        )
    }

    private static func aFreshStartWithUsFrontmostAimsAtTheLastOtherApp() throws {
        try expect(
            aimsElsewhere(frontmost: us, focused: us, last: notes),
            "we are frontmost with nothing on screen → aim at the app behind us"
        )
        try expect(
            !aimsElsewhere(frontmost: us, ownWindow: true, focused: us, last: notes),
            "a Settings window or alert is up → don't guess the app behind it"
        )
        try expect(
            aimsElsewhere(frontmost: us, focused: nil, last: notes),
            "Accessibility unreadable → still aim at the app behind us"
        )
        try expect(
            !aimsElsewhere(frontmost: us, ownText: true, focused: us, last: notes),
            "a Settings text field has focus → dictate into it"
        )
        try expect(
            !aimsElsewhere(frontmost: us, focused: raycast, last: notes),
            "another app's panel has focus over us → leave the target alone"
        )
        try expect(
            !aimsElsewhere(frontmost: notes, focused: notes, last: safari),
            "another app is frontmost → it is the target"
        )
        try expect(
            !aimsElsewhere(frontmost: us, focused: us, last: nil),
            "no other app seen yet → nothing to aim at"
        )
        try expect(
            !aimsElsewhere(frontmost: us, focused: us, last: us),
            "never aims at ourselves as the 'other' app"
        )
    }

    private static func theReportNamesEveryFieldAndNeverTheText() throws {
        var report = PasteDeliveryReport(
            path: .review,
            target: PasteDeliveryReport.appLabel(bundleID: "com.apple.Notes", pid: notes),
            frontmost: PasteDeliveryReport.appLabel(bundleID: nil, pid: us),
            ownAppActive: true,
            decision: .handOff,
            ownFocusIsEditable: false,
            focusedApp: nil,
            modifierWait: .init(elapsedMs: 400, timedOut: true, held: "⌥"),
            postEventAccess: false,
            secureInput: true,
            textLength: 42
        )
        report.handOff = .init(elapsedMs: 31, requested: true, arrived: true, frontmostAfter: "com.apple.Notes/200")
        report.eventsCreated = true
        let line = report.description
        try expect(line.hasPrefix("Paste: "), "greppable prefix: \(line)")
        for field in [
            "path=review", "decision=handOff", "target=com.apple.Notes/200", "front=?/100",
            "active=1", "ownText=0", "axFocus=n/a", "handoff=ok/31ms(req=1 front=com.apple.Notes/200)",
            "modwait=400ms/timeout held=⌥", "postAccess=0", "secureInput=1",
            "events=1", "len=42",
        ] {
            try expect(line.contains(field), "report carries \(field): \(line)")
        }

        report.handOff = .init(elapsedMs: 500, requested: false, arrived: false, frontmostAfter: "none")
        report.eventsCreated = nil
        report.modifierWait = nil
        report.path = .direct
        let fallback = report.description
        for field in ["path=direct", "handoff=timeout/500ms(req=0 front=none)", "modwait=n/a", "events=none"] {
            try expect(fallback.contains(field), "fallback report carries \(field): \(fallback)")
        }
        try expect(!fallback.contains("ax="), "no dead ax= field: \(fallback)")

        report.handOff = .init(
            elapsedMs: 72, requested: true, arrived: false, lostAfterSettle: true, frontmostAfter: "?/100"
        )
        report.decision = .copyOnly
        report.ownFocusIsEditable = true
        report.focusedApp = PasteDeliveryReport.appLabel(bundleID: nil, pid: us)
        let lost = report.description
        for field in ["handoff=lost/72ms(req=1 front=?/100)", "decision=copyOnly", "ownText=1", "axFocus=?/100"] {
            try expect(lost.contains(field), "bounced hand-off report carries \(field): \(lost)")
        }
        try expect(
            PasteDeliveryReport.appLabel(bundleID: "x", pid: nil) == "none",
            "no app → none"
        )
    }
}
