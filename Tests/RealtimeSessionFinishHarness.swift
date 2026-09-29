import Foundation

struct RealtimeSessionFinishHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw RealtimeSessionFinishHarnessFailure(description: message)
    }
}

/// Scripted server event sequences for both realtime engines' finish
/// bookkeeping, plus the policy that turns a degraded session into a re-send or
/// a thrown error instead of half a transcript.
@main
struct RealtimeSessionFinishHarness {
    static func main() throws {
        try policyDeliversOnlyCleanSessions()
        try policyFailureReasonNamesProviderAndCause()
        try bufferedCapScalesWithTheTake()

        try openAIQuietFinishNeedsNoCommit()
        try openAIWaitsForCommittedButUntranscribedTail()
        try openAICommitsSpeechTheVADIsStillInside()
        try openAIManualCommitAlwaysCommits()
        try openAIEmptyCommitIsAnAnswer()
        try openAIBulkFinishDrainsEveryTranscript()
        try openAIDropMidTakeDegrades()
        try openAICloseAfterSettledFinishIsBenign()
        try openAIFailedUtteranceDegrades()
        try openAIFirstReasonWins()
        try openAITimeoutDegrades()

        try elevenLabsCommitAnswersFlush()
        try elevenLabsEmptyFlushAnswersWhenNothingShowing()
        try elevenLabsEmptyFlushWithPartialStillOwesCommit()
        try elevenLabsNothingToCommitBeforeFlushIsIgnored()
        try elevenLabsDropMidTakeDegrades()
        try elevenLabsCloseAfterAnsweredFlushIsBenign()
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

    private static func policyFailureReasonNamesProviderAndCause() throws {
        let reason = RealtimeFinishPolicy.failureReason(provider: "ElevenLabs", .connectionLost)
        try expect(reason == "ElevenLabs didn't return the complete transcript (the connection dropped).",
                   "failure reason reads as one sentence: \(reason)")
        let send = RealtimeFinishPolicy.failureReason(provider: "OpenAI", .sendFailed("offline"))
        try expect(send.contains("OpenAI") && send.contains("offline"), "send failure keeps its cause: \(send)")
    }

    private static func bufferedCapScalesWithTheTake() throws {
        let base = RealtimeFinishPolicy.baseBufferedFinishCapMs
        try expect(RealtimeFinishPolicy.bufferedFinishCapMs(sampleCount: 0, sampleRate: 16_000) == base,
                   "an empty take gets the base cap")
        try expect(RealtimeFinishPolicy.bufferedFinishCapMs(sampleCount: 16_000 * 60, sampleRate: 16_000) == base + 30_000,
                   "a minute of audio adds half a minute of wait")
        try expect(RealtimeFinishPolicy.bufferedFinishCapMs(sampleCount: 16_000 * 600, sampleRate: 16_000)
                   > RealtimeFinishPolicy.bufferedFinishCapMs(sampleCount: 16_000 * 60, sampleRate: 16_000),
                   "a longer take waits longer")
        try expect(RealtimeFinishPolicy.bufferedFinishCapMs(sampleCount: 1_000, sampleRate: 0) == base,
                   "a zero sample rate can't divide by zero")
    }

    // MARK: - OpenAI

    private static func openAIQuietFinishNeedsNoCommit() throws {
        var t = OpenAIRealtimeFinishTracker()
        t.speechStarted()
        t.bufferCommitted()
        t.transcriptCompleted()
        t.beginFinish()
        try expect(!t.needsFinishCommit(manualCommit: false, hasPartial: false),
                   "everything committed and transcribed: no trailing commit (it would only commit silence)")
        try expect(t.isSettled && t.degradation == nil, "nothing owed, nothing lost")
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
        t.connectionClosed()
        try expect(t.degradation == .connectionLost,
                   "a close mid-take loses whatever was said after it, even with nothing pending")
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
        t.sendFailed("socket not connected")
        t.connectionClosed()
        t.finishWindowExpired()
        try expect(t.degradation == .sendFailed("socket not connected"), "the first cause is the one reported")
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

    private static func elevenLabsCommitAnswersFlush() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.partialTranscript("hello wor")
        t.flushCommitSent()
        try expect(!t.isSettled, "the flush is owed an answer")
        t.committedTranscript()
        try expect(t.isSettled && t.degradation == nil, "the committed tail answers it")
    }

    private static func elevenLabsEmptyFlushAnswersWhenNothingShowing() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.partialTranscript("hello")
        t.committedTranscript()
        t.flushCommitSent()
        t.nothingToCommit()
        try expect(t.isSettled && t.degradation == nil,
                   "insufficient_audio_activity with no partial showing means nothing is owed — no 2 s wait, no re-send")
    }

    private static func elevenLabsEmptyFlushWithPartialStillOwesCommit() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.partialTranscript("and one more thing")
        t.flushCommitSent()
        t.nothingToCommit()
        try expect(!t.isSettled, "a partial on screen means the VAD's commit for it is still owed")
        t.committedTranscript()
        try expect(t.isSettled && t.degradation == nil, "which settles it when it lands")

        var lost = ElevenLabsRealtimeFinishTracker()
        lost.partialTranscript("and one more thing")
        lost.flushCommitSent()
        lost.nothingToCommit()
        lost.finishWindowExpired()
        try expect(lost.degradation == .finishTimedOut, "and degrades if it never does")
    }

    private static func elevenLabsNothingToCommitBeforeFlushIsIgnored() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.nothingToCommit()
        try expect(!t.flushAnswered && t.degradation == nil,
                   "the app never commits mid-take, so these events say nothing about lost audio")
    }

    private static func elevenLabsDropMidTakeDegrades() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.partialTranscript("hello")
        t.connectionClosed()
        try expect(t.degradation == .connectionLost, "a drop before the flush degrades")
        try expect(t.isSettled, "and ends the wait")
    }

    private static func elevenLabsCloseAfterAnsweredFlushIsBenign() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.flushCommitSent()
        t.committedTranscript()
        t.connectionClosed()
        try expect(t.degradation == nil, "a close after the flush was answered costs nothing")

        var owed = ElevenLabsRealtimeFinishTracker()
        owed.partialTranscript("hi")
        owed.flushCommitSent()
        owed.connectionClosed()
        try expect(owed.degradation == .connectionLost, "a close before the answer degrades")
    }

    private static func elevenLabsServerErrorDegrades() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.serverError("quota_exceeded: out of credits")
        try expect(t.degradation == .serverError("quota_exceeded: out of credits"), "a server error degrades")
        t.sendFailed("later")
        try expect(t.degradation == .serverError("quota_exceeded: out of credits"), "first reason wins")
    }

    private static func elevenLabsCountsTranscriptEvents() throws {
        var t = ElevenLabsRealtimeFinishTracker()
        t.partialTranscript("a")
        t.partialTranscript("a b")
        t.committedTranscript()
        t.nothingToCommit()
        try expect(t.transcriptEvents == 3,
                   "partials and commits move the quiet clock; commit replies with no text don't")
    }
}
