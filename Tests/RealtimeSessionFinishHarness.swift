import Foundation

struct RealtimeSessionFinishHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RealtimeSessionFinishHarnessFailure(description: message)
    }
}

private let rate = 16_000

/// ElevenLabs tracker with the engine's one-second commit lag.
private func elevenLabs() -> ElevenLabsRealtimeFinishTracker {
    ElevenLabsRealtimeFinishTracker(commitLagSamples: rate)
}

private func tone(seconds: Double, amplitude: Float) -> [Float] {
    (0..<Int(seconds * Double(rate))).map { amplitude * sin(2 * .pi * 440 * Float($0) / Float(rate)) }
}

/// Scripted server event sequences for both realtime engines' finish
/// bookkeeping, plus the policy that turns a degraded session into a re-send or
/// a thrown error instead of half a transcript.
@main
struct RealtimeSessionFinishHarness {
    static func main() throws {
        try policyDeliversOnlyCleanSessions()
        try refusalsNeverResend()
        try refusalsMapFromProviderEvents()
        try failureErrorsReachTheFailureCard()
        try policyFailureReasonNamesProviderAndCause()
        try capsScaleAndStayUnderTheWatchdog()
        try deadlineArithmetic()
        try speechEnergyCheck()

        try transcriptsFollowCommitOrder()
        try transcriptsKeepDeltasPerItem()

        try openAIQuietFinishNeedsNoCommit()
        try openAIWaitsForCommittedButUntranscribedTail()
        try openAICommitsSpeechTheVADIsStillInside()
        try openAILateSpeechGetsAFollowUpCommit()
        try openAIManualCommitAlwaysCommits()
        try openAIEmptyCommitIsAnAnswer()
        try openAIBulkFinishDrainsEveryTranscript()
        try openAIDropMidTakeDegrades()
        try openAICloseAfterSettledFinishIsBenign()
        try openAIFailedUtteranceDegrades()
        try openAIFirstReasonWins()
        try openAITimeoutDegrades()

        try elevenLabsSkipsFlushWithNothingUncommitted()
        try elevenLabsFlushesSpeechAfterTheLastCommit()
        try elevenLabsCommitAnswersFlushAfterASettle()
        try elevenLabsEarlyVADCommitDoesNotAnswerFlush()
        try elevenLabsQuietEndsAnUnansweredFlush()
        try elevenLabsEmptyFlushRepliesStillHelp()
        try elevenLabsBufferedWaitsToHearBack()
        try elevenLabsDropMidTakeDegrades()
        try elevenLabsCloseAfterFinishIsBenign()
        try elevenLabsServerErrorDegrades()
        try elevenLabsCountsTranscriptEvents()
        print("Realtime session finish harness passed")
    }

    // MARK: - Policy

    private static func policyDeliversOnlyCleanSessions() throws {
        typealias Policy = RealtimeFinishPolicy
        try expect(Policy.action(for: nil, session: .live, hasRetainedTake: true) == .deliver,
                   "a clean live session delivers its text")
        try expect(Policy.action(for: nil, session: .buffered, hasRetainedTake: false) == .deliver,
                   "a clean buffered session delivers its text")
        try expect(Policy.action(for: .connectionLost, session: .live, hasRetainedTake: true) == .rerunBuffered,
                   "a degraded live session re-sends the retained take")
        try expect(Policy.action(for: .finishTimedOut, session: .live, hasRetainedTake: false) == .fail(.finishTimedOut),
                   "a degraded live session with nothing retained fails instead of returning partial text")
        try expect(Policy.action(for: .sendFailed("x"), session: .buffered, hasRetainedTake: false) == .fail(.sendFailed("x")),
                   "a degraded buffered session fails outright — no second re-run")
        try expect(Policy.action(for: .serverError("x"), session: .buffered, hasRetainedTake: true) == .fail(.serverError("x")),
                   "a buffered session never re-runs itself, even with audio at hand")
    }

    private static func refusalsNeverResend() throws {
        for refusal in [RealtimeRefusal.unauthorized, .quotaExceeded, .rateLimited, .termsNotAccepted, .sessionLimit, .overloaded] {
            let degradation = RealtimeDegradation.refused(refusal, "no")
            try expect(!degradation.allowsResend, "\(refusal) rules out a re-send")
            try expect(RealtimeFinishPolicy.action(for: degradation, session: .live, hasRetainedTake: true) == .fail(degradation),
                       "\(refusal) goes straight to the failure path")
        }
        try expect(RealtimeDegradation.connectionLost.allowsResend && RealtimeDegradation.finishTimedOut.allowsResend,
                   "a drop or a timeout can do better on a second try")
    }

    private static func refusalsMapFromProviderEvents() throws {
        try expect(RealtimeRefusal.elevenLabs(messageType: "auth_error") == .unauthorized, "ElevenLabs auth_error")
        try expect(RealtimeRefusal.elevenLabs(messageType: "quota_exceeded") == .quotaExceeded, "ElevenLabs quota")
        try expect(RealtimeRefusal.elevenLabs(messageType: "unaccepted_terms") == .termsNotAccepted, "ElevenLabs terms")
        try expect(RealtimeRefusal.elevenLabs(messageType: "session_time_limit_exceeded") == .sessionLimit, "ElevenLabs session limit")
        try expect(RealtimeRefusal.elevenLabs(messageType: "queue_overflow") == .overloaded, "ElevenLabs queue overflow")
        try expect(RealtimeRefusal.elevenLabs(messageType: "transcriber_error") == nil,
                   "a transcriber hiccup is worth a re-send")
        try expect(RealtimeRefusal.openAI(type: "invalid_request_error", code: "invalid_api_key") == .unauthorized, "OpenAI bad key")
        try expect(RealtimeRefusal.openAI(type: nil, code: "insufficient_quota") == .quotaExceeded, "OpenAI quota")
        try expect(RealtimeRefusal.openAI(type: "rate_limit_error", code: nil) == .rateLimited, "OpenAI rate limit")
        try expect(RealtimeRefusal.openAI(type: "invalid_request_error", code: "session_expired") == .sessionLimit, "OpenAI session limit")
        try expect(RealtimeRefusal.openAI(type: "server_error", code: nil) == nil, "a server error is worth a re-send")
        try expect(RealtimeRefusal.handshake(status: 401) == .unauthorized && RealtimeRefusal.handshake(status: 429) == .rateLimited,
                   "a refused handshake says why by its status")
        try expect(RealtimeRefusal.handshake(status: 502) == nil, "a gateway error isn't a refusal")
    }

    private static func failureErrorsReachTheFailureCard() throws {
        let key = RealtimeFinishPolicy.failureError(provider: "ElevenLabs", .refused(.unauthorized, "bad key"), transport: nil)
        try expect(TranscriptionFailure.classify(key) == .unauthorized, "a refused key sends the user to fix it, no Retry")
        let limit = RealtimeFinishPolicy.failureError(provider: "OpenAI", .refused(.rateLimited, "slow down"), transport: nil)
        try expect(TranscriptionFailure.classify(limit) == .rateLimited(retryAfter: nil), "a rate limit reads as one")
        let quota = RealtimeFinishPolicy.failureError(provider: "OpenAI", .refused(.quotaExceeded, "no credits"), transport: nil)
        try expect(TranscriptionFailure.classify(quota) == .other, "an empty quota keeps the provider's own message")
        let offline = RealtimeFinishPolicy.failureError(provider: "OpenAI", .connectionLost, transport: .notConnectedToInternet)
        try expect(TranscriptionFailure.classify(offline) == .offline, "a drop with no network reads as offline")
        let plain = RealtimeFinishPolicy.failureError(provider: "OpenAI", .finishTimedOut, transport: nil)
        try expect(plain is TranscriptionEngineError, "anything else stays an engine error")
        try expect(plain.localizedDescription.hasPrefix("Transcription failed: OpenAI didn't return the complete transcript"),
                   "and reads as before: \(plain.localizedDescription)")
    }

    private static func policyFailureReasonNamesProviderAndCause() throws {
        let reason = RealtimeFinishPolicy.failureReason(provider: "ElevenLabs", .connectionLost)
        try expect(reason == "ElevenLabs didn't return the complete transcript (the connection dropped).",
                   "failure reason reads as one sentence: \(reason)")
        let send = RealtimeFinishPolicy.failureReason(provider: "OpenAI", .sendFailed("offline"))
        try expect(send.contains("OpenAI") && send.contains("offline"), "send failure keeps its cause: \(send)")
        let refused = RealtimeFinishPolicy.failureReason(provider: "ElevenLabs", .refused(.quotaExceeded, "out of credits"))
        try expect(refused == "ElevenLabs refused the session (quota exceeded: out of credits).", "refusal reads as one: \(refused)")
    }

    private static func capsScaleAndStayUnderTheWatchdog() throws {
        typealias Policy = RealtimeFinishPolicy
        try expect(Policy.bufferedFinishCapMs(sampleCount: 0, sampleRate: 16_000) == Policy.baseBufferedFinishCapMs,
                   "an empty take gets the base cap")
        try expect(Policy.bufferedFinishCapMs(sampleCount: 16_000 * 60, sampleRate: 16_000) == Policy.baseBufferedFinishCapMs + 30_000,
                   "a minute of audio adds half a minute of wait")
        try expect(Policy.liveFinishCapMs(owedSampleCount: 0, sampleRate: 16_000) == Policy.baseLiveFinishCapMs,
                   "nothing owed since the last commit: the base live window")
        try expect(Policy.liveFinishCapMs(owedSampleCount: 16_000 * 20, sampleRate: 16_000) == Policy.baseLiveFinishCapMs + 10_000,
                   "a 20 s uncommitted tail gets 10 s more")
        let twentyMinutes = Policy.bufferedFinishCapMs(sampleCount: 16_000 * 1_200, sampleRate: 16_000)
        try expect(twentyMinutes == Policy.maxFinishCapMs, "a 20-minute take hits the ceiling: \(twentyMinutes)")
        try expect(Policy.maxFinishCapMs + Policy.maxFinishCapMs + Policy.resendBudgetMs < 600_000,
                   "a live wait plus a re-send stays under the 600 s transcription watchdog")
        try expect(Policy.bufferedFinishCapMs(sampleCount: 1_000, sampleRate: 0) == Policy.baseBufferedFinishCapMs,
                   "a zero sample rate can't divide by zero")
    }

    private static func deadlineArithmetic() throws {
        let now = ContinuousClock.now
        try expect(RealtimeFinishPolicy.milliseconds(until: now + .milliseconds(1_500), now: now) == 1_500, "time left")
        try expect(RealtimeFinishPolicy.milliseconds(until: now - .seconds(2), now: now) == 0, "a passed deadline leaves nothing")
    }

    private static func speechEnergyCheck() throws {
        let silence = [Float](repeating: 0, count: rate)
        try expect(!RealtimeFinishPolicy.hasSpeechEnergy(silence, sampleRate: rate, thresholdDBFS: -45), "silence")
        try expect(!RealtimeFinishPolicy.hasSpeechEnergy(tone(seconds: 0.064, amplitude: 0.001), sampleRate: rate, thresholdDBFS: -45),
                   "a -63 dBFS hum stays under the threshold")
        try expect(RealtimeFinishPolicy.hasSpeechEnergy(tone(seconds: 0.064, amplitude: 0.2), sampleRate: rate, thresholdDBFS: -45),
                   "a voice-level chunk counts")
        try expect(!RealtimeFinishPolicy.hasSpeechEnergy([], sampleRate: rate, thresholdDBFS: -45), "no audio")
    }

    // MARK: - OpenAI transcript order

    private static func transcriptsFollowCommitOrder() throws {
        var order = RealtimeTranscriptOrder()
        order.committed(itemID: "a", previousItemID: nil)
        order.committed(itemID: "b", previousItemID: "a")
        order.committed(itemID: "c", previousItemID: "b")
        order.completed(itemID: "c", transcript: "third.")
        order.completed(itemID: "a", transcript: "First,")
        order.completed(itemID: "b", transcript: "second,")
        try expect(order.text == "First, second, third.",
                   "completions out of order still read in commit order: \(order.text)")

        var inserted = RealtimeTranscriptOrder()
        inserted.committed(itemID: "a", previousItemID: nil)
        inserted.committed(itemID: "c", previousItemID: "b")
        inserted.committed(itemID: "b", previousItemID: "a")
        inserted.completed(itemID: "a", transcript: "one")
        inserted.completed(itemID: "b", transcript: "two")
        inserted.completed(itemID: "c", transcript: "three")
        try expect(inserted.itemIDs == ["a", "b", "c"], "previous_item_id places a late commit: \(inserted.itemIDs)")

        var failed = RealtimeTranscriptOrder()
        failed.committed(itemID: "a", previousItemID: nil)
        failed.committed(itemID: "b", previousItemID: "a")
        failed.failed(itemID: "a")
        failed.completed(itemID: "b", transcript: "kept")
        failed.completed(itemID: "stray", transcript: "late")
        try expect(failed.text == "kept late", "a failed item leaves no text; an unknown one goes last: \(failed.text)")
    }

    private static func transcriptsKeepDeltasPerItem() throws {
        var order = RealtimeTranscriptOrder()
        order.committed(itemID: "a", previousItemID: nil)
        order.committed(itemID: "b", previousItemID: "a")
        order.delta(itemID: "b", "wor")
        order.delta(itemID: "a", "hel")
        order.delta(itemID: "b", "ld")
        order.delta(itemID: "a", "lo")
        try expect(order.text == "hello world", "interleaved deltas stay with their items: \(order.text)")
        try expect(order.hasPartial, "partials are showing")
        order.completed(itemID: "a", transcript: "Hello")
        order.completed(itemID: "b", transcript: "world.")
        try expect(order.text == "Hello world." && !order.hasPartial, "finals replace partials")
        order.delta(itemID: "a", " stray")
        try expect(order.text == "Hello world.", "a delta after the final changes nothing")
    }

    // MARK: - OpenAI finish

    private static func openAIQuietFinishNeedsNoCommit() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.transcriptCompleted()
        t.beginFinish()
        try expect(!t.needsFinishCommit(manualCommit: false, hasPartial: false),
                   "everything committed and transcribed: no trailing commit (it would only commit silence)")
        try expect(t.isSettled && t.degradation == nil, "nothing owed, nothing lost")
        try expect(!t.needsFollowUpCommit, "and no follow-up either")
    }

    // The bug: a trailing utterance committed by the VAD but not yet
    // transcribed used to be skipped because no delta had arrived.
    private static func openAIWaitsForCommittedButUntranscribedTail() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.beginFinish()
        try expect(!t.needsFinishCommit(manualCommit: false, hasPartial: false),
                   "an already-committed tail needs no second commit")
        try expect(!t.isSettled, "a committed-but-untranscribed tail keeps the finish waiting")
        t.transcriptCompleted()
        try expect(t.isSettled && t.degradation == nil, "the tail's transcript settles the finish")
    }

    private static func openAICommitsSpeechTheVADIsStillInside() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.beginFinish()
        try expect(t.needsFinishCommit(manualCommit: false, hasPartial: false),
                   "speech the VAD hasn't committed needs the finishing commit")
        t.finishCommitSent()
        try expect(!t.isSettled, "waits for the commit's reply")
        t.bufferCommitted()
        try expect(!t.isSettled, "then for the committed buffer's transcript")
        try expect(t.pendingTranscripts == 1, "one transcript owed")
        t.transcriptCompleted()
        try expect(t.isSettled && t.degradation == nil, "settles once it arrives")
    }

    // Reviewer probe: `speech_started` for the last audio sent lands after the
    // finish decided no commit was needed. It used to stall out the window and
    // re-send the whole take.
    private static func openAILateSpeechGetsAFollowUpCommit() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.transcriptCompleted()
        t.beginFinish()
        try expect(!t.needsFinishCommit(manualCommit: false, hasPartial: false), "no commit at the decision")
        t.speechStarted()
        try expect(!t.isSettled && t.needsFollowUpCommit, "late speech asks for a follow-up commit")
        t.finishCommitSent()
        try expect(!t.needsFollowUpCommit, "only one at a time")
        t.bufferCommitted()
        t.transcriptCompleted()
        try expect(t.isSettled && t.degradation == nil, "and settles without a re-send")
    }

    private static func openAIManualCommitAlwaysCommits() throws {
        let t = OpenAIRealtimeFinishTracker()
        try expect(t.needsFinishCommit(manualCommit: true, hasPartial: false),
                   "a manual-commit model always commits at finish")
        try expect(t.needsFinishCommit(manualCommit: false, hasPartial: true),
                   "a partial on screen still gets its commit")
    }

    private static func openAIEmptyCommitIsAnAnswer() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.beginFinish()
        t.finishCommitSent()
        t.commitFoundEmptyBuffer()
        try expect(t.isSettled && t.degradation == nil,
                   "input_audio_buffer_commit_empty answers the commit without degrading the take")
    }

    private static func openAIBulkFinishDrainsEveryTranscript() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.beginFinish()
        t.finishCommitSent()
        for _ in 0..<3 {
            t.speechStarted()
            t.bufferCommitted()
        }
        t.transcriptCompleted()
        t.transcriptCompleted()
        try expect(!t.isSettled, "a buffered session waits for every transcript, not the first")
        t.transcriptCompleted()
        try expect(t.isSettled && t.degradation == nil, "settles when the last one lands")
    }

    private static func openAIDropMidTakeDegrades() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.transcriptCompleted()
        t.connectionClosed(transport: .networkConnectionLost)
        try expect(t.degradation == .connectionLost,
                   "a close mid-take loses whatever was said after it, even with nothing pending")
        try expect(t.transport == .networkConnectionLost, "and keeps the network error for the failure card")
        try expect(t.isSettled, "and there is nothing left to wait for")
        try expect(RealtimeFinishPolicy.action(for: t.degradation, session: .live, hasRetainedTake: true) == .rerunBuffered,
                   "the live take is re-sent")
    }

    private static func openAICloseAfterSettledFinishIsBenign() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.transcriptCompleted()
        t.beginFinish()
        t.connectionClosed()
        try expect(t.degradation == nil, "a close once nothing is owed costs nothing")

        var owed = OpenAIRealtimeFinishTracker()
        owed.speechStarted()
        owed.bufferCommitted()
        owed.beginFinish()
        owed.connectionClosed()
        try expect(owed.degradation == .connectionLost, "a close while a transcript is owed degrades")
    }

    private static func openAIFailedUtteranceDegrades() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.transcriptFailed("audio too noisy")
        try expect(t.pendingTranscripts == 0, "a failed transcript is no longer owed")
        try expect(t.degradation == .serverError("audio too noisy"), "but its text is gone")
    }

    private static func openAIFirstReasonWins() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.sendFailed("socket not connected", transport: .notConnectedToInternet)
        t.refused(.unauthorized, "late")
        t.connectionClosed(transport: .timedOut)
        t.finishWindowExpired()
        try expect(t.degradation == .sendFailed("socket not connected"), "the first cause is the one reported")
        try expect(t.transport == .notConnectedToInternet, "and the first network error")
    }

    private static func openAITimeoutDegrades() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.beginFinish()
        t.finishWindowExpired()
        try expect(t.degradation == .finishTimedOut, "an expired finish window with a transcript owed degrades")
        try expect(RealtimeFinishPolicy.action(for: t.degradation, session: .buffered, hasRetainedTake: false)
                   == .fail(.finishTimedOut), "and a buffered session throws")
    }

    // MARK: - ElevenLabs

    private static func elevenLabsSkipsFlushWithNothingUncommitted() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate * 3, hasSpeechEnergy: true)
        t.partialTranscript("hello there")
        // The VAD's commit lands after two more seconds of silence went up.
        t.audioSent(sampleCount: rate * 2, hasSpeechEnergy: false)
        t.committedTranscript()
        t.audioSent(sampleCount: rate, hasSpeechEnergy: false)
        t.beginFinish()
        try expect(!t.needsFlush, "a silent tail after the last commit needs no flush")
        try expect(t.isDone(quietMs: 0, buffered: false), "so the finish is done at once — no undocumented reply needed")
    }

    private static func elevenLabsFlushesSpeechAfterTheLastCommit() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate * 3, hasSpeechEnergy: true)
        t.audioSent(sampleCount: rate * 2, hasSpeechEnergy: false)
        t.committedTranscript()
        t.audioSent(sampleCount: rate / 2, hasSpeechEnergy: true)
        t.beginFinish()
        try expect(t.needsFlush, "speech sent after the last commit needs the flush, partial or not")

        var justBefore = elevenLabs()
        justBefore.audioSent(sampleCount: rate * 3, hasSpeechEnergy: true)
        justBefore.audioSent(sampleCount: rate / 2, hasSpeechEnergy: true)
        justBefore.committedTranscript()
        try expect(justBefore.needsFlush,
                   "speech in the last second before a commit landed isn't taken as covered by it")

        var showing = elevenLabs()
        showing.audioSent(sampleCount: rate, hasSpeechEnergy: false)
        showing.partialTranscript("and")
        try expect(showing.needsFlush, "a partial on screen always needs the flush")
        try expect(!elevenLabs().needsFlush, "a take with nothing sent needs none")
    }

    private static func elevenLabsCommitAnswersFlushAfterASettle() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate, hasSpeechEnergy: true)
        t.partialTranscript("hello wor")
        t.beginFinish()
        t.flushCommitSent()
        try expect(!t.isDone(quietMs: 5_000, buffered: false), "a partial showing is still owed its commit")
        t.committedTranscript()
        try expect(!t.isDone(quietMs: 0, buffered: false), "a commit right after the flush may be the VAD's, so settle first")
        try expect(t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.answerSettleMs, buffered: false),
                   "then it answers the flush")
        try expect(t.degradation == nil, "with nothing lost")
    }

    // Reviewer probe: the VAD's commit for an earlier segment lands after the
    // flush, while the flush's own segment is still showing as a partial.
    private static func elevenLabsEarlyVADCommitDoesNotAnswerFlush() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate * 2, hasSpeechEnergy: true)
        t.partialTranscript("first sentence")
        t.beginFinish()
        t.flushCommitSent()
        t.committedTranscript()
        t.partialTranscript("thanks")
        try expect(!t.isDone(quietMs: 10_000, buffered: false), "a newer partial keeps the finish waiting")
        t.committedTranscript()
        try expect(t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.answerSettleMs, buffered: false),
                   "until its own commit lands")
    }

    private static func elevenLabsQuietEndsAnUnansweredFlush() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate, hasSpeechEnergy: true)
        t.beginFinish()
        t.flushCommitSent()
        try expect(!t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.liveQuietMs - 1, buffered: false),
                   "an unanswered flush waits a moment for its speech to show up")
        try expect(t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.liveQuietMs, buffered: false),
                   "then, with no partial showing, the quiet stream is the answer")
        try expect(t.degradation == nil, "nothing lost")
    }

    private static func elevenLabsEmptyFlushRepliesStillHelp() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate, hasSpeechEnergy: true)
        t.beginFinish()
        t.flushCommitSent()
        t.nothingToCommit()
        try expect(t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.answerSettleMs, buffered: false),
                   "insufficient_audio_activity, when it comes, ends the wait early")

        var before = elevenLabs()
        before.nothingToCommit()
        try expect(!before.flushAnswered && before.degradation == nil,
                   "before a flush it says nothing about lost audio")
    }

    private static func elevenLabsBufferedWaitsToHearBack() throws {
        var t = elevenLabs()
        t.audioSent(sampleCount: rate * 60, hasSpeechEnergy: true)
        t.beginFinish()
        try expect(t.needsFlush, "a buffered take with speech is flushed")
        t.flushCommitSent()
        try expect(!t.isDone(quietMs: 10_000, buffered: true), "silence before the first segment isn't the end")
        t.partialTranscript("one")
        t.committedTranscript()
        try expect(!t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.bufferedQuietMs - 1, buffered: true),
                   "segments arrive in a burst, so the first commit isn't the end either")
        try expect(t.isDone(quietMs: ElevenLabsRealtimeFinishTracker.bufferedQuietMs, buffered: true),
                   "the burst going quiet is")

        var silent = elevenLabs()
        silent.audioSent(sampleCount: rate * 10, hasSpeechEnergy: false)
        silent.beginFinish()
        try expect(!silent.needsFlush && silent.isDone(quietMs: 0, buffered: true),
                   "a buffered take with no speech energy finishes at once, empty")
    }

    private static func elevenLabsDropMidTakeDegrades() throws {
        var t = elevenLabs()
        t.partialTranscript("hello")
        t.connectionClosed(transport: .notConnectedToInternet)
        try expect(t.degradation == .connectionLost, "a drop before the finish degrades")
        try expect(t.transport == .notConnectedToInternet, "keeping the network error")
        try expect(t.isDone(quietMs: 0, buffered: false), "and ends the wait")
    }

    private static func elevenLabsCloseAfterFinishIsBenign() throws {
        var answered = elevenLabs()
        answered.beginFinish()
        answered.flushCommitSent()
        answered.committedTranscript()
        answered.connectionClosed()
        try expect(answered.degradation == nil, "a close after the flush was answered costs nothing")

        var noFlush = elevenLabs()
        noFlush.beginFinish()
        noFlush.connectionClosed()
        try expect(noFlush.degradation == nil, "a close when nothing was owed costs nothing")

        var owed = elevenLabs()
        owed.audioSent(sampleCount: rate, hasSpeechEnergy: true)
        owed.beginFinish()
        owed.flushCommitSent()
        owed.connectionClosed()
        try expect(owed.degradation == .connectionLost, "a close before the answer degrades")
    }

    private static func elevenLabsServerErrorDegrades() throws {
        var t = elevenLabs()
        t.serverError("transcriber_error: hiccup")
        try expect(t.degradation == .serverError("transcriber_error: hiccup"), "a server error degrades")
        t.sendFailed("later")
        try expect(t.degradation == .serverError("transcriber_error: hiccup"), "first reason wins")

        var refused = elevenLabs()
        refused.refused(.quotaExceeded, "out of credits")
        try expect(refused.degradation == .refused(.quotaExceeded, "out of credits"), "a refusal is recorded as one")
    }

    private static func elevenLabsCountsTranscriptEvents() throws {
        var t = elevenLabs()
        t.partialTranscript("a")
        t.partialTranscript("a b")
        t.committedTranscript()
        t.nothingToCommit()
        try expect(t.transcriptEvents == 3,
                   "partials and commits move the quiet clock; commit replies with no text don't")
    }
}
