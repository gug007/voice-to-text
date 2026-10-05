import Foundation

/// What becomes of a dictation take's audio once recording has stopped.
///
/// The rule this exists to hold: a take the user spoke is never destroyed
/// without them seeing it go. Its audio is saved to History the moment it
/// stops — before the speech gate or any engine runs — so a quit, a crash or
/// an update relaunch mid-request leaves a row that can be transcribed again.
/// What happens to that row next depends on how the attempt ended and on
/// whether the user has already been told the take is saved, which is why
/// both are inputs here and every answer is in one table.
///
/// Pure and `nonisolated`, like `RecordingSalvage`, so a harness can walk the
/// table instead of a user walking every card.
nonisolated enum DictationTakePolicy {
    /// Below this, a take cancelled while it was transcribing is let go, as
    /// cancelling always did. A few seconds is a stray press or a false
    /// start the user just abandoned on purpose; a row for it in History
    /// would be clutter. Past it, the take is real dictation — the kind a
    /// user cancels out of a hung request rather than out of the words — and
    /// it is kept as an untranscribed row instead of being thrown away.
    static let minCancelledSecondsKept: TimeInterval = 5

    /// Below this, a recording cancelled mid-take is gone at once. Under
    /// three seconds the cancel is almost always the point: the hotkey hit by
    /// mistake, a restart before the first sentence. Past it, Cancel or Esc
    /// may have been a slip over minutes of speech, so the audio is held
    /// behind an Undo for as long as History's own Undo lasts.
    static let minDiscardedRecordingSecondsHeld: TimeInterval = 3

    /// Where the take stands in History right now.
    enum RowStage: Equatable, Sendable {
        /// No row: History is off, the row was taken back, or the user
        /// deleted it (`rowStage`).
        case none
        /// Saved ahead of transcription, and the user hasn't been told —
        /// to them it is still an ordinary dictation in progress.
        case writeAhead
        /// A failure card or banner has said this take is in History.
        case surfaced
    }

    /// How one attempt at transcribing the take ended.
    enum Outcome: Equatable, Sendable {
        /// The engine produced text.
        case transcribed
        /// The engine failed, the model wouldn't prepare, or the watchdog
        /// gave up on it.
        case failed
        /// Nothing worth keeping: the speech gate heard no speech, or the
        /// engine ran and wrote nothing.
        case unusable
        /// The user cancelled while it was transcribing. `seconds` is the
        /// length of the take.
        case cancelled(seconds: TimeInterval)
    }

    /// What to do with the take's row.
    enum Disposition: Equatable, Sendable {
        /// File the transcript — into the row if there is one, otherwise as a
        /// new row (when History is on). `pending` keeps it retractable by a
        /// review Cancel, as an ordinary dictation is: true for a take the
        /// user never heard was saved, false for one a card already promised.
        case keepTranscript(pending: Bool)
        /// Keep the take in History as untranscribed, saying why — saved even
        /// with History off, because the audio can't be recorded again.
        case keepFailed
        /// Delete the write-ahead row. The card says the audio isn't saved.
        case retract
        /// Leave History as it is.
        case leave
    }

    /// The stage of a take whose row may have left History under it. Only a
    /// row in History's visible list counts: one the user deleted — or one
    /// in History's undo window after a delete or Clear All, a timer away
    /// from gone with its audio — no longer holds the take. The take is then
    /// treated as having no row, so whatever keeps it saves it afresh rather
    /// than promising a row that is about to disappear. The controller takes
    /// a row still in that window back before asking, so in practice "no
    /// row" here means one whose deletion has committed: filing a second row
    /// beside one Undo could still restore would leave two.
    static func rowStage(hasRow: Bool, isInHistory: Bool, isSurfaced: Bool) -> RowStage {
        guard hasRow, isInHistory else { return .none }
        return isSurfaced ? .surfaced : .writeAhead
    }

    /// What a recording held behind "Recording discarded · Undo" keeps when a
    /// second copy of its audio arrives late. The buffer drains once, so of
    /// two stops racing for it one gets everything and the other nothing —
    /// and the late one may be the winner. The longer copy is the take.
    static func heldRecordingSamples(held: [Float], late: [Float]) -> [Float] {
        late.count > held.count ? late : held
    }

    /// Whether to save the take before transcribing it. A take that already
    /// has a row — a retry of one saved on failure — keeps the row it has.
    /// History off means nothing is written ahead: with saving off, a take
    /// that transcribes is never written at all.
    static func writesAhead(historyEnabled: Bool, row: RowStage) -> Bool {
        historyEnabled && row == .none
    }

    static func disposition(for outcome: Outcome, row: RowStage) -> Disposition {
        switch outcome {
        case .transcribed:
            return .keepTranscript(pending: row != .surfaced)

        case .failed:
            return .keepFailed

        // Silence is not kept: rows of it would push real dictations out of
        // the History cap, and past the gate a rejection is almost always
        // real silence. A take already promised as saved keeps its row, now
        // with this as its latest reason.
        case .unusable:
            switch row {
            case .surfaced: return .keepFailed
            case .writeAhead: return .retract
            case .none: return .leave
            }

        // A take the user was already told is saved stays as it was — with
        // the failure that put it there, which says more than "cancelled".
        case .cancelled(let seconds):
            switch row {
            case .surfaced:
                return .leave
            case .writeAhead:
                return seconds >= minCancelledSecondsKept ? .keepFailed : .retract
            case .none:
                return seconds >= minCancelledSecondsKept ? .keepFailed : .leave
            }
        }
    }

    /// Whether a failure card's "Transcribe on Mac" or "Download &
    /// Transcribe" still picks the model this take's retries run on. It was
    /// chosen over the dictation model the user had then
    /// (`chosenOverModelID`); once they pick another in Settings — or "Use
    /// for Dictation" picks one for them — that newer choice is the one a
    /// Retry honours. The override may be the very model whose own run just
    /// failed to prepare.
    static func keepsRetryModelOverride(chosenOverModelID: String?, activeModelID: String?) -> Bool {
        chosenOverModelID == activeModelID
    }

    /// Whether a recording cancelled after `seconds` is held for Undo.
    static func holdsDiscardedRecording(seconds: TimeInterval) -> Bool {
        seconds >= minDiscardedRecordingSecondsHeld
    }

    // MARK: - A model on this Mac, when the cloud can't run the take

    /// A model that runs on this Mac, as `localFallback` weighs it. Built from
    /// the catalog's local models, in catalog order — the order is the
    /// recommendation, which is why Parakeet leads.
    struct LocalCandidate: Equatable, Sendable {
        let id: String
        /// Downloaded and ready to load without the network
        /// (`ModelStorage.isDownloaded`, as History asks it) — not merely a
        /// folder a download is still writing into.
        let isInstalled: Bool
        /// Lowercase ISO 639-1 codes the model transcribes; nil for one that
        /// is broadly multilingual (`ModelDescriptor.languageCodes`).
        let languageCodes: Set<String>?
        let sizeMB: Int
        /// False for the models too weak to choose for the user
        /// (`ModelDescriptor.autoPickable`).
        let autoPickable: Bool

        /// Whether it transcribes every language the user speaks. Nothing
        /// known about what they speak counts as covered: guessing a gap
        /// would push a download nobody needed.
        func covers(_ spokenLanguages: Set<String>) -> Bool {
            guard !spokenLanguages.isEmpty, let languageCodes else { return true }
            return spokenLanguages.isSubset(of: languageCodes)
        }
    }

    /// The model on this Mac a failed cloud take is offered to.
    enum LocalFallback: Equatable, Sendable {
        /// On disk: transcribing with it starts at once. `coversLanguages` is
        /// false when it is the only one there and doesn't know a language
        /// the user speaks — still offered, since the take is otherwise stuck,
        /// but worth saying on the card.
        case ready(id: String, coversLanguages: Bool)
        /// Not on disk yet: the card downloads it, then transcribes. Only
        /// offered when the caller can download (online).
        case download(id: String, sizeMB: Int)

        var modelID: String {
            switch self {
            case .ready(let id, _), .download(let id, _): return id
            }
        }

        var needsDownload: Bool {
            if case .download = self { return true }
            return false
        }
    }

    /// Which model on this Mac to offer for a take the cloud refused or
    /// couldn't reach, or nil when there is none worth offering.
    ///
    /// A model already here that knows the user's languages wins: it is
    /// instant, free and private. Next, when a download is possible, the
    /// first one in catalog order that knows them — Parakeet, the smaller and
    /// faster, when it does; Whisper Large v3 Turbo for anything past its
    /// 25 European languages. A one-time download of a model that gets the
    /// words right beats an instant one that can't. Only then a model here
    /// that doesn't know every language, and last whatever is installed at
    /// all — Base and Tiny included, because they are still better than a
    /// take nobody can transcribe, but never chosen while anything else is.
    ///
    /// The model that just failed is never offered back.
    /// `spokenLanguages` and `primaryLanguage` come from
    /// `SpokenLanguages.current(recentDictations:)`. A `primaryLanguage` says
    /// the set is a guess from the Mac's settings, sure only of that one
    /// language: then a model here that knows it is offered before a
    /// download — the take is most likely in it, and the rest of the set
    /// may be a keyboard kept for the odd message, not worth a 632 MB wait.
    /// `canDownload` is false offline, where offering a download would only
    /// fail again.
    static func localFallback(
        candidates: [LocalCandidate],
        failedModelID: String,
        spokenLanguages: Set<String>,
        primaryLanguage: String? = nil,
        canDownload: Bool
    ) -> LocalFallback? {
        let others = candidates.filter { $0.id != failedModelID }
        let pickable = others.filter(\.autoPickable)

        if let ready = pickable.first(where: { $0.isInstalled && $0.covers(spokenLanguages) }) {
            return .ready(id: ready.id, coversLanguages: true)
        }
        if let primaryLanguage,
           let likely = pickable.first(where: { $0.isInstalled && $0.covers([primaryLanguage]) }) {
            return .ready(id: likely.id, coversLanguages: false)
        }
        if canDownload, let fetch = pickable.first(where: { $0.covers(spokenLanguages) }) {
            return .download(id: fetch.id, sizeMB: fetch.sizeMB)
        }
        if let partial = pickable.first(where: \.isInstalled) {
            return .ready(id: partial.id, coversLanguages: false)
        }
        if let anyInstalled = others.first(where: \.isInstalled) {
            return .ready(id: anyInstalled.id, coversLanguages: anyInstalled.covers(spokenLanguages))
        }
        return nil
    }

    // MARK: - The failure card's buttons

    /// One button on a dictation failure card. The card is laid out
    /// `[secondary] [Close esc] [primary ↩]`, and Return runs the primary.
    /// Titles and icons: `FailureCardCopy.title(of:provider:)` and `icon(of:)`.
    enum CardAction: Equatable, Sendable {
        /// "Retry ↩": the take again exactly as the last attempt ran it —
        /// today's `retryTranscription()`.
        case retry
        /// "Retry <provider>": the take again on the cloud model that failed,
        /// passed explicitly, so a one-off local override left from an earlier
        /// button can't quietly answer instead.
        case retryCloud
        /// "Transcribe on Mac ↩": the take once on this installed model, as a
        /// one-off override. The dictation model doesn't change.
        case transcribeOnMac(id: String)
        /// "Download & Transcribe ↩": fetch this model on the card, then
        /// transcribe the take with it, as a one-off override.
        case downloadAndTranscribe(id: String, sizeMB: Int)
        /// "Use for Dictation": make this model the dictation model — the one
        /// explicit, lasting switch, remembered so Settings can switch back —
        /// and transcribe the take with it.
        case useForDictation(id: String)
        /// "Choose Model": Settings → Models, for a take with no model on this
        /// Mac to fall back to.
        case chooseModel
        /// "Check API Key": Settings → Cloud, for a key the provider refused.
        case checkAPIKey
    }

    /// The failure card's buttons for a take an engine failed.
    ///
    /// Out of credit, every model of the same provider bills the same empty
    /// balance, so a model on this Mac leads and Return runs it; Retry stays
    /// beside it, named for the provider, for a user who has just topped up.
    /// Refused again — the provider was already flagged before this take —
    /// the card offers to make the local model the dictation model instead,
    /// since by now retrying is the unlikely path. Offline, a model already
    /// here leads the same way, but nothing is offered that needs the network
    /// to get: no download, no "Choose Model" leading to one.
    ///
    /// `local` is only evaluated for those two failures: it walks the model
    /// folders and the input sources, and a rate limit or a server error has
    /// no use for either. `isRepeatRefusal` comes from
    /// `CloudCreditStatus.noteRefusal`, read before this failure marks it.
    /// The speech gate's Transcribe Anyway and the cards no engine produced
    /// (permissions, paste) are not this table's.
    static func failureCard(
        failure: TranscriptionFailure,
        local: () -> LocalFallback?,
        isRepeatRefusal: Bool
    ) -> (primary: CardAction, secondary: CardAction?) {
        switch failure {
        case .quotaExhausted:
            guard let fallback = local() else { return (.retry, .chooseModel) }
            let primary = localAction(for: fallback)
            return (primary, isRepeatRefusal ? .useForDictation(id: fallback.modelID) : .retryCloud)
        case .offline:
            guard case .ready(let id, _)? = local() else { return (.retry, nil) }
            return (.transcribeOnMac(id: id), .retryCloud)
        case .unauthorized:
            return (.retry, .checkAPIKey)
        case .rateLimited, .server, .other:
            return (.retry, nil)
        }
    }

    /// The button that runs the take on `fallback` once.
    static func localAction(for fallback: LocalFallback) -> CardAction {
        switch fallback {
        case .ready(let id, _): return .transcribeOnMac(id: id)
        case .download(let id, let sizeMB): return .downloadAndTranscribe(id: id, sizeMB: sizeMB)
        }
    }
}
