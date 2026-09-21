import Foundation

struct AudioConfigChangePolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw AudioConfigChangePolicyHarnessFailure(description: message)
    }
}

@main
struct AudioConfigChangePolicyHarness {
    static func main() throws {
        try theFirstChangeRestartsRatherThanFailing()
        try siblingsOfOneBurstAreNotChargedTwice()
        try onlyBegunRestartsSpendTheBudget()
        try anExhaustedBudgetGivesUp()
        try aSuccessfulRestartAnswersAChangeSeenWhileItRan()
        try aSuccessfulRestartNeverEndsTheTake()
        try aSwallowedFollowUpStillLetsStarvationSalvage()
        try starvationEscalatesOnTheSameBudget()
        try starvationIsSupersededByARestartAlreadyInFlight()
        try theDeadlineStopsARetryLoopBeforeTheBudgetDoes()
        try aLateFirstChangeStillGetsTheFullBudget()
        try aRapidBurstStillExhaustsTheBudget()
        try changesSpreadAcrossMinutesEachGetARestart()
        try aChangeAfterTheResetWindowGetsAFreshDeadline()
        try anUnhealthyTakeCannotBuyANewBudget()
        try aLandedRestartClearsTheDeadlineItWasMeasuredFrom()
        try aGiveUpIsTerminalForTheSession()
        try anAbandonedRestartFreesTheFlagWithoutRefundingTheBudget()
        try resetRestoresTheBudgetBetweenSessions()
        try salvageNeverShowsAnEmptyCardWhileAudioExists()
        print("Audio config change policy harness passed")
    }

    /// The reported bug: AirPods renegotiate ~250 ms in, with ~4 000 samples
    /// banked, and the take used to die there.
    private static func theFirstChangeRestartsRatherThanFailing() throws {
        var policy = AudioConfigChangePolicy()
        try expect(
            policy.changeObserved(now: 0.25, captureHealthy: false) == .scheduleRestart(after: 0.3),
            "the first mid-recording change schedules a restart after the settle delay"
        )
        try expect(policy.isRestarting, "scheduling marks a restart in flight")
        try expect(!policy.hasGivenUp, "and writes nothing off")
    }

    private static func siblingsOfOneBurstAreNotChargedTwice() throws {
        var policy = AudioConfigChangePolicy()
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        try expect(
            policy.changeObserved(now: 0.26, captureHealthy: false) == .ignoreCoalesced,
            "a sibling arriving during the attempt is coalesced"
        )
        try expect(
            policy.changeObserved(now: 0.31, captureHealthy: false) == .ignoreCoalesced,
            "so is the next one"
        )
        try expect(policy.restartsUsed == 1, "coalesced siblings charge nothing")
        try expect(policy.isRestarting, "and leave the attempt in flight")
        try expect(!policy.hasGivenUp, "and record no verdict")
    }

    /// A scheduled attempt whose session ended before it touched CoreAudio must
    /// not have spent anything.
    private static func onlyBegunRestartsSpendTheBudget() throws {
        var policy = AudioConfigChangePolicy()
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        try expect(policy.restartsUsed == 0, "scheduling alone charges nothing")
        policy.restartBegan()
        try expect(policy.restartsUsed == 1, "beginning CoreAudio work is what charges")
    }

    private static func anExhaustedBudgetGivesUp() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 2)
        try expect(
            policy.changeObserved(now: 0.25, captureHealthy: false) == .scheduleRestart(after: 0.3),
            "the first attempt is within budget"
        )
        policy.restartBegan()
        // A failure re-arms the next attempt itself; nothing waits for another
        // notification to retry.
        try expect(
            policy.restartFailed(now: 0.9) == .scheduleRestart(after: 0.3),
            "the second attempt is within budget"
        )
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 1.6) == .giveUp(reason: .budgetExhausted),
            "the third would exceed the budget, so the take ends"
        )
        try expect(policy.hasGivenUp, "and the verdict is on the record")
        try expect(!policy.isRestarting, "with nothing left in flight")
        // Absorbed, not a second give-up: the teardown is already under way
        // and a spent budget cannot be resurrected either way.
        try expect(
            policy.changeObserved(now: 1.7, captureHealthy: false) == .ignoreCoalesced,
            "a further change neither restarts nor raises a second teardown"
        )
    }

    private static func aSuccessfulRestartAnswersAChangeSeenWhileItRan() throws {
        var policy = AudioConfigChangePolicy()
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        _ = policy.changeObserved(now: 0.4, captureHealthy: false)
        try expect(
            policy.restartSucceeded(now: 0.9) == .scheduleRestart(after: 0.3),
            "a change seen mid-restart is answered once the restart lands"
        )
        try expect(policy.restartsUsed == 1, "the follow-up has not begun yet")
    }

    private static func aSuccessfulRestartNeverEndsTheTake() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 1)
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        _ = policy.changeObserved(now: 0.4, captureHealthy: false)
        // Capture is running again, so an exhausted budget here must leave the
        // recording alone rather than kill a take that is working.
        try expect(
            policy.restartSucceeded(now: 0.9) == .ignoreCoalesced,
            "a successful restart with no budget left keeps recording"
        )
        // And must not have recorded the verdict it declined to return: every
        // other entry point short-circuits on `hasGivenUp`, so a take left in
        // that state can neither restart nor salvage.
        try expect(!policy.hasGivenUp, "declining a follow-up is not giving up")
        try expect(!policy.isRestarting, "and leaves nothing in flight")
    }

    /// The failure that state would cause: a restart reports success, delivers
    /// nothing, and the starvation watchdog is the only thing left that can
    /// end the take.
    private static func aSwallowedFollowUpStillLetsStarvationSalvage() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 1)
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        _ = policy.changeObserved(now: 0.4, captureHealthy: false)
        try expect(
            policy.restartSucceeded(now: 0.9) == .ignoreCoalesced,
            "the follow-up is unaffordable and is dropped"
        )
        try expect(
            policy.captureStarved(now: 2.4) == .giveUp(reason: .budgetExhausted),
            "the starved tap can still end the take and salvage its audio"
        )
        try expect(policy.hasGivenUp, "which is the verdict that belongs on the record")
    }

    /// The restart reported success and then no audio arrived: the tap anchored
    /// to a rate the device no longer runs at.
    private static func starvationEscalatesOnTheSameBudget() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 2)
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        _ = policy.restartSucceeded(now: 0.9)
        try expect(
            policy.captureStarved(now: 2.4) == .scheduleRestart(after: 0.3),
            "a starved tap escalates to another restart"
        )
        policy.restartBegan()
        _ = policy.restartSucceeded(now: 3.0)
        try expect(
            policy.captureStarved(now: 4.5) == .giveUp(reason: .budgetExhausted),
            "a starved tap with no budget left ends the take"
        )
        try expect(policy.hasGivenUp, "and the verdict is on the record")
    }

    private static func starvationIsSupersededByARestartAlreadyInFlight() throws {
        var policy = AudioConfigChangePolicy()
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        _ = policy.restartSucceeded(now: 0.9)
        _ = policy.changeObserved(now: 1.0, captureHealthy: false)
        try expect(
            policy.captureStarved(now: 2.4) == .ignoreCoalesced,
            "a late starvation verdict yields to the restart already under way"
        )
        try expect(!policy.hasGivenUp, "yielding is not a verdict")
        try expect(policy.isRestarting, "and does not cancel the attempt it yielded to")
    }

    private static func theDeadlineStopsARetryLoopBeforeTheBudgetDoes() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 10, restartDeadline: 12)
        _ = policy.changeObserved(now: 1, captureHealthy: false)
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 9) == .scheduleRestart(after: 0.3),
            "a retry inside the deadline still gets to try"
        )
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 13.5) == .giveUp(reason: .deadlineExceeded),
            "a retry that would begin past the deadline does not start"
        )
        try expect(policy.hasGivenUp, "and the verdict is on the record")
    }

    /// The deadline runs from the first change, not from the start of capture:
    /// a device that dies twelve seconds into a good take still gets restarted.
    private static func aLateFirstChangeStillGetsTheFullBudget() throws {
        var policy = AudioConfigChangePolicy()
        try expect(
            policy.changeObserved(now: 12.0, captureHealthy: false) == .scheduleRestart(after: 0.3),
            "a change long into a take is a first change, not an expired one"
        )
    }

    /// The anti-storm property, and the reason the burst reset needs the quiet
    /// period as well as the health flag: capture between two notifications of
    /// one storm looks perfectly healthy.
    private static func aRapidBurstStillExhaustsTheBudget() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 3, burstResetAfter: 30)
        var now = 1.0
        for attempt in 1...3 {
            try expect(
                policy.changeObserved(now: now, captureHealthy: true) == .scheduleRestart(after: 0.3),
                "attempt \(attempt) of the burst is within budget"
            )
            policy.restartBegan()
            now += 0.6
            _ = policy.restartSucceeded(now: now)
            now += 1.0
        }
        try expect(
            policy.changeObserved(now: now, captureHealthy: true) == .giveUp(reason: .budgetExhausted),
            "a fourth change inside the same burst window still ends the take"
        )
        try expect(policy.hasGivenUp, "and the verdict is on the record")
    }

    /// The bug the burst reset fixes: the budget is per burst, so a device that
    /// legitimately changes a few times over a long dictation is not capped at
    /// three for the whole session.
    private static func changesSpreadAcrossMinutesEachGetARestart() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 3, burstResetAfter: 30)
        for change in 1...5 {
            let now = Double(change) * 60
            try expect(
                policy.changeObserved(now: now, captureHealthy: true) == .scheduleRestart(after: 0.3),
                "well-separated change \(change) starts its own burst"
            )
            try expect(!policy.hasGivenUp, "and never writes the take off")
            policy.restartBegan()
            _ = policy.restartSucceeded(now: now + 0.5)
        }
    }

    /// The other half of the same bug: `restartDeadline` runs from the burst's
    /// first change, so one benign change early in a long take cannot poison
    /// every later one.
    private static func aChangeAfterTheResetWindowGetsAFreshDeadline() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 3, restartDeadline: 12, burstResetAfter: 30)
        _ = policy.changeObserved(now: 1, captureHealthy: false)
        policy.restartBegan()
        _ = policy.restartSucceeded(now: 1.6)

        // 58 s later than the first change — far outside a deadline measured
        // from the session — and capture has been running the whole time.
        try expect(
            policy.changeObserved(now: 60, captureHealthy: true) == .scheduleRestart(after: 0.3),
            "an unrelated change much later is not instantly past the deadline"
        )
        try expect(!policy.hasGivenUp, "and nothing was written off on the way")
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 69) == .scheduleRestart(after: 0.3),
            "its retries are measured from its own burst, not from the session"
        )
    }

    private static func anUnhealthyTakeCannotBuyANewBudget() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 1, burstResetAfter: 30)
        _ = policy.changeObserved(now: 1, captureHealthy: false)
        policy.restartBegan()
        _ = policy.restartSucceeded(now: 1.6)
        // Minutes later, but the tap has delivered nothing since that restart,
        // so this is a take recording silence — not evidence of recovery.
        try expect(
            policy.changeObserved(now: 300, captureHealthy: false) == .giveUp(reason: .budgetExhausted),
            "time alone does not refill the budget"
        )
        try expect(policy.hasGivenUp, "and the verdict is on the record")
    }

    /// An attempt dropped before it reached the device must not leave the
    /// policy believing a restart is in flight — nor hand back budget that a
    /// storm could then spend again.
    /// The dead zone between the two thresholds: `restartDeadline` is 12 s and
    /// the burst reset needs 30 s of quiet, so a change landing in between used
    /// to be refused on arrival and end a healthy take with its budget unspent.
    private static func aLandedRestartClearsTheDeadlineItWasMeasuredFrom() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 3, restartDeadline: 12, burstResetAfter: 30)
        _ = policy.changeObserved(now: 0, captureHealthy: false)
        policy.restartBegan()
        _ = policy.restartSucceeded(now: 0.4)

        // 20 s in: too soon for the burst reset, far past a deadline anchored
        // to a change this take has already recovered from.
        try expect(
            policy.changeObserved(now: 20, captureHealthy: true) == .scheduleRestart(after: 0.3),
            "a change after a landed restart is answered, not refused on arrival"
        )
        try expect(policy.restartsUsed == 1, "and it still has two attempts left to spend")
        try expect(!policy.hasGivenUp, "and no verdict was recorded on the way")
    }

    /// Once the take is being torn down the budget is moot: further
    /// notifications must not queue a second teardown behind the first.
    private static func aGiveUpIsTerminalForTheSession() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 1)
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 1.0) == .giveUp(reason: .budgetExhausted),
            "the budget runs out"
        )
        try expect(policy.hasGivenUp, "which is terminal")
        try expect(
            policy.changeObserved(now: 1.1, captureHealthy: false) == .ignoreCoalesced,
            "a later change in the same burst is not a second give-up"
        )
        try expect(
            policy.captureStarved(now: 2.6) == .ignoreCoalesced,
            "nor is a starvation verdict that arrives after the decision"
        )
        policy.reset()
        try expect(!policy.hasGivenUp, "the next session starts arguing again")
        try expect(
            policy.changeObserved(now: 30, captureHealthy: false) == .scheduleRestart(after: 0.3),
            "with a full budget"
        )
    }

    private static func anAbandonedRestartFreesTheFlagWithoutRefundingTheBudget() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 2)
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        policy.restartAbandoned()
        try expect(!policy.isRestarting, "abandoning clears the in-flight flag")
        try expect(!policy.hasGivenUp, "and is not a verdict")
        try expect(policy.restartsUsed == 1, "abandoning does not refund the attempt")
        try expect(
            policy.changeObserved(now: 0.9, captureHealthy: false) == .scheduleRestart(after: 0.3),
            "the next change is answered rather than coalesced into a restart that is gone"
        )
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 1.5) == .giveUp(reason: .budgetExhausted),
            "the budget still runs out on schedule"
        )
    }

    private static func resetRestoresTheBudgetBetweenSessions() throws {
        var policy = AudioConfigChangePolicy(maxRestarts: 1)
        _ = policy.changeObserved(now: 0.25, captureHealthy: false)
        policy.restartBegan()
        try expect(
            policy.restartFailed(now: 1.0) == .giveUp(reason: .budgetExhausted),
            "the session's budget is spent"
        )
        policy.reset()
        try expect(policy.restartsUsed == 0, "reset clears the spend")
        try expect(
            policy.changeObserved(now: 40, captureHealthy: false) == .scheduleRestart(after: 0.3),
            "the next session starts with a full budget and a fresh deadline"
        )
    }

    /// The invariant the whole exercise is about: the failure card shows
    /// "Nothing to review." only when there is genuinely nothing.
    private static func salvageNeverShowsAnEmptyCardWhileAudioExists() throws {
        let floor = 8_000
        try expect(
            RecordingSalvage.outcome(sampleCount: 0, minTranscribeSamples: floor) == .failEmpty,
            "no audio is the only empty card"
        )
        try expect(
            RecordingSalvage.outcome(sampleCount: 1, minTranscribeSamples: floor)
                == .failWithSalvagedAudio,
            "one sample is still audio"
        )
        try expect(
            RecordingSalvage.outcome(sampleCount: 4_000, minTranscribeSamples: floor)
                == .failWithSalvagedAudio,
            "the 250 ms a bail used to throw away is salvaged, not discarded"
        )
        try expect(
            RecordingSalvage.outcome(sampleCount: floor - 1, minTranscribeSamples: floor)
                == .failWithSalvagedAudio,
            "just under the floor still keeps its audio"
        )
        try expect(
            RecordingSalvage.outcome(sampleCount: floor, minTranscribeSamples: floor) == .transcribe,
            "the floor itself transcribes"
        )
        try expect(
            RecordingSalvage.outcome(sampleCount: 190_000, minTranscribeSamples: floor) == .transcribe,
            "a twelve-second take interrupted at the end is transcribed, not failed"
        )
    }
}
