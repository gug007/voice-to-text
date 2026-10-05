import Foundation

/// Every string the out-of-credit and offline rescue puts on screen: the
/// dictation failure card, the review banner of a refused Resume take, the
/// History row's menu and the Models pane's banner. In one place so the same
/// action is called the same thing wherever it appears, and so a harness can
/// hold each string to the space it gets — the failure card is 600pt wide, its
/// banner gets two lines and its detail line one.
///
/// Sentence case for prose; Title Case for HUD buttons, as the card's other
/// buttons are ("Transcribe Anyway", "Check API Key"). Model names come in as
/// the caller shows them: a local model's `displayName`, a cloud model's
/// `sectionedDisplayName` ("GPT Transcribe", without " (OpenAI)").
///
/// Foundation-only and `nonisolated`, like `DictationTakePolicy`, whose
/// `CardAction`s these strings label.
nonisolated enum FailureCardCopy {
    typealias CardAction = DictationTakePolicy.CardAction
    typealias LocalFallback = DictationTakePolicy.LocalFallback

    /// The banner's two lines of 11pt text, as characters. The harness
    /// measures the longest real banners against the card's width; this is
    /// what code that composes a banner can check without a font.
    static let bannerCharacterBudget = 150
    /// The detail line's one line of 13pt text, as characters. This copy
    /// runs about 6.1pt a character, so 88 is ~540pt of the line's 576 —
    /// "1:02:03 saved to History · Whisper Large v3 Turbo runs on this Mac —
    /// free and private." (86) fits, the same take unsaved (90) doesn't.
    static let detailCharacterBudget = 88

    /// One button on the card.
    struct Button: Equatable, Sendable {
        let title: String
        /// SF Symbol name.
        let icon: String
        /// The key the button answers to, shown beside its title: "↩" on the
        /// primary, which Return runs; nil elsewhere.
        let hint: String?
    }

    /// Everything the failure card says, for one `DictationTakePolicy.failureCard`.
    struct Card: Equatable, Sendable {
        let banner: String
        /// Replaces the card's "N captured — saved to History." line; nil
        /// keeps that line.
        let detail: String?
        let primary: Button
        let secondary: Button?
    }

    /// The whole card.
    ///
    /// - Parameters:
    ///   - actions: what `DictationTakePolicy.failureCard` returned.
    ///   - provider: the failed model's provider name ("OpenAI"), nil for a
    ///     local model.
    ///   - local: the fallback `actions` was built from, if any — read for
    ///     whether it covers the user's languages.
    ///   - localName: that model's `displayName`.
    ///   - localLanguages: that model's `languages` ("25 European
    ///     languages"), said when it doesn't cover the user's.
    ///   - capturedSeconds: the length of the take.
    ///   - savedToHistory: whether the take is in History now.
    ///   - engineMessage: the engine's own message, which failures this
    ///     rescue has nothing to add to keep.
    static func card(
        failure: TranscriptionFailure,
        actions: (primary: CardAction, secondary: CardAction?),
        provider: String?,
        local: LocalFallback?,
        localName: String?,
        localLanguages: String?,
        capturedSeconds: TimeInterval,
        savedToHistory: Bool,
        isRepeatRefusal: Bool,
        engineMessage: String
    ) -> Card {
        let uncovered: String?
        if case .ready(_, coversLanguages: false)? = local { uncovered = localLanguages } else { uncovered = nil }
        return Card(
            banner: banner(
                failure: failure,
                primary: actions.primary,
                provider: provider,
                isRepeatRefusal: isRepeatRefusal,
                engineMessage: engineMessage
            ),
            detail: detail(
                failure: failure,
                primary: actions.primary,
                localName: localName,
                uncoveredLanguages: uncovered,
                capturedSeconds: capturedSeconds,
                savedToHistory: savedToHistory
            ),
            primary: Button(title: title(of: actions.primary, provider: provider), icon: icon(of: actions.primary), hint: "↩"),
            secondary: actions.secondary.map {
                Button(title: title(of: $0, provider: provider), icon: icon(of: $0), hint: nil)
            }
        )
    }

    // MARK: - Banner

    /// The card's banner. Out of credit or offline it says what the buttons
    /// below it do, in the order they matter; a refusal seen before this take
    /// moves on from "top up" to the lasting switch. Every other failure
    /// keeps `TranscriptionFailure.message`.
    static func banner(
        failure: TranscriptionFailure,
        primary: CardAction,
        provider: String?,
        isRepeatRefusal: Bool,
        engineMessage: String
    ) -> String {
        let service = provider ?? "The transcription service"
        switch failure {
        case .quotaExhausted:
            // With nothing on this Mac to fall back to, "use it for
            // dictation" would point at a model that isn't there; the first
            // refusal's words fit the Retry and Choose Model below.
            if isRepeatRefusal, runsLocally(primary) {
                return "\(service) is still out of credit. Transcribe on your Mac, or use it for dictation until you top up."
            }
            return "\(service) says your account is out of credit. Transcribe this take on your Mac, or top up and retry."
        case .offline:
            return runsLocally(primary)
                ? "You're offline. Transcribe this take on your Mac, or retry once you're connected."
                : "You're offline. Retry once you're connected."
        case .unauthorized, .rateLimited, .server, .other:
            return failure.message(provider: provider, fallback: engineMessage)
        }
    }

    /// The review banner's message for a Resume take that failed, which the
    /// controller prefixes with "Recording saved to History." when it is.
    /// The banner has one line's worth of room beside its buttons, and the
    /// button already says what to do, so out of credit it only says why.
    static func reviewBanner(
        failure: TranscriptionFailure,
        primary: CardAction,
        provider: String?,
        engineMessage: String
    ) -> String {
        if failure == .quotaExhausted {
            return "\(provider ?? "The transcription service") is out of credit."
        }
        return banner(failure: failure, primary: primary, provider: provider, isRepeatRefusal: false, engineMessage: engineMessage)
    }

    // MARK: - Detail line

    /// The line under the banner, where the decision is made: how much was
    /// kept, and what the model on offer costs — nothing and nothing leaves
    /// the Mac, or a one-time download of a stated size. nil for failures
    /// this rescue doesn't touch, which keep the card's own line.
    ///
    /// `uncoveredLanguages` is the fallback's `languages` when it doesn't
    /// know every language the user speaks, nil otherwise: then the line
    /// says what it does know instead of promising it is free.
    static func detail(
        failure: TranscriptionFailure,
        primary: CardAction,
        localName: String?,
        uncoveredLanguages: String?,
        capturedSeconds: TimeInterval,
        savedToHistory: Bool
    ) -> String? {
        guard failure == .quotaExhausted || failure == .offline else { return nil }
        let kept = keptPrefix(capturedSeconds: capturedSeconds, savedToHistory: savedToHistory)
        let name = localName ?? "This model"
        switch primary {
        case .transcribeOnMac:
            if let uncoveredLanguages {
                return fitting(
                    "\(kept) · \(name) covers \(uncoveredLanguages) only.",
                    or: "\(kept) · \(name) covers fewer languages."
                )
            }
            return fitting(
                "\(kept) · \(name) runs on this Mac — free and private.",
                or: "\(kept) · \(name) runs on this Mac."
            )
        case .downloadAndTranscribe(_, let sizeMB):
            return fitting(
                "\(kept) · \(name) is a one-time \(sizeText(megabytes: sizeMB)) download.",
                or: "\(kept) · a one-time \(sizeText(megabytes: sizeMB)) download."
            )
        case .retry, .retryCloud, .useForDictation, .chooseModel, .checkAPIKey:
            return "\(kept)."
        }
    }

    /// "42.0s saved to History", "1:02:03 captured, not saved". Below a
    /// minute in tenths, above it on the clock — the card's own captured
    /// line reads durations the same way (`LiveHUDView`).
    static func keptPrefix(capturedSeconds: TimeInterval, savedToHistory: Bool) -> String {
        guard capturedSeconds > 0 else { return savedToHistory ? "Saved to History" : "Not saved" }
        let captured = capturedDuration(capturedSeconds)
        return savedToHistory ? "\(captured) saved to History" : "\(captured) captured, not saved"
    }

    static func capturedDuration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return String(format: "%.1fs", seconds) }
        // `formattedClock`'s shape, computed here: that extension is main
        // actor-isolated, and this type is not.
        let total = seconds.isFinite ? Int(seconds.rounded()) : 0
        let (hours, minutes, rest) = (total / 3_600, (total % 3_600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// "470 MB", "1.5 GB" — decimal units, as the Models pane counts.
    static func sizeText(megabytes: Int) -> String {
        megabytes < 1_000 ? "\(megabytes) MB" : String(format: "%.1f GB", Double(megabytes) / 1_000)
    }

    private static func fitting(_ preferred: String, or shorter: String) -> String {
        preferred.count <= detailCharacterBudget ? preferred : shorter
    }

    private static func runsLocally(_ action: CardAction) -> Bool {
        switch action {
        case .transcribeOnMac, .downloadAndTranscribe: return true
        case .retry, .retryCloud, .useForDictation, .chooseModel, .checkAPIKey: return false
        }
    }

    // MARK: - Buttons

    /// The button's title. `provider` names "Retry <provider>", which says
    /// outright that it goes back to the service that just refused.
    static func title(of action: CardAction, provider: String?) -> String {
        switch action {
        case .retry: return "Retry"
        case .retryCloud: return provider.map { "Retry \($0)" } ?? "Retry"
        case .transcribeOnMac: return "Transcribe on Mac"
        case .downloadAndTranscribe: return "Download & Transcribe"
        case .useForDictation: return "Use for Dictation"
        case .chooseModel: return "Choose Model"
        case .checkAPIKey: return "Check API Key"
        }
    }

    static func icon(of action: CardAction) -> String {
        switch action {
        case .retry, .retryCloud: return "arrow.clockwise"
        case .transcribeOnMac: return "laptopcomputer"
        case .downloadAndTranscribe: return "arrow.down.circle"
        case .useForDictation: return "checkmark.circle"
        case .chooseModel: return "square.and.arrow.down"
        case .checkAPIKey: return "key.fill"
        }
    }

    // MARK: - Downloading on the card

    /// The transcribing card's phase while the fallback is fetched, then
    /// loaded (`ModelReadiness.isLoadingOrCompiling`).
    static func preparePhaseTitle(isLoading: Bool) -> String {
        isLoading ? "Loading" : "Downloading"
    }

    /// "42%", or nil while the fraction is unknown or still zero — the
    /// indeterminate state, where a "0%" would read as stuck.
    static func percent(_ fraction: Double?) -> String? {
        guard let fraction, fraction.isFinite, fraction > 0 else { return nil }
        return "\(Int((min(fraction, 1) * 100).rounded(.down)))%"
    }

    /// "Parakeet TDT v3 · 42%", or the name alone without a fraction.
    static func downloadProgress(modelName: String, fraction: Double?) -> String {
        percent(fraction).map { "\(modelName) · \($0)" } ?? modelName
    }

    /// The failure card's message when the fallback didn't download.
    /// `reason` is the registry's `.failed` message, when it has one.
    static func downloadFailed(modelName: String, reason: String?) -> String {
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else {
            return "Couldn't download \(modelName). Check your connection and try again."
        }
        let sentence = reason.last.map { ".!?".contains($0) } == true ? reason : reason + "."
        return "Couldn't download \(modelName). \(sentence)"
    }

    /// The message when the fallback downloaded but wouldn't load. `reason`
    /// is the registry's `.failed` message, when it has one.
    static func loadFailed(modelName: String, reason: String?) -> String {
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else {
            return "Couldn't load \(modelName). Try again, or re-download it in Models."
        }
        let sentence = reason.last.map { ".!?".contains($0) } == true ? reason : reason + "."
        return "Couldn't load \(modelName). \(sentence)"
    }

    /// The notice after a cancel while the fallback was still downloading:
    /// the take is kept, and the download — the registry's, shared with the
    /// Models pane — carries on for next time.
    static let cancelledWhileDownloadingNotice = "Saved to History · download continues"

    // MARK: - History row

    /// The History row's first menu item for a take whose provider is out of
    /// credit: "Transcribe with Parakeet TDT v3", or "Download & transcribe
    /// with Parakeet TDT v3 (470 MB)" — sentence case, as menu items are.
    static func historyLocalTitle(_ fallback: LocalFallback, modelName: String) -> String {
        switch fallback {
        case .ready:
            return "Transcribe with \(modelName)"
        case .download(_, let sizeMB):
            return "Download & transcribe with \(modelName) (\(sizeText(megabytes: sizeMB)))"
        }
    }

    /// "Retry with GPT Transcribe".
    static func historyRetryTitle(cloudModelName: String) -> String {
        "Retry with \(cloudModelName)"
    }

    static let historyOtherModelTitle = "Other model…"

    /// "Downloading Parakeet TDT v3 · 42%", while a row's transcription
    /// waits on its model.
    static func historyDownloading(modelName: String, fraction: Double?) -> String {
        "Downloading \(downloadProgress(modelName: modelName, fraction: fraction))"
    }

    // MARK: - Settings

    /// The Models pane's banner while "Use for Dictation" stands:
    /// "Switched from GPT Transcribe when OpenAI ran out of credit."
    static func switchedBanner(cloudModelName: String, provider: String) -> String {
        "Switched from \(cloudModelName) when \(provider) ran out of credit."
    }

    static let switchBackTitle = "Switch Back"

    /// A flagged provider's status, in place of "Connected", and the segment
    /// on its models' rows.
    static let outOfCreditLabel = "Out of credit"
}
