import Foundation

/// The out-of-credit and offline rescue where it reaches past the failure
/// card's own table (`DictationTakePolicy.failureCard`): the review banner a
/// failed Resume take gets instead of a card, and the transcribing card while
/// a take waits for the model on this Mac it was sent to.
///
/// Foundation-only and `nonisolated`, like the table it builds on, so a
/// harness can walk both.
nonisolated enum DictationRescue {
    typealias CardAction = DictationTakePolicy.CardAction

    // MARK: - A failed Resume take's banner

    /// What the review banner offers in place of the card's buttons. It has
    /// one Retry and one action beside it, and no Return of its own — Return
    /// pastes the review.
    struct ResumeBanner: Equatable, Sendable {
        /// What the banner's Retry runs, or nil for no Retry.
        let retry: CardAction?
        let action: CardAction?
    }

    /// The card's buttons, fitted to the banner. A model on this Mac is the
    /// banner's action. Out of credit, Retry goes: every model of that
    /// provider bills the same empty balance, so it can only be refused
    /// again — it stays in History for after a top-up. Offline it stays,
    /// as Retry <provider>, for once the connection is back. The lasting
    /// "Use for Dictation" is the card's alone: the banner has no room for a
    /// second action, and the take, not the dictation model, is what the
    /// banner is about. Every other card fits as it is: Retry, and what sits
    /// beside it.
    static func resumeBanner(
        failure: TranscriptionFailure,
        actions: (primary: CardAction, secondary: CardAction?)
    ) -> ResumeBanner {
        switch actions.primary {
        case .transcribeOnMac, .downloadAndTranscribe:
            return ResumeBanner(
                retry: failure == .quotaExhausted ? nil : actions.secondary,
                action: actions.primary
            )
        case .retry, .retryCloud, .useForDictation, .chooseModel, .checkAPIKey:
            return ResumeBanner(retry: actions.primary, action: actions.secondary)
        }
    }

    // MARK: - Waiting on the model

    /// What a take sent to a model on this Mac is waiting on, as the
    /// transcribing card names it in place of "Transcribing".
    enum ModelWait: Equatable, Sendable {
        /// Fetching the model's files: "Download & Transcribe".
        case downloading
        /// Loading or compiling a model that is on disk.
        case loading
    }

    /// The phase, read off the engine's own message — the registry reports
    /// no other. A message about downloading is a download, checked first:
    /// "Downloading 3/12 files" contains "load" too, which is how reading
    /// "load" alone mistakes a download for the compile tail. A model that
    /// was on disk when the take was sent to it can only be loading; one that
    /// wasn't is downloading until the engine says it has moved on to
    /// loading or compiling ("Loading model into memory…", "Compiling
    /// AudioEncoder…"), its first messages ("Starting…", "Listing files…",
    /// "Connecting to HuggingFace…") included.
    static func modelWait(message: String, wasOnDisk: Bool) -> ModelWait {
        let lower = message.lowercased()
        if lower.contains("download") { return .downloading }
        if wasOnDisk || lower.contains("load") || lower.contains("compil") { return .loading }
        return .downloading
    }

    /// The fraction to show for `wait`, or nil for the indeterminate state.
    /// A load reports nothing it can be measured by — Whisper parks at 95%
    /// for the whole of it — and a download that hasn't moved yet would show
    /// a 0% that reads as stuck.
    static func shownFraction(_ fraction: Double, during wait: ModelWait) -> Double? {
        guard wait == .downloading, fraction.isFinite, fraction > 0 else { return nil }
        return min(fraction, 1)
    }
}
