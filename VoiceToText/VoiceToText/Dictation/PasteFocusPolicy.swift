import Foundation

/// Where the synthetic ⌘V is allowed to go, decided just before it is posted.
///
/// ⌘V is delivered to whichever app is active, and `CGEventPost` is fire and
/// forget: if *we* are the active app when it lands, it reaches our own process
/// — which has no text field to put it in — and is dropped without a trace. The
/// clipboard restore then runs on schedule and the transcript is gone from the
/// clipboard (History keeps the raw take, not the review card's edits).
/// That is the one reproduced way to get "the card closed and nothing was
/// pasted", and it needs nothing more exotic than an update alert or a Settings
/// window having activated us — during the dictation, or before it started.
///
/// So the controller remembers which app a dictation was aimed at (see
/// `aimsAtLastExternalApp` for the case where that would be us), and asks
/// this policy — with nothing but process ids and flags — whether to post
/// straight away, hand activation back to that app first, or not post at all.
///
/// Deliberately pure: no AppKit, no `NSRunningApplication`, no actor. Every
/// branch is exercised by `Tests/PasteFocusPolicyHarness.swift`.
nonisolated enum PasteFocusPolicy {
    enum Decision: String, Equatable, CustomStringConvertible {
        /// Another app is active and it is the one the dictation was aimed at
        /// (or no target was captured to compare against).
        case post
        /// Another app is active, but not the target: the user switched apps on
        /// purpose between starting and pasting. Paste where they are now.
        case postAfterAppSwitch
        /// We are active, the dictation was aimed at us (or nowhere known), and
        /// one of our text views has keyboard focus — a Settings text field.
        /// There is nothing to hand activation back to, and ⌘V has somewhere
        /// to land, so post as we always did.
        case postToSelf
        /// We are active and the target is another, still-running app. Give it
        /// activation back, wait until it really is frontmost, then post.
        case handOff
        /// We are active and ⌘V would land in our own process with nothing to
        /// take it: the target has quit, or the dictation was aimed at us (or
        /// nowhere known) and no text view of ours — nor any other app — has
        /// keyboard focus. Leave the text on the clipboard instead.
        case copyOnly

        var description: String { rawValue }
    }

    /// - Parameters:
    ///   - ownPID: this process.
    ///   - targetPID: the app that was frontmost when the dictation started, or
    ///     nil if none was known.
    ///   - targetTerminated: whether that app has since quit.
    ///   - frontmostPID: `NSWorkspace.frontmostApplication` right now.
    ///   - ownAppActive: `NSApp.isActive` right now. Only meaningful once the
    ///     review panel has been ordered out: while that nonactivating panel is
    ///     key, WindowServer reports us active even though the target is still
    ///     frontmost. Counted as "we hold activation" on its own because a false
    ///     positive costs nothing — handing activation to an app that already
    ///     has it completes on the first poll.
    ///   - ownFocusIsEditable: our key window's first responder is an editable
    ///     text view, read after the review panel is gone. Only consulted when
    ///     the dictation was aimed at us or nowhere known.
    ///   - focusedAppPID: the Accessibility focused application, or nil if it
    ///     couldn't be read. Only consulted in that same case: it is how a
    ///     third-party nonactivating panel (Spotlight, Raycast) holding keyboard
    ///     focus over our active app is told apart from focus that is really
    ///     ours — in the first case ⌘V pastes into the panel.
    static func decide(
        ownPID: pid_t,
        targetPID: pid_t?,
        targetTerminated: Bool,
        frontmostPID: pid_t?,
        ownAppActive: Bool,
        ownFocusIsEditable: Bool,
        focusedAppPID: pid_t?
    ) -> Decision {
        let weHoldActivation = frontmostPID == ownPID || ownAppActive
        guard weHoldActivation else {
            if let targetPID, let frontmostPID, frontmostPID != targetPID {
                return .postAfterAppSwitch
            }
            return .post
        }
        guard let targetPID, targetPID != ownPID else {
            // Aimed at us, or at nothing known: ⌘V only lands if one of our
            // text views has focus, or another app holds keyboard focus.
            if ownFocusIsEditable { return .postToSelf }
            let focusElsewhere = [focusedAppPID, frontmostPID].contains { $0 != nil && $0 != ownPID }
            return focusElsewhere ? .post : .copyOnly
        }
        return targetTerminated ? .copyOnly : .handOff
    }

    /// Whether a fresh dictation should be aimed at the last other app the
    /// user was in, instead of at the frontmost app.
    ///
    /// Only when the frontmost app is us with nothing of ours on screen: the
    /// Settings window closed (the app stays active with no window), an update
    /// alert dismissed with "Later". The user is looking at the app behind
    /// ours, and aiming at us would end in a ⌘V with nothing to take it. Not
    /// while a window of ours is still up — the app behind it may not be the
    /// one the user means, so that case falls back to the clipboard instead —
    /// nor when one of our text fields has focus (dictating into Settings), nor
    /// when another app's nonactivating panel holds keyboard focus over us —
    /// ⌘V reaches that panel as it is.
    static func aimsAtLastExternalApp(
        ownPID: pid_t,
        frontmostPID: pid_t?,
        ownWindowOnScreen: Bool,
        ownFocusIsEditable: Bool,
        focusedAppPID: pid_t?,
        lastExternalPID: pid_t?
    ) -> Bool {
        guard frontmostPID == ownPID, !ownWindowOnScreen, !ownFocusIsEditable else { return false }
        if let focusedAppPID, focusedAppPID != ownPID { return false }
        guard let lastExternalPID else { return false }
        return lastExternalPID != ownPID
    }
}

/// The one persisted line each delivery leaves behind, so the next "the card
/// closed and nothing was pasted" report arrives with its cause attached.
///
/// Logged at `.notice` (a normal delivery) or `.error` (a fallback to the
/// clipboard) — `.info` is not persisted, which is why the original report came
/// with no trail at all. Holds the transcript's *length* and never its text:
/// this line is meant to be pasted into a bug report.
nonisolated struct PasteDeliveryReport: CustomStringConvertible {
    enum Path: String {
        /// Confirmed from the review card.
        case review
        /// Review-before-paste off: straight from transcription.
        case direct
    }

    struct ModifierWait {
        var elapsedMs: Int
        var timedOut: Bool
        /// Modifiers still down when the wait ended, as symbols ("⌥", "⌘⇧").
        var held: String
    }

    struct HandOff {
        var elapsedMs: Int
        /// What the target's `activate()` returned. False means the system
        /// refused the request outright, as opposed to it simply not landing.
        var requested: Bool
        /// The target was frontmost after the settle that follows the wait —
        /// the reading ⌘V is posted against.
        var arrived: Bool
        /// The target came forward during the wait but had lost activation
        /// again by the end of the settle.
        var lostAfterSettle: Bool = false
        /// `appLabel` of whatever was frontmost after the settle.
        var frontmostAfter: String
    }

    var path: Path
    var target: String
    var frontmost: String
    var ownAppActive: Bool
    var decision: PasteFocusPolicy.Decision
    /// Whether our key window's first responder was an editable text view.
    var ownFocusIsEditable: Bool
    /// `appLabel` of the Accessibility focused application; nil when it wasn't
    /// probed (the dictation was aimed at another app).
    var focusedApp: String?
    var handOff: HandOff?
    /// Nil on the direct path, which has no hotkey chord to wait out.
    var modifierWait: ModifierWait?
    var postEventAccess: Bool
    var secureInput: Bool
    /// Nil when nothing was posted (the clipboard fallback).
    var eventsCreated: Bool?
    var textLength: Int

    /// "com.apple.Notes/412", or "none" when there is no app.
    static func appLabel(bundleID: String?, pid: pid_t?) -> String {
        guard let pid else { return "none" }
        return "\(bundleID ?? "?")/\(pid)"
    }

    var description: String {
        var fields = [
            "Paste:",
            "path=\(path.rawValue)",
            "decision=\(decision)",
            "target=\(target)",
            "front=\(frontmost)",
            "active=\(Self.flag(ownAppActive))",
            "ownText=\(Self.flag(ownFocusIsEditable))",
            "axFocus=\(focusedApp ?? "n/a")",
        ]
        if let handOff {
            let outcome = handOff.arrived ? "ok" : handOff.lostAfterSettle ? "lost" : "timeout"
            fields.append(
                "handoff=\(outcome)/\(handOff.elapsedMs)ms(req=\(Self.flag(handOff.requested)) front=\(handOff.frontmostAfter))"
            )
        }
        if let modifierWait {
            let held = modifierWait.held.isEmpty ? "-" : modifierWait.held
            let timedOut = modifierWait.timedOut ? "/timeout" : ""
            fields.append("modwait=\(modifierWait.elapsedMs)ms\(timedOut) held=\(held)")
        } else {
            fields.append("modwait=n/a")
        }
        fields.append(contentsOf: [
            "postAccess=\(Self.flag(postEventAccess))",
            "secureInput=\(Self.flag(secureInput))",
            "events=\(eventsCreated.map(Self.flag) ?? "none")",
            "len=\(textLength)",
        ])
        return fields.joined(separator: " ")
    }

    private static func flag(_ value: Bool) -> String { value ? "1" : "0" }
}
