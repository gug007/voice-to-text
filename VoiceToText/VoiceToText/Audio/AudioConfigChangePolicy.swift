import Foundation

/// How a recording answers an `.AVAudioEngineConfigurationChange`.
///
/// Apple documents that notification as "the input or output hardware's sample
/// rate or channel count changed; re-wire the connections and start the engine"
/// — it carries no reason code and it is explicitly not a device-removal
/// signal. On a Bluetooth mic it is also self-inflicted: starting our own input
/// unit is what forces the A2DP → handsfree profile switch, so it fires on
/// essentially every take, ~250 ms after IO starts. Treating it as fatal cost
/// the whole recording every time.
///
/// The opposite mistake is just as expensive: every rebuild instantiates a
/// fresh input unit, which is another thing touching the input, which posts
/// another change — the self-feeding HAL storm `AudioRecorder`'s prewarm floor
/// exists to prevent. So a restart is always bounded, in attempts and in
/// wall-clock, and never re-arms on its own output.
///
/// Deliberately pure: no clock, no CoreAudio, no engine, no actor. The caller
/// injects a monotonic `now` and every threshold is an `init` parameter, so the
/// decision can be exercised by a harness instead of by unplugging AirPods.
nonisolated struct AudioConfigChangePolicy {
    enum Decision: Equatable, CustomStringConvertible {
        /// A sibling of a change a restart is already answering. Costs nothing
        /// and charges nothing.
        case ignoreCoalesced
        /// Restart capture once the hardware has had `after` to settle.
        case scheduleRestart(after: TimeInterval)
        /// Stop trying. The take ends here, and its audio is salvaged.
        case giveUp(reason: GiveUpReason)

        /// Log form. Every notification is logged with the decision it drew,
        /// which is the only way the budget can be sized from a real session.
        var description: String {
            switch self {
            case .ignoreCoalesced: return "coalesced into the restart in flight"
            case .scheduleRestart(let after): return "restarting capture in \(Int(after * 1000)) ms"
            case .giveUp(let reason): return "giving up (\(reason))"
            }
        }
    }

    enum GiveUpReason: String, Equatable, CustomStringConvertible {
        case budgetExhausted
        case deadlineExceeded

        var description: String { rawValue }
    }

    /// Longer than the ~190 ms of input-format flapping measured across an
    /// AirPods profile switch (0 Hz → 24 k → 48 k → 24 k), so one burst
    /// collapses into one attempt instead of landing a restart mid-flap.
    /// Deliberately independent of `prewarmDebounce` (1.5 s), which is six
    /// times larger because it is sized for a different job.
    static let defaultSettleDelay: TimeInterval = 0.3
    /// Attempts per **burst** — one notification burst, one follow-up provoked
    /// by our own restart, one spare. Measured on real AirPods: a single forced
    /// device change costs one restart, and three changes in a 15 s take each
    /// took one. It is a burst budget and not a session budget on purpose: it
    /// exists to stop a self-feeding storm, not to cap how many times a device
    /// may legitimately change over a ten-minute dictation.
    static let defaultMaxRestarts = 3
    /// Ceiling on retrying, from the **burst's** first change. One worst-case
    /// attempt is the settle delay plus the 8 s engine-queue start timeout plus
    /// the starvation grace ≈ 9.8 s, so this admits one of those and refuses to
    /// *begin* a second: a wedged CoreAudio must cost a recording, not a
    /// multi-minute stall the 300 s preparing watchdog is far too coarse to
    /// catch. It bounds time where `maxRestarts` bounds count, and the two
    /// diverge exactly when attempts are slow — which is the case worth
    /// bounding.
    static let defaultRestartDeadline: TimeInterval = 12
    /// How long capture must run healthily before a later change counts as a
    /// new burst rather than more of the one the budget was spent on.
    ///
    /// The longest silence *inside* a burst is one worst-case attempt — settle
    /// plus the 8 s start timeout plus the starvation grace ≈ 9.8 s — so this
    /// is three times the largest gap a burst can produce on its own. It is
    /// also `prewarmMinInterval`, which the recorder already uses to say "long
    /// enough that the HAL has settled", for the same physical reason.
    static let defaultBurstResetAfter: TimeInterval = 30
    /// How long a restarted tap may deliver nothing before it is presumed
    /// anchored to a rate the device no longer runs at — a documented failure
    /// where capture reports success and then silently delivers zero buffers
    /// for the rest of the session. One tap buffer is 21-43 ms depending on the
    /// hardware rate, so this is over thirty buffer periods of grace.
    static let defaultCaptureStarvation: TimeInterval = 1.5

    let settleDelay: TimeInterval
    let maxRestarts: Int
    let restartDeadline: TimeInterval
    let captureStarvation: TimeInterval
    let burstResetAfter: TimeInterval

    private(set) var restartsUsed = 0
    /// Terminal for this session. The take is being torn down, so every
    /// further notification is noise from a device we have stopped arguing
    /// with — and answering them would queue a second teardown behind the
    /// first.
    private(set) var hasGivenUp = false
    /// True from the moment an attempt is scheduled until it reports back. The
    /// primary coalescer: the engine queue is serial and already a debouncer,
    /// so anything arriving inside that window is answered by the attempt in
    /// flight.
    private(set) var isRestarting = false
    private var changeSeenDuringRestart = false
    /// First change of the **current burst**, which is what `restartDeadline`
    /// runs from. Cleared when a burst ends, so one benign change early in a
    /// long dictation cannot poison the rest of the take.
    private var firstChangeAt: TimeInterval?
    /// The most recent thing that happened in this burst: a change arriving or
    /// an attempt reporting back. The quiet period is measured from here, not
    /// from the burst's start, so a burst is only over once it stops moving.
    private var lastBurstActivityAt: TimeInterval?

    init(
        settleDelay: TimeInterval = defaultSettleDelay,
        maxRestarts: Int = defaultMaxRestarts,
        restartDeadline: TimeInterval = defaultRestartDeadline,
        captureStarvation: TimeInterval = defaultCaptureStarvation,
        burstResetAfter: TimeInterval = defaultBurstResetAfter
    ) {
        self.settleDelay = settleDelay
        self.maxRestarts = maxRestarts
        self.restartDeadline = restartDeadline
        self.captureStarvation = captureStarvation
        self.burstResetAfter = burstResetAfter
    }

    /// Called as a recording starts, so every session begins with a full
    /// budget and no burst in progress.
    mutating func reset() {
        restartsUsed = 0
        hasGivenUp = false
        isRestarting = false
        changeSeenDuringRestart = false
        firstChangeAt = nil
        lastBurstActivityAt = nil
    }

    /// `captureHealthy` is the recorder's evidence that the tap has actually
    /// delivered audio since the last restart landed — the caller reads its own
    /// sample counter, because the policy owns no clock and no engine.
    mutating func changeObserved(now: TimeInterval, captureHealthy: Bool) -> Decision {
        guard !hasGivenUp else { return .ignoreCoalesced }
        // A change that arrives long after the burst stopped moving, with audio
        // flowing throughout, is not more of that burst: it is an unrelated
        // route change, and it gets a full budget and a fresh deadline. Both
        // conditions are load-bearing. Time alone would let a take that has
        // been recording silence since its last restart buy itself a new budget
        // every half minute; health alone would hand a storm a new budget
        // between two of its own notifications.
        if captureHealthy, let last = lastBurstActivityAt, now - last >= burstResetAfter {
            restartsUsed = 0
            firstChangeAt = nil
        }
        lastBurstActivityAt = now
        guard !isRestarting else {
            // Remembered rather than dropped: the attempt in flight may have
            // been under way before this change happened, so it isn't
            // necessarily an answer to it. Re-read when the restart lands.
            changeSeenDuringRestart = true
            return .ignoreCoalesced
        }
        return schedule(now: now)
    }

    /// Charges one attempt. Called where the restart actually begins CoreAudio
    /// work, not where it is scheduled, so a notification a cheap pre-filter
    /// rejected — or an attempt whose session ended first — cannot spend the
    /// budget without ever touching the device.
    mutating func restartBegan() {
        restartsUsed += 1
    }

    mutating func restartSucceeded(now: TimeInterval) -> Decision {
        guard !hasGivenUp else { return .ignoreCoalesced }
        isRestarting = false
        lastBurstActivityAt = now
        // The deadline bounds a recovery in progress, and this one is over —
        // capture is running again. Leaving the clock anchored to a change the
        // take has already recovered from leaves a window between the deadline
        // and the burst reset in which every further change is refused on
        // arrival, killing a healthy take with its budget unspent.
        firstChangeAt = nil
        guard changeSeenDuringRestart else { return .ignoreCoalesced }
        changeSeenDuringRestart = false
        // Capture is running again, so an unaffordable follow-up here means
        // "keep the take and let the starvation watchdog judge it", never
        // "end it". Asked before scheduling rather than scheduled and then
        // swallowed: a `.giveUp` this method discards still records the
        // verdict, and every other entry point short-circuits on it, so the
        // take would be left unable to restart *and* unable to give up and
        // salvage — recording silence to the end.
        guard canSchedule(now: now) else { return .ignoreCoalesced }
        return schedule(now: now)
    }

    /// The attempt never reached the device — its session ended, or its queue
    /// was abandoned, while the settle delay ran. Drops the in-flight flag so
    /// a recorder that keeps living is not deaf to the next change, and leaves
    /// the spend alone: nothing was spent, and nothing was proven either.
    mutating func restartAbandoned() {
        isRestarting = false
        changeSeenDuringRestart = false
    }

    mutating func restartFailed(now: TimeInterval) -> Decision {
        guard !hasGivenUp else { return .ignoreCoalesced }
        isRestarting = false
        changeSeenDuringRestart = false
        lastBurstActivityAt = now
        return schedule(now: now)
    }

    /// The restart reported success and then no audio arrived. Escalates on the
    /// same budget as an outright failure — unless a later change already put
    /// another attempt in flight, which supersedes this verdict.
    mutating func captureStarved(now: TimeInterval) -> Decision {
        guard !hasGivenUp, !isRestarting else { return .ignoreCoalesced }
        lastBurstActivityAt = now
        return schedule(now: now)
    }

    /// Whether another attempt is affordable. Deliberately non-mutating: a
    /// caller that cannot act on a refusal must be able to ask without one
    /// being recorded against the take.
    private func canSchedule(now: TimeInterval) -> Bool {
        guard restartsUsed < maxRestarts else { return false }
        if let firstChangeAt, now - firstChangeAt >= restartDeadline { return false }
        return true
    }

    private mutating func schedule(now: TimeInterval) -> Decision {
        guard canSchedule(now: now) else {
            return giveUp(restartsUsed >= maxRestarts ? .budgetExhausted : .deadlineExceeded)
        }
        if firstChangeAt == nil { firstChangeAt = now }
        isRestarting = true
        return .scheduleRestart(after: settleDelay)
    }

    private mutating func giveUp(_ reason: GiveUpReason) -> Decision {
        hasGivenUp = true
        isRestarting = false
        changeSeenDuringRestart = false
        return .giveUp(reason: reason)
    }
}

/// What becomes of the audio a recording had banked when it has to end early.
///
/// One place decides it, so "the failure card can never be empty while audio
/// exists" is a property a harness asserts rather than an invariant argued
/// across call sites.
nonisolated enum RecordingSalvage {
    enum Outcome: Equatable {
        /// Enough to be worth transcribing — run the normal pipeline.
        case transcribe
        /// Too short for the pipeline, but the user still spoke: the failure
        /// card must show the clip, not an empty state.
        case failWithSalvagedAudio
        /// Nothing was captured at all.
        case failEmpty
    }

    static func outcome(sampleCount: Int, minTranscribeSamples: Int) -> Outcome {
        if sampleCount >= minTranscribeSamples { return .transcribe }
        if sampleCount > 0 { return .failWithSalvagedAudio }
        return .failEmpty
    }
}
