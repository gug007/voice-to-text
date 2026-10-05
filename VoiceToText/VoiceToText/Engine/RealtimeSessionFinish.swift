import Foundation

/// The provider refused the session outright. Sending the same take again
/// would be refused the same way, so none of these gets an automatic re-send.
nonisolated enum RealtimeRefusal: Equatable, Sendable {
    case unauthorized
    /// The account has no credit left. Every model of the same provider bills
    /// the same balance, so only a top-up or a model on this Mac gets past it.
    case quotaExceeded
    /// `retryAfter` is when the provider said to try again, if it said.
    case rateLimited(retryAfter: TimeInterval? = nil)
    case termsNotAccepted
    case sessionLimit
    /// The provider's queue or capacity is full; hammering it again at once
    /// only makes that worse.
    case overloaded
    /// Refused for a reason this app has no name for — an account problem, or
    /// an error before the session was set up that no config change could
    /// answer. The server's own message is all there is to go on.
    case rejected

    var label: String {
        switch self {
        case .unauthorized: return "API key refused"
        case .quotaExceeded: return "quota exceeded"
        case .rateLimited: return "rate limited"
        case .termsNotAccepted: return "terms not accepted"
        case .sessionLimit: return "session time limit reached"
        case .overloaded: return "service overloaded"
        case .rejected: return "rejected"
        }
    }

    /// ElevenLabs names its error events after the problem (`message_type`).
    static func elevenLabs(messageType: String) -> RealtimeRefusal? {
        switch messageType {
        case "auth_error": return .unauthorized
        case "quota_exceeded": return .quotaExceeded
        case "rate_limited": return .rateLimited()
        case "unaccepted_terms": return .termsNotAccepted
        case "session_time_limit_exceeded": return .sessionLimit
        case "queue_overflow", "resource_exhausted": return .overloaded
        default: return nil
        }
    }

    /// OpenAI's `error` event carries a `type`, a machine-readable `code` and
    /// a `message`. The codes are trusted first; the message only decides
    /// between a rate limit and an empty balance, because the realtime socket
    /// doesn't keep the two apart: an empty account has been seen arriving as
    /// `rate_limit_exceeded` with "You exceeded your current quota, please
    /// check your plan and billing details." Calling that a rate limit tells
    /// the user to wait for something waiting never fixes. Only OpenAI's quota
    /// sentence counts — an ordinary rate limit on a low tier ends with a link
    /// to the account's billing page, and that one really is worth waiting out.
    static func openAI(type: String?, code: String?, message: String? = nil) -> RealtimeRefusal? {
        let code = code ?? ""
        let type = type ?? ""
        if code == "invalid_api_key" || type == "authentication_error" { return .unauthorized }
        if quotaCodes.contains(code) || type == "insufficient_quota" || statesQuota(message) {
            return .quotaExceeded
        }
        if code.contains("rate_limit") || type.contains("rate_limit") { return .rateLimited() }
        if code == "session_expired" || code.contains("session_time_limit") { return .sessionLimit }
        return nil
    }

    /// An OpenAI error that arrives before the server has acknowledged our
    /// `session.update`. The server answers a config it dislikes with an
    /// `invalid_request_error`, which the fallback ladder can do something
    /// about. A named refusal or a complaint about the account isn't about the
    /// config, and no reduced one gets past it. Anything else stays on the
    /// ladder, a transient `server_error` included: refusing the take over it
    /// would throw away a session that, once acknowledged, transcribes
    /// normally — and leave nothing to re-send.
    static func openAIBeforeConfig(type: String?, code: String?, message: String?) -> RealtimeRefusal? {
        if let refusal = openAI(type: type, code: code, message: message) { return refusal }
        if mentionsAccount(message) { return .rejected }
        return nil
    }

    /// A WebSocket handshake the server answered with an HTTP error.
    static func handshake(status: Int, retryAfter: TimeInterval? = nil) -> RealtimeRefusal? {
        switch status {
        case 401, 403: return .unauthorized
        case 402: return .quotaExceeded
        case 429: return .rateLimited(retryAfter: retryAfter)
        default: return nil
        }
    }

    /// The same, read off the handshake's response, with its `Retry-After`
    /// honoured the way the batch engines honour it.
    static func handshake(response: HTTPURLResponse, now: Date = Date()) -> RealtimeRefusal? {
        handshake(
            status: response.statusCode,
            retryAfter: CloudTranscriptionError.retryAfter(
                milliseconds: response.value(forHTTPHeaderField: "retry-after-ms"),
                header: response.value(forHTTPHeaderField: "Retry-After"),
                now: now
            )
        )
    }

    /// OpenAI's codes for an account that can't pay for the request.
    static let quotaCodes: Set<String> = ["insufficient_quota", "billing_not_active", "billing_hard_limit_reached"]

    /// OpenAI's own words for an empty balance — specific enough to outrank
    /// a `rate_limit` code.
    static func statesQuota(_ message: String?) -> Bool {
        mentions(message, anyOf: ["exceeded your current quota", "credit balance"])
    }

    static func mentionsBalance(_ message: String?) -> Bool {
        mentions(message, anyOf: ["quota", "credit", "billing details"])
    }

    static func mentionsAccount(_ message: String?) -> Bool {
        mentionsBalance(message) || mentions(message, anyOf: ["account"])
    }

    /// Links don't count: OpenAI's rate-limit text ends with one to
    /// `platform.openai.com/account/billing`, which says nothing about the
    /// account itself.
    private static func mentions(_ message: String?, anyOf words: [String]) -> Bool {
        guard let message else { return false }
        let prose = message.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.contains("://") && !$0.contains(".com/") }
            .joined(separator: " ")
        return words.contains { prose.contains($0) }
    }
}

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
    /// The provider refused the session (see `RealtimeRefusal`).
    case refused(RealtimeRefusal, String)
    /// Every utterance the server took in, it failed to transcribe — with
    /// the message that says the most about why. Nothing came back at all,
    /// which is how an empty balance can look when the socket itself was let
    /// through; a re-send of the whole take would only fail the same way,
    /// and the user needs to hear what might fix it. Only recorded on strong
    /// evidence (see `OpenAIRealtimeFinishTracker.outcome`).
    case nothingTranscribed(String)

    /// Whether re-sending the take could plausibly do better.
    var allowsResend: Bool {
        switch self {
        case .refused, .nothingTranscribed: return false
        case .sendFailed, .connectionLost, .serverError, .finishTimedOut: return true
        }
    }

    var isRefusal: Bool {
        if case .refused = self { return true }
        return false
    }

    /// Reads as the tail of "… didn't return the complete transcript (…)".
    var summary: String {
        switch self {
        case .sendFailed(let reason): return "audio couldn't be sent: \(reason)"
        case .connectionLost: return "the connection dropped"
        case .serverError(let message): return "server error: \(message)"
        case .finishTimedOut: return "the final text didn't arrive in time"
        case .refused(.rejected, let message): return message
        case .refused(let refusal, let message): return "\(refusal.label): \(message)"
        case .nothingTranscribed(let message): return message
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

    /// A degraded live session gets one buffered re-run of the whole take —
    /// unless the provider refused it (a bad key, an empty quota) or
    /// transcribed none of it, which a re-send can only repeat. A degraded
    /// buffered session fails outright: its input already is the whole take,
    /// so there is nothing better to fall back to — and quietly handing back
    /// part of it is exactly what this policy exists to stop.
    static func action(
        for degradation: RealtimeDegradation?,
        session: Session,
        hasRetainedTake: Bool
    ) -> Action {
        guard let degradation else { return .deliver }
        if session == .live, hasRetainedTake, degradation.allowsResend { return .rerunBuffered }
        return .fail(degradation)
    }

    /// Written to follow "Transcription failed: ".
    static func failureReason(provider: String, _ degradation: RealtimeDegradation) -> String {
        switch degradation {
        case .refused:
            return "\(provider) refused the session (\(degradation.summary))."
        case .nothingTranscribed(let message):
            // The top-up advice only when the server's words point at the
            // balance; anything else would send the user after the wrong fix.
            let reason = "\(provider) transcribed none of this take (\(degradation.summary))."
            guard RealtimeRefusal.mentionsBalance(message) else { return reason }
            return reason + " If your \(provider) balance is empty, top up — or use a model on this Mac."
        case .sendFailed, .connectionLost, .serverError, .finishTimedOut:
            return "\(provider) didn't return the complete transcript (\(degradation.summary))."
        }
    }

    /// The error a failed session throws. Where the cause maps onto one the
    /// failure card knows — a refused key, a rate limit, no network — it
    /// arrives as a `CloudTranscriptionError`, so the card can say what would
    /// actually help instead of offering a Retry that can't.
    static func failureError(
        provider: String,
        _ degradation: RealtimeDegradation,
        transport: URLError.Code?
    ) -> any Error {
        let reason = failureReason(provider: provider, degradation)
        if case .refused(let refusal, _) = degradation {
            switch refusal {
            case .unauthorized:
                return CloudTranscriptionError(cause: .http(status: 401, retryAfter: nil, apiCode: nil), reason: reason)
            case .rateLimited(let retryAfter):
                return CloudTranscriptionError(cause: .http(status: 429, retryAfter: retryAfter, apiCode: nil), reason: reason)
            case .quotaExceeded:
                return CloudTranscriptionError(
                    cause: .http(status: 429, retryAfter: nil, apiCode: "insufficient_quota"),
                    reason: reason
                )
            case .termsNotAccepted, .sessionLimit, .overloaded, .rejected:
                return TranscriptionEngineError.transcriptionFailed(reason)
            }
        }
        if let transport {
            return CloudTranscriptionError(cause: .transport(transport), reason: reason)
        }
        return TranscriptionEngineError.transcriptionFailed(reason)
    }

    /// Cap on a live session's finish wait. What is still owed is the audio
    /// since the last commit — the trailing utterance on a VAD model, the whole
    /// take on a manual-commit one — so the wait scales with that rather than
    /// being one flat window that a long tail outlasts.
    static func liveFinishCapMs(owedSampleCount: Int, sampleRate: Double) -> Int {
        cap(base: baseLiveFinishCapMs, sampleCount: owedSampleCount, sampleRate: sampleRate)
    }

    /// Cap on waiting for a buffered session's text. The whole take goes up
    /// faster than realtime and every transcript can still be owed at finish,
    /// so a fixed cap cut long takes short. Only a stalled server ever reaches
    /// it; a healthy one settles well inside.
    static func bufferedFinishCapMs(sampleCount: Int, sampleRate: Double) -> Int {
        cap(base: baseBufferedFinishCapMs, sampleCount: sampleCount, sampleRate: sampleRate)
    }

    private static func cap(base: Int, sampleCount: Int, sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return base }
        let seconds = Double(max(0, sampleCount)) / sampleRate
        return min(maxFinishCapMs, base + Int(seconds * Double(finishMsPerAudioSecond)))
    }

    static let baseLiveFinishCapMs = 5_000
    static let baseBufferedFinishCapMs = 15_000
    static let finishMsPerAudioSecond = 500
    /// No finish wait gets near the dictation controller's 10-minute
    /// transcription watchdog, even with an automatic re-send after it.
    static let maxFinishCapMs = 240_000
    /// Wall-clock budget for the automatic re-send of a degraded live take,
    /// connection included. It runs while the user watches "Transcribing", so
    /// a server that stalls again must hand over to the Retry card within a
    /// minute rather than after the full buffered cap; a manual Retry still
    /// gets that.
    static let resendBudgetMs = 60_000

    /// Whole milliseconds left before `deadline`, never negative.
    static func milliseconds(until deadline: ContinuousClock.Instant, now: ContinuousClock.Instant = .now) -> Int {
        max(0, Int(((deadline - now) / .milliseconds(1)).rounded(.down)))
    }

    /// Any 30 ms frame of `samples` louder than `thresholdDBFS`: audio that may
    /// hold speech the server hasn't committed, as opposed to silence it has
    /// nothing to say about.
    static func hasSpeechEnergy(_ samples: [Float], sampleRate: Int, thresholdDBFS: Float) -> Bool {
        let frame = max(1, sampleRate * 30 / 1_000)
        var start = 0
        while start < samples.count {
            let end = min(start + frame, samples.count)
            var sum: Float = 0
            for index in start..<end { sum += samples[index] * samples[index] }
            let rms = (sum / Float(end - start)).squareRoot()
            if rms > 0, 20 * log10(rms) > thresholdDBFS { return true }
            start = end
        }
        return false
    }
}

/// OpenAI transcripts in the order they were spoken.
///
/// `…transcription.completed` events arrive in completion order, and OpenAI
/// doesn't promise that follows commit order across items — which a buffered
/// session, committing a whole take's utterances back to back, turns into
/// shuffled text. Each item is placed where `input_audio_buffer.committed`
/// put it (after its `previous_item_id`), and deltas are kept per item, so
/// two utterances transcribing at once can't interleave in the live text
/// either.
nonisolated struct RealtimeTranscriptOrder: Equatable, Sendable {
    private(set) var itemIDs: [String] = []
    private var finals: [String: String] = [:]
    private var partials: [String: String] = [:]

    mutating func committed(itemID: String, previousItemID: String?) {
        guard !itemIDs.contains(itemID) else { return }
        if let previousItemID, let index = itemIDs.firstIndex(of: previousItemID) {
            itemIDs.insert(itemID, at: index + 1)
        } else {
            itemIDs.append(itemID)
        }
    }

    mutating func delta(itemID: String, _ text: String) {
        place(itemID)
        guard finals[itemID] == nil else { return }
        partials[itemID, default: ""] += text
    }

    mutating func completed(itemID: String, transcript: String) {
        place(itemID)
        finals[itemID] = transcript
        partials[itemID] = nil
    }

    /// A failed item keeps its slot, empty.
    mutating func failed(itemID: String) {
        place(itemID)
        finals[itemID] = ""
        partials[itemID] = nil
    }

    /// Final text where it has arrived, the partial where it hasn't.
    var text: String {
        itemIDs
            .compactMap { finals[$0] ?? partials[$0] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var hasPartial: Bool {
        partials.values.contains { !$0.isEmpty }
    }

    /// An item heard of before its `committed` (which shouldn't happen) goes
    /// last rather than nowhere.
    private mutating func place(_ itemID: String) {
        if !itemIDs.contains(itemID) { itemIDs.append(itemID) }
    }
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
    /// The first reason the transcript can't be trusted; later ones add
    /// nothing — except a refusal, which replaces whatever came before it.
    private(set) var degradation: RealtimeDegradation?
    /// The first network error behind a send failure or a close, so the
    /// failure card can tell "offline" from anything else.
    private(set) var transport: URLError.Code?
    /// Utterances transcribed, and utterances the server failed on, this
    /// session. Together they tell a take that lost a line from one that got
    /// nothing back at all.
    private(set) var completedTranscripts = 0
    private(set) var failedTranscripts = 0
    private var firstTranscriptFailure: String?
    /// The first failed utterance whose message talks about the account or
    /// its balance without naming a refusal outright.
    private var accountTranscriptFailure: String?
    /// Something more than one utterance's failure degraded the session — a
    /// refusal, a drop, a server error on the socket, an expired wait. No
    /// amount of waiting mends those; a failed utterance leaves the rest of
    /// the take still worth waiting for, since they decide between a re-send
    /// and "nothing transcribed".
    private(set) var interrupted = false
    /// Audio or text was lost to the network: a send failed, or the socket
    /// closed with text still owed. Failed utterances before that are no
    /// evidence the rest would have failed too.
    private(set) var connectionFailed = false
    /// The server's message for the last `session.update` it rejected, while
    /// the fallback ladder is still waiting on a reduced one. A server that
    /// rejects the config and then hangs up has said more about the take
    /// than "the connection dropped".
    private(set) var configRejection: String?

    /// Nothing more is coming, or waiting can no longer help.
    var isSettled: Bool {
        if closed || interrupted { return true }
        return !awaitingCommitReply && pendingTranscripts == 0 && !uncommittedSpeech
    }

    /// What the finish reports. A take the server transcribed none of is
    /// reported as that — and so not re-sent — only on strong evidence:
    /// nothing completed, nothing still owed, no network loss to blame, and
    /// either several utterances failed or one said why in terms of the
    /// account. One transient failure, or a failure followed by a drop or a
    /// timeout, keeps its own reason and gets the single re-send. A refusal
    /// the provider named always stands.
    var outcome: RealtimeDegradation? {
        guard let degradation, !degradation.isRefusal else { return degradation }
        guard completedTranscripts == 0, pendingTranscripts == 0, !awaitingCommitReply, !uncommittedSpeech,
              !connectionFailed,
              failedTranscripts >= 2 || accountTranscriptFailure != nil else { return degradation }
        return .nothingTranscribed(accountTranscriptFailure ?? firstTranscriptFailure ?? "every utterance failed")
    }

    /// An utterance failed after another came back: whatever is still owed,
    /// the finish can only report that failure and re-send the take, so
    /// waiting for the rest decides nothing. The live wait matters only while
    /// "nothing transcribed" is still possible.
    var resendIsCertain: Bool {
        degradation != nil && completedTranscripts > 0
    }

    /// The live path commits only when something is actually in the buffer:
    /// speech the VAD is still inside, a partial on screen, or a model that
    /// never commits on its own. Committing trailing silence would only invite
    /// a hallucinated line.
    func needsFinishCommit(manualCommit: Bool, hasPartial: Bool) -> Bool {
        manualCommit || uncommittedSpeech || hasPartial
    }

    /// `speech_started` can land after the finish already decided no commit
    /// was needed — the VAD is still working through the last audio sent.
    /// That speech needs its own commit, or the wait runs out and the whole
    /// take is re-sent for one trailing word.
    var needsFollowUpCommit: Bool {
        finishing && !closed && !interrupted && uncommittedSpeech && !awaitingCommitReply
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
        completedTranscripts += 1
    }

    /// `…input_audio_transcription.failed`: that utterance's text is gone.
    /// `refusal` is what its error names, if anything — an empty balance can
    /// surface here, one utterance at a time, rather than on the socket.
    mutating func transcriptFailed(_ message: String, refusal: RealtimeRefusal? = nil) {
        pendingTranscripts = max(0, pendingTranscripts - 1)
        failedTranscripts += 1
        if firstTranscriptFailure == nil { firstTranscriptFailure = message }
        if let refusal {
            degrade(.refused(refusal, message))
            return
        }
        if accountTranscriptFailure == nil, RealtimeRefusal.mentionsAccount(message) {
            accountTranscriptFailure = message
        }
        degrade(.serverError(message), interrupts: false)
    }

    /// The fallback ladder is retrying a config the server rejected with
    /// `message`.
    mutating func configRejected(_ message: String) { configRejection = message }

    /// `session.updated`: whatever the ladder was answering is settled.
    mutating func configAccepted() { configRejection = nil }

    /// `input_audio_buffer_commit_empty`: the finishing commit found nothing
    /// left to transcribe — an answer, not a failure.
    mutating func commitFoundEmptyBuffer() {
        awaitingCommitReply = false
    }

    mutating func serverError(_ message: String) { degrade(.serverError(message)) }

    mutating func refused(_ refusal: RealtimeRefusal, _ message: String) { degrade(.refused(refusal, message)) }

    /// While a rejected config is unanswered, the server's message stands in
    /// for the send failure it led to.
    mutating func sendFailed(_ reason: String, transport code: URLError.Code? = nil) {
        note(code)
        connectionFailed = true
        degrade(configRejection.map(RealtimeDegradation.serverError) ?? .sendFailed(reason))
    }

    mutating func beginFinish() { finishing = true }

    mutating func finishCommitSent() { awaitingCommitReply = true }

    /// A close mid-take loses whatever was said after it; during the finish it
    /// only matters while text is still owed. A close that follows a rejected
    /// config is reported with the server's message.
    mutating func connectionClosed(transport code: URLError.Code? = nil) {
        let owed = !finishing || !isSettled
        closed = true
        if owed {
            note(code)
            connectionFailed = true
            degrade(configRejection.map(RealtimeDegradation.serverError) ?? .connectionLost)
        }
    }

    /// The engine's finish wait ran out before the session was done.
    mutating func finishWindowExpired() { degrade(.finishTimedOut) }

    private mutating func note(_ code: URLError.Code?) {
        if transport == nil { transport = code }
    }

    /// The first reason sticks, with one exception: a refusal replaces an
    /// earlier reason that isn't one. A refused handshake often shows up
    /// first as the send that failed on it, and reporting that send would
    /// re-send a take the provider has already said it won't take.
    private mutating func degrade(_ reason: RealtimeDegradation, interrupts: Bool = true) {
        if interrupts { interrupted = true }
        guard let degradation else {
            degradation = reason
            return
        }
        if reason.isRefusal, !degradation.isRefusal { self.degradation = reason }
    }
}

/// End-of-session bookkeeping for `ElevenLabsRealtimeEngine`.
///
/// ElevenLabs acknowledges a commit only with the `committed_transcript` it
/// produces; what it sends for a commit that found nothing to transcribe isn't
/// documented. So the finish avoids needing that answer: it flushes only when
/// speech may still be uncommitted — a partial on screen, or audio with speech
/// energy sent after what the last commit can be trusted to cover — and
/// otherwise finishes at once. After a flush it waits for a committed segment
/// with no partial left showing, or, failing any answer, for the stream to go
/// quiet with no partial showing. `insufficient_audio_activity` and
/// `commit_throttled` still end the wait early when they do arrive.
nonisolated struct ElevenLabsRealtimeFinishTracker: Equatable, Sendable {
    /// A partial is showing that no committed segment has replaced yet.
    private(set) var hasPartial = false
    private(set) var finishing = false
    private(set) var flushSent = false
    private(set) var flushAnswered = false
    private(set) var closed = false
    private(set) var degradation: RealtimeDegradation?
    /// The first network error behind a send failure or a close.
    private(set) var transport: URLError.Code?
    /// Bumped on every partial or committed segment. A buffered session keeps
    /// waiting until this stops moving: its audio went up faster than
    /// realtime, so the first commit after the flush is usually an early VAD
    /// segment, not the answer to the flush.
    private(set) var transcriptEvents = 0
    private(set) var eventsAtFlush = 0

    /// Samples sent so far, the end of the last chunk that had speech energy,
    /// and how far the commits so far can be trusted to reach.
    private(set) var sentSamples = 0
    private(set) var voicedThrough = 0
    private(set) var committedThrough = 0
    /// A committed segment arrives after the VAD's silence window and the
    /// transcription itself, so it can't vouch for audio sent in that last
    /// stretch before it — speech there may belong to the next segment.
    let commitLagSamples: Int

    init(commitLagSamples: Int) {
        self.commitLagSamples = commitLagSamples
    }

    /// Speech may still be sitting uncommitted on the server.
    var needsFlush: Bool {
        hasPartial || voicedThrough > committedThrough
    }

    /// Audio sent since the last commit — what the finish may still be owed.
    var owedSampleCount: Int {
        max(0, sentSamples - committedThrough)
    }

    /// The finish can stop waiting. `quietMs` is how long no partial or
    /// committed segment has arrived (counted from the flush).
    ///
    /// A live session is done once a commit has answered the flush and
    /// nothing more follows for a moment — the first commit after the flush
    /// can be the VAD's for the previous segment, with the flush's own close
    /// behind it — or, with no answer at all, once the stream has stayed quiet
    /// with no partial showing. A buffered session needs to have heard back
    /// and then a longer quiet, since its segments arrive in a burst.
    func isDone(quietMs: Int, buffered: Bool) -> Bool {
        if closed || degradation != nil { return true }
        if hasPartial { return false }
        guard flushSent else { return true }
        if buffered {
            let heardBack = flushAnswered || transcriptEvents > eventsAtFlush
            return heardBack && quietMs >= Self.bufferedQuietMs
        }
        return (flushAnswered && quietMs >= Self.answerSettleMs) || quietMs >= Self.liveQuietMs
    }

    static let answerSettleMs = 500
    static let liveQuietMs = 1_500
    static let bufferedQuietMs = 2_000

    mutating func audioSent(sampleCount: Int, hasSpeechEnergy: Bool) {
        sentSamples += sampleCount
        if hasSpeechEnergy { voicedThrough = sentSamples }
    }

    mutating func partialTranscript(_ text: String) {
        hasPartial = !text.isEmpty
        transcriptEvents += 1
    }

    mutating func committedTranscript() {
        hasPartial = false
        transcriptEvents += 1
        committedThrough = max(committedThrough, sentSamples - commitLagSamples)
        if flushSent { flushAnswered = true }
    }

    /// `insufficient_audio_activity` or `commit_throttled`. Before the flush
    /// neither says anything about lost audio — the app never commits then.
    mutating func nothingToCommit() {
        if flushSent, !hasPartial { flushAnswered = true }
    }

    mutating func serverError(_ message: String) { degrade(.serverError(message)) }

    mutating func refused(_ refusal: RealtimeRefusal, _ message: String) { degrade(.refused(refusal, message)) }

    mutating func sendFailed(_ reason: String, transport code: URLError.Code? = nil) {
        note(code)
        degrade(.sendFailed(reason))
    }

    mutating func beginFinish() { finishing = true }

    mutating func flushCommitSent() {
        flushSent = true
        eventsAtFlush = transcriptEvents
    }

    /// A close mid-take loses whatever was said after it; during the finish it
    /// only matters while a flush or a partial is still unanswered.
    mutating func connectionClosed(transport code: URLError.Code? = nil) {
        let owed = !finishing || hasPartial || (flushSent && !flushAnswered)
        closed = true
        if owed {
            note(code)
            degrade(.connectionLost)
        }
    }

    /// The engine's finish wait ran out before the session was done.
    mutating func finishWindowExpired() { degrade(.finishTimedOut) }

    private mutating func note(_ code: URLError.Code?) {
        if transport == nil { transport = code }
    }

    /// First reason wins, except that a refusal replaces an earlier one that
    /// isn't (see `OpenAIRealtimeFinishTracker.degrade`).
    private mutating func degrade(_ reason: RealtimeDegradation) {
        guard let degradation else {
            degradation = reason
            return
        }
        if reason.isRefusal, !degradation.isRefusal { self.degradation = reason }
    }
}
