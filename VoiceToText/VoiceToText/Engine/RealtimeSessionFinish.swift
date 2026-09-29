import Foundation

/// Why a realtime session's transcript can't be trusted to cover the whole
/// take. Any of these means text may be missing, and a streaming engine used to
/// return what it had anyway — pasted straight into the user's document when
/// review is off, with nothing to say it stopped short.
nonisolated enum RealtimeDegradation: Equatable, Sendable {
    /// Audio, or the commit that flushes it, never reached the server.
    case sendFailed(String)
    /// The socket closed while the server still owed us text.
    case connectionLost
    /// The server reported an error that costs audio or text.
    case serverError(String)
    /// The finish window ran out with text still owed.
    case finishTimedOut

    /// Reads as the tail of "… didn't return the complete transcript (…)".
    var summary: String {
        switch self {
        case .sendFailed(let reason): return "audio couldn't be sent: \(reason)"
        case .connectionLost: return "the connection dropped"
        case .serverError(let message): return "server error: \(message)"
        case .finishTimedOut: return "the final text didn't arrive in time"
        }
    }
}

/// What a realtime engine does with a finished session. Pure so the harness can
/// pin the rule without a socket.
nonisolated enum RealtimeFinishPolicy {
    enum Session: Equatable, Sendable {
        /// Opened by the dictation controller; audio streamed in as captured.
        case live
        /// The engine's own one-shot `transcribe(samples:)`.
        case buffered
    }

    enum Action: Equatable, Sendable {
        /// The transcript covers the take.
        case deliver
        /// Re-send the retained take through the buffered path and return that.
        case rerunBuffered
        /// Throw, so the caller's failure path keeps the audio and offers Retry.
        case fail(RealtimeDegradation)
    }

    /// A degraded live session gets one buffered re-run of the whole take. A
    /// degraded buffered session fails outright: its input already is the whole
    /// take, so there is nothing better to fall back to — and quietly handing
    /// back part of it is exactly what this policy exists to stop.
    static func action(
        for degradation: RealtimeDegradation?,
        session: Session,
        hasRetainedTake: Bool
    ) -> Action {
        guard let degradation else { return .deliver }
        if session == .live, hasRetainedTake { return .rerunBuffered }
        return .fail(degradation)
    }

    /// The reason carried by `TranscriptionEngineError.transcriptionFailed`.
    static func failureReason(provider: String, _ degradation: RealtimeDegradation) -> String {
        "\(provider) didn't return the complete transcript (\(degradation.summary))."
    }

    /// Cap on waiting for a buffered session's text. The whole take goes up
    /// faster than realtime and every transcript can still be owed at finish,
    /// so a fixed cap cut long takes short. Only a stalled server ever reaches
    /// it; a healthy one settles well inside.
    static func bufferedFinishCapMs(sampleCount: Int, sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return baseBufferedFinishCapMs }
        let seconds = Double(sampleCount) / sampleRate
        return baseBufferedFinishCapMs + Int(seconds * Double(bufferedFinishMsPerAudioSecond))
    }

    static let baseBufferedFinishCapMs = 15_000
    static let bufferedFinishMsPerAudioSecond = 500
}

/// End-of-session bookkeeping for `OpenAIRealtimeEngine`, fed with the server's
/// events so the harness can script a finish without a socket.
///
/// Transcription only starts at a commit, so what is owed at finish is: every
/// committed buffer whose `completed` hasn't arrived (`pendingTranscripts`),
/// speech the server's VAD has heard but not committed yet, and the reply to
/// the finishing commit itself. The old live path waited only when a delta was
/// already showing, so a trailing utterance that had been committed but not yet
/// transcribed was silently skipped.
nonisolated struct OpenAIRealtimeFinishTracker: Equatable, Sendable {
    /// Committed buffers whose transcript (or failure) hasn't arrived.
    private(set) var pendingTranscripts = 0
    /// The server's VAD reported speech that no commit has covered yet.
    private(set) var uncommittedSpeech = false
    /// The finishing commit was sent and neither `committed` nor
    /// `input_audio_buffer_commit_empty` has answered it.
    private(set) var awaitingCommitReply = false
    private(set) var finishing = false
    private(set) var closed = false
    /// The first reason the transcript can't be trusted; later ones add nothing.
    private(set) var degradation: RealtimeDegradation?

    /// Nothing more is coming, or waiting can no longer help.
    var isSettled: Bool {
        if closed || degradation != nil { return true }
        return !awaitingCommitReply && pendingTranscripts == 0 && !uncommittedSpeech
    }

    /// The live path commits only when something is actually in the buffer:
    /// speech the VAD is still inside, a partial on screen, or a model that
    /// never commits on its own. Committing trailing silence would only invite
    /// a hallucinated line.
    func needsFinishCommit(manualCommit: Bool, hasPartial: Bool) -> Bool {
        manualCommit || uncommittedSpeech || hasPartial
    }

    mutating func speechStarted() { uncommittedSpeech = true }

    /// `input_audio_buffer.committed`, from the VAD or from our own commit.
    /// Either answers the finishing commit: the socket is ordered, so a later
    /// `committed` can only cover audio we already sent.
    mutating func bufferCommitted() {
        pendingTranscripts += 1
        uncommittedSpeech = false
        awaitingCommitReply = false
    }

    mutating func transcriptCompleted() {
        pendingTranscripts = max(0, pendingTranscripts - 1)
    }

    /// `…input_audio_transcription.failed`: that utterance's text is gone.
    mutating func transcriptFailed(_ message: String) {
        pendingTranscripts = max(0, pendingTranscripts - 1)
        degrade(.serverError(message))
    }

    /// `input_audio_buffer_commit_empty`: the finishing commit found nothing
    /// left to transcribe — an answer, not a failure.
    mutating func commitFoundEmptyBuffer() {
        awaitingCommitReply = false
    }

    mutating func serverError(_ message: String) { degrade(.serverError(message)) }

    mutating func sendFailed(_ reason: String) { degrade(.sendFailed(reason)) }

    mutating func beginFinish() { finishing = true }

    mutating func finishCommitSent() { awaitingCommitReply = true }

    /// A close mid-take loses whatever was said after it; during the finish it
    /// only matters while text is still owed.
    mutating func connectionClosed() {
        let owed = !finishing || !isSettled
        closed = true
        if owed { degrade(.connectionLost) }
    }

    /// The engine's finish wait ran out before the session was done.
    mutating func finishWindowExpired() { degrade(.finishTimedOut) }

    private mutating func degrade(_ reason: RealtimeDegradation) {
        if degradation == nil { degradation = reason }
    }
}

/// End-of-session bookkeeping for `ElevenLabsRealtimeEngine`.
///
/// ElevenLabs sends no acknowledgement of a commit other than the resulting
/// `committed_transcript`, so the finish waits for the flush to be answered:
/// by a committed segment, or — when the flush found nothing left to commit —
/// by `insufficient_audio_activity` / `commit_throttled`. Those two count as
/// an answer only while no partial is on screen; with one showing, a commit
/// for that speech is still owed (the VAD's, landing just ahead of our flush).
nonisolated struct ElevenLabsRealtimeFinishTracker: Equatable, Sendable {
    /// A partial is showing that no committed segment has replaced yet.
    private(set) var hasPartial = false
    private(set) var flushSent = false
    private(set) var flushAnswered = false
    private(set) var closed = false
    private(set) var degradation: RealtimeDegradation?
    /// Bumped on every partial or committed segment. A buffered session keeps
    /// waiting until this stops moving: its audio went up faster than
    /// realtime, so the first commit after the flush is usually an early VAD
    /// segment, not the answer to the flush.
    private(set) var transcriptEvents = 0

    var isSettled: Bool {
        closed || degradation != nil || flushAnswered
    }

    mutating func partialTranscript(_ text: String) {
        hasPartial = !text.isEmpty
        transcriptEvents += 1
    }

    mutating func committedTranscript() {
        hasPartial = false
        transcriptEvents += 1
        if flushSent { flushAnswered = true }
    }

    /// `insufficient_audio_activity` or `commit_throttled`. Before the flush
    /// neither says anything about lost audio — the app never commits then.
    mutating func nothingToCommit() {
        if flushSent, !hasPartial { flushAnswered = true }
    }

    mutating func serverError(_ message: String) { degrade(.serverError(message)) }

    mutating func sendFailed(_ reason: String) { degrade(.sendFailed(reason)) }

    mutating func flushCommitSent() { flushSent = true }

    mutating func connectionClosed() {
        let owed = !flushSent || !isSettled
        closed = true
        if owed { degrade(.connectionLost) }
    }

    /// The engine's finish wait ran out before the session was done.
    mutating func finishWindowExpired() { degrade(.finishTimedOut) }

    private mutating func degrade(_ reason: RealtimeDegradation) {
        if degradation == nil { degradation = reason }
    }
}
