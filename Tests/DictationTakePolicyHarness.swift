import Foundation

struct DictationTakePolicyHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw DictationTakePolicyHarnessFailure(description: message)
    }
}

@main
struct DictationTakePolicyHarness {
    typealias Policy = DictationTakePolicy

    static func main() throws {
        try aTakeIsWrittenAheadOnlyWhenHistoryIsOnAndItHasNoRow()
        try aTranscriptIsPendingUnlessTheCardAlreadyPromisedTheRow()
        try aFailureAlwaysKeepsTheTake()
        try silenceIsNotKeptUnlessTheTakeWasAlreadyPromised()
        try aCancelKeepsALongTakeAndLetsAShortOneGo()
        try aCancelNeverTakesBackARowTheUserWasToldAbout()
        try aDiscardedRecordingIsHeldFromThreeSeconds()
        try aRowThatLeftHistoryNoLongerHoldsTheTake()
        try aHeldRecordingKeepsTheLongerCopyOfItsAudio()
        try anInstalledModelThatKnowsTheLanguagesComesFirst()
        try onlineTheFirstModelThatKnowsTheLanguagesIsDownloaded()
        try offlineAModelThatDoesntKnowTheLanguagesIsStillOffered()
        try aGuessKeepsAModelHereThatKnowsItsPrimaryLanguage()
        try baseAndTinyAreOnlyOfferedWhenTheyAreAllThereIs()
        try theFailedModelIsNeverOfferedAgain()
        try nothingInstalledAndOfflineOffersNothing()
        try aFirstOutOfCreditRefusalLeadsWithTheMac()
        try aRepeatRefusalOffersTheLastingSwitch()
        try outOfCreditWithNothingToFallBackToOpensSettings()
        try offlineLeadsWithAnInstalledModelAndNeverADownload()
        try aRefusedKeyStillPointsAtTheKey()
        try otherFailuresOfferNothingAndWalkNoFolders()
        try aChosenRetryModelLastsOnlyWhileTheDictationModelDoes()
        print("Dictation take policy harness passed")
    }

    private static func aTakeIsWrittenAheadOnlyWhenHistoryIsOnAndItHasNoRow() throws {
        try expect(Policy.writesAhead(historyEnabled: true, row: .none), "a fresh take is saved before transcribing")
        try expect(!Policy.writesAhead(historyEnabled: false, row: .none), "History off writes nothing ahead")
        try expect(
            !Policy.writesAhead(historyEnabled: true, row: .surfaced),
            "a retry of a take saved on failure reuses its row rather than adding one"
        )
        try expect(
            !Policy.writesAhead(historyEnabled: true, row: .writeAhead),
            "a take is never written ahead twice"
        )
    }

    /// The write-ahead row stands in for what `record()` used to insert on
    /// success, so a review Cancel still takes it back behind Undo.
    private static func aTranscriptIsPendingUnlessTheCardAlreadyPromisedTheRow() throws {
        try expect(
            Policy.disposition(for: .transcribed, row: .writeAhead) == .keepTranscript(pending: true),
            "a write-ahead row filled in is an ordinary dictation: pending until kept"
        )
        try expect(
            Policy.disposition(for: .transcribed, row: .none) == .keepTranscript(pending: true),
            "with no row, the transcript is saved like any dictation, pending"
        )
        try expect(
            Policy.disposition(for: .transcribed, row: .surfaced) == .keepTranscript(pending: false),
            "a retry that works on a row the card promised can't be taken back by a review Cancel"
        )
    }

    private static func aFailureAlwaysKeepsTheTake() throws {
        for row in [Policy.RowStage.none, .writeAhead, .surfaced] {
            try expect(
                Policy.disposition(for: .failed, row: row) == .keepFailed,
                "an engine failure keeps the take (row \(row))"
            )
        }
    }

    private static func silenceIsNotKeptUnlessTheTakeWasAlreadyPromised() throws {
        try expect(
            Policy.disposition(for: .unusable, row: .writeAhead) == .retract,
            "a gate rejection or empty transcript takes the write-ahead row back"
        )
        try expect(
            Policy.disposition(for: .unusable, row: .none) == .leave,
            "with no row there is nothing to take back"
        )
        try expect(
            Policy.disposition(for: .unusable, row: .surfaced) == .keepFailed,
            "a saved failed take whose retry heard nothing keeps its row, with the new reason"
        )
    }

    private static func aCancelKeepsALongTakeAndLetsAShortOneGo() throws {
        let threshold = Policy.minCancelledSecondsKept
        try expect(threshold == 5, "the cancel threshold is five seconds")
        try expect(
            Policy.disposition(for: .cancelled(seconds: 124), row: .writeAhead) == .keepFailed,
            "a two-minute take cancelled mid-request stays in History"
        )
        try expect(
            Policy.disposition(for: .cancelled(seconds: threshold), row: .writeAhead) == .keepFailed,
            "the threshold itself is kept"
        )
        try expect(
            Policy.disposition(for: .cancelled(seconds: threshold - 0.1), row: .writeAhead) == .retract,
            "a short take cancelled is let go, as before"
        )
        try expect(
            Policy.disposition(for: .cancelled(seconds: 60), row: .none) == .keepFailed,
            "History off still keeps a long cancelled take, like a failed one"
        )
        try expect(
            Policy.disposition(for: .cancelled(seconds: 2), row: .none) == .leave,
            "a short take with no row leaves nothing behind"
        )
    }

    private static func aCancelNeverTakesBackARowTheUserWasToldAbout() throws {
        for seconds in [1.0, 5.0, 300.0] {
            try expect(
                Policy.disposition(for: .cancelled(seconds: seconds), row: .surfaced) == .leave,
                "a cancelled retry of a saved take leaves its row and its reason alone (\(seconds)s)"
            )
        }
    }

    private static func aDiscardedRecordingIsHeldFromThreeSeconds() throws {
        try expect(Policy.minDiscardedRecordingSecondsHeld == 3, "the discard threshold is three seconds")
        try expect(!Policy.holdsDiscardedRecording(seconds: 0.4), "a stray press is dropped at once")
        try expect(!Policy.holdsDiscardedRecording(seconds: 2.9), "just under the threshold is dropped")
        try expect(Policy.holdsDiscardedRecording(seconds: 3), "the threshold itself is held")
        try expect(Policy.holdsDiscardedRecording(seconds: 600), "a long take is held for Undo")
    }

    /// A row the user deleted mid-transcription (or that Clear All parked in
    /// History's undo window) must not be promised as "saved to History".
    private static func aRowThatLeftHistoryNoLongerHoldsTheTake() throws {
        try expect(
            Policy.rowStage(hasRow: true, isInHistory: true, isSurfaced: false) == .writeAhead,
            "a visible row not yet surfaced is write-ahead"
        )
        try expect(
            Policy.rowStage(hasRow: true, isInHistory: true, isSurfaced: true) == .surfaced,
            "a visible row a card announced is surfaced"
        )
        for surfaced in [false, true] {
            let stage = Policy.rowStage(hasRow: true, isInHistory: false, isSurfaced: surfaced)
            try expect(stage == .none, "a deleted row counts as no row (surfaced: \(surfaced))")
            try expect(
                Policy.disposition(for: .failed, row: stage) == .keepFailed,
                "a failure whose row was deleted saves the take afresh"
            )
            try expect(
                Policy.disposition(for: .cancelled(seconds: 60), row: stage) == .keepFailed,
                "a long cancelled take whose row was deleted is saved afresh"
            )
            try expect(
                Policy.disposition(for: .cancelled(seconds: 2), row: stage) == .leave,
                "a short cancelled take whose row was deleted stays deleted"
            )
            try expect(
                Policy.disposition(for: .unusable, row: stage) == .leave,
                "silence whose row was deleted stays deleted"
            )
        }
        try expect(
            Policy.rowStage(hasRow: false, isInHistory: false, isSurfaced: false) == .none,
            "no row is no row"
        )
    }

    private static func aHeldRecordingKeepsTheLongerCopyOfItsAudio() throws {
        let take = [Float](repeating: 0.1, count: 16_000 * 120)
        try expect(
            Policy.heldRecordingSamples(held: [], late: take) == take,
            "a hold whose stop drained nothing adopts the late copy"
        )
        try expect(
            Policy.heldRecordingSamples(held: take, late: []) == take,
            "an empty late copy never replaces the held audio"
        )
        let shorter = Array(take.prefix(8_000))
        try expect(
            Policy.heldRecordingSamples(held: shorter, late: take) == take,
            "the longer copy wins"
        )
        try expect(
            Policy.heldRecordingSamples(held: take, late: shorter) == take,
            "the held copy stays when it is the longer"
        )
    }

    // MARK: - Local fallback

    private static let parakeetLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    /// The catalog's local models in its order, with what is installed.
    private static func catalog(installed: Set<String>) -> [Policy.LocalCandidate] {
        let models: [(id: String, codes: Set<String>?, sizeMB: Int, pickable: Bool)] = [
            ("parakeet-tdt-v3", parakeetLanguages, 470, true),
            ("whisper-large-v3-turbo", nil, 632, true),
            ("whisper-large-v3", nil, 626, true),
            ("whisper-small", nil, 244, true),
            ("whisper-base", nil, 77, false),
            ("whisper-tiny", nil, 39, false),
        ]
        return models.map {
            Policy.LocalCandidate(
                id: $0.id,
                isInstalled: installed.contains($0.id),
                languageCodes: $0.codes,
                sizeMB: $0.sizeMB,
                autoPickable: $0.pickable
            )
        }
    }

    private static let cloudModel = "openai-gpt-transcribe"

    private static func fallback(
        installed: Set<String>,
        spoken: Set<String>,
        primary: String? = nil,
        canDownload: Bool = true,
        failed: String = cloudModel
    ) -> Policy.LocalFallback? {
        Policy.localFallback(
            candidates: catalog(installed: installed),
            failedModelID: failed,
            spokenLanguages: spoken,
            primaryLanguage: primary,
            canDownload: canDownload
        )
    }

    private static func anInstalledModelThatKnowsTheLanguagesComesFirst() throws {
        try expect(
            fallback(installed: ["whisper-small", "parakeet-tdt-v3"], spoken: ["en", "ru"])
                == .ready(id: "parakeet-tdt-v3", coversLanguages: true),
            "an installed Parakeet covers {en, ru} and wins, in catalog order"
        )
        try expect(
            fallback(installed: ["whisper-small"], spoken: ["en", "ru"])
                == .ready(id: "whisper-small", coversLanguages: true),
            "an installed model that covers the languages beats downloading a better one"
        )
        try expect(
            fallback(installed: ["parakeet-tdt-v3", "whisper-large-v3"], spoken: ["ja", "en"])
                == .ready(id: "whisper-large-v3", coversLanguages: true),
            "{ja, en} skips an installed Parakeet for an installed Whisper"
        )
        try expect(
            fallback(installed: ["parakeet-tdt-v3"], spoken: [])
                == .ready(id: "parakeet-tdt-v3", coversLanguages: true),
            "knowing nothing about the user's languages counts as covered"
        )
    }

    private static func onlineTheFirstModelThatKnowsTheLanguagesIsDownloaded() throws {
        try expect(
            fallback(installed: [], spoken: ["en", "ru"]) == .download(id: "parakeet-tdt-v3", sizeMB: 470),
            "{en, ru} with nothing installed downloads Parakeet"
        )
        try expect(
            fallback(installed: [], spoken: ["ja", "en"]) == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "{ja, en} with nothing installed downloads Whisper Large v3 Turbo"
        )
        try expect(
            fallback(installed: ["parakeet-tdt-v3"], spoken: ["ja", "en"])
                == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "online, a download that knows Japanese beats an installed Parakeet that doesn't"
        )
        try expect(
            fallback(installed: ["whisper-tiny"], spoken: ["en"]) == .download(id: "parakeet-tdt-v3", sizeMB: 470),
            "online, Tiny on disk doesn't stop a proper model being offered"
        )
    }

    private static func offlineAModelThatDoesntKnowTheLanguagesIsStillOffered() throws {
        try expect(
            fallback(installed: ["parakeet-tdt-v3"], spoken: ["ja"], canDownload: false)
                == .ready(id: "parakeet-tdt-v3", coversLanguages: false),
            "offline, an installed Parakeet is offered for Japanese, flagged as not covering it"
        )
    }

    /// A set guessed from the Mac's settings — English menus, Armenian and
    /// Russian keyboards — is sure only of English. An installed Parakeet
    /// knows English, so it is offered at once rather than a 632 MB download.
    private static func aGuessKeepsAModelHereThatKnowsItsPrimaryLanguage() throws {
        try expect(
            fallback(installed: ["parakeet-tdt-v3"], spoken: ["en", "hy", "ru"], primary: "en")
                == .ready(id: "parakeet-tdt-v3", coversLanguages: false),
            "{en, hy, ru} guessed, English first, Parakeet installed: Parakeet now, flagged as not covering Armenian"
        )
        try expect(
            fallback(installed: ["parakeet-tdt-v3"], spoken: ["en", "hy", "ru"])
                == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "the same languages read from what the user dictates still fetch the model that knows them all"
        )
        try expect(
            fallback(installed: ["parakeet-tdt-v3"], spoken: ["hy", "en"], primary: "hy")
                == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "a primary language the model here doesn't know is no reason to keep it"
        )
        try expect(
            fallback(installed: ["whisper-tiny"], spoken: ["en", "hy"], primary: "en")
                == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "Tiny is never what the primary language is kept on"
        )
        try expect(
            fallback(installed: ["parakeet-tdt-v3", "whisper-small"], spoken: ["en", "hy"], primary: "en")
                == .ready(id: "whisper-small", coversLanguages: true),
            "a model here that knows every language still comes first"
        )
        try expect(
            fallback(installed: [], spoken: ["en", "hy"], primary: "en")
                == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "with nothing installed, the guess downloads what covers it"
        )
    }

    private static func baseAndTinyAreOnlyOfferedWhenTheyAreAllThereIs() throws {
        try expect(
            fallback(installed: ["whisper-tiny"], spoken: ["en"], canDownload: false)
                == .ready(id: "whisper-tiny", coversLanguages: true),
            "offline with only Tiny installed, Tiny beats nothing"
        )
        try expect(
            fallback(installed: ["whisper-base", "whisper-tiny"], spoken: ["ja"], canDownload: false)
                == .ready(id: "whisper-base", coversLanguages: true),
            "with only Base and Tiny, the catalog's order picks Base"
        )
        try expect(
            fallback(installed: ["whisper-tiny", "parakeet-tdt-v3"], spoken: ["ja"], canDownload: false)
                == .ready(id: "parakeet-tdt-v3", coversLanguages: false),
            "any auto-pickable model on disk is offered before Tiny"
        )
        for spoken in [Set<String>(), ["en"], ["ja"]] {
            let picked = fallback(installed: [], spoken: spoken)?.modelID
            try expect(
                picked != "whisper-tiny" && picked != "whisper-base",
                "Base and Tiny are never downloaded on the user's behalf (\(spoken))"
            )
        }
    }

    private static func theFailedModelIsNeverOfferedAgain() throws {
        try expect(
            fallback(installed: ["parakeet-tdt-v3", "whisper-small"], spoken: ["en"], failed: "parakeet-tdt-v3")
                == .ready(id: "whisper-small", coversLanguages: true),
            "the model that just failed is skipped when installed"
        )
        try expect(
            fallback(installed: [], spoken: ["en"], failed: "parakeet-tdt-v3")
                == .download(id: "whisper-large-v3-turbo", sizeMB: 632),
            "and never offered as a download either"
        )
        try expect(
            fallback(installed: ["whisper-tiny"], spoken: ["en"], canDownload: false, failed: "whisper-tiny") == nil,
            "nor as the last model standing"
        )
    }

    private static func nothingInstalledAndOfflineOffersNothing() throws {
        try expect(
            fallback(installed: [], spoken: ["en"], canDownload: false) == nil,
            "offline with nothing installed there is no fallback"
        )
    }

    // MARK: - Failure card

    private static let ready = Policy.LocalFallback.ready(id: "parakeet-tdt-v3", coversLanguages: true)
    private static let download = Policy.LocalFallback.download(id: "whisper-large-v3-turbo", sizeMB: 632)

    private static func card(
        _ failure: TranscriptionFailure,
        _ local: Policy.LocalFallback?,
        repeat isRepeat: Bool = false
    ) -> (primary: Policy.CardAction, secondary: Policy.CardAction?) {
        Policy.failureCard(failure: failure, local: { local }, isRepeatRefusal: isRepeat)
    }

    private static func aFirstOutOfCreditRefusalLeadsWithTheMac() throws {
        let onMac = card(.quotaExhausted, ready)
        try expect(onMac.primary == .transcribeOnMac(id: "parakeet-tdt-v3"), "an installed model leads, on Return")
        try expect(onMac.secondary == .retryCloud, "Retry <provider> stays beside it")

        let fetch = card(.quotaExhausted, download)
        try expect(
            fetch.primary == .downloadAndTranscribe(id: "whisper-large-v3-turbo", sizeMB: 632),
            "a model to download leads as Download & Transcribe"
        )
        try expect(fetch.secondary == .retryCloud, "with Retry <provider> beside it")

        let partial = card(.quotaExhausted, .ready(id: "parakeet-tdt-v3", coversLanguages: false))
        try expect(
            partial.primary == .transcribeOnMac(id: "parakeet-tdt-v3"),
            "a model that doesn't cover every language still leads when it is the one on offer"
        )
    }

    private static func aRepeatRefusalOffersTheLastingSwitch() throws {
        let onMac = card(.quotaExhausted, ready, repeat: true)
        try expect(onMac.primary == .transcribeOnMac(id: "parakeet-tdt-v3"), "a repeat refusal keeps the same primary")
        try expect(
            onMac.secondary == .useForDictation(id: "parakeet-tdt-v3"),
            "and offers to make it the dictation model in place of Retry"
        )
        let fetch = card(.quotaExhausted, download, repeat: true)
        try expect(
            fetch.primary == .downloadAndTranscribe(id: "whisper-large-v3-turbo", sizeMB: 632)
                && fetch.secondary == .useForDictation(id: "whisper-large-v3-turbo"),
            "a repeat refusal with a download on offer switches to that model"
        )
    }

    private static func outOfCreditWithNothingToFallBackToOpensSettings() throws {
        for isRepeat in [false, true] {
            let none = card(.quotaExhausted, nil, repeat: isRepeat)
            try expect(none.primary == .retry, "with no model to fall back to, Retry leads (repeat: \(isRepeat))")
            try expect(none.secondary == .chooseModel, "and Choose Model opens Settings (repeat: \(isRepeat))")
        }
    }

    private static func offlineLeadsWithAnInstalledModelAndNeverADownload() throws {
        let onMac = card(.offline, ready)
        try expect(onMac.primary == .transcribeOnMac(id: "parakeet-tdt-v3"), "offline, an installed model leads")
        try expect(onMac.secondary == .retryCloud, "with Retry <provider> beside it")

        let fetch = card(.offline, download)
        try expect(fetch.primary == .retry && fetch.secondary == nil, "offline never offers a download")

        let none = card(.offline, nil)
        try expect(none.primary == .retry, "offline with nothing installed: Retry")
        try expect(none.secondary == nil, "and no Choose Model leading to a download that can't work")

        let repeated = card(.offline, ready, repeat: true)
        try expect(repeated.secondary == .retryCloud, "offline isn't a refusal; a stale flag changes nothing")
    }

    private static func aRefusedKeyStillPointsAtTheKey() throws {
        let refused = card(.unauthorized, ready)
        try expect(refused.primary == .retry, "a refused key keeps Retry for after it's fixed")
        try expect(refused.secondary == .checkAPIKey, "beside Check API Key")
    }

    private static func otherFailuresOfferNothingAndWalkNoFolders() throws {
        let failures: [TranscriptionFailure] = [.unauthorized, .rateLimited(retryAfter: 20), .server, .other]
        for failure in failures {
            var walked = false
            let actions = Policy.failureCard(failure: failure, local: {
                walked = true
                return ready
            }, isRepeatRefusal: true)
            try expect(actions.primary == .retry, "\(failure) leads with Retry")
            if failure != .unauthorized {
                try expect(actions.secondary == nil, "\(failure) offers no second button")
            }
            try expect(!walked, "\(failure) never walks the model folders")
        }
    }

    /// Review: "Use Parakeet" pinned every later Retry to Parakeet, even after
    /// it failed to prepare and the user picked Whisper in Settings.
    private static func aChosenRetryModelLastsOnlyWhileTheDictationModelDoes() throws {
        try expect(
            Policy.keepsRetryModelOverride(chosenOverModelID: "openai-gpt-transcribe", activeModelID: "openai-gpt-transcribe"),
            "with the dictation model unchanged, Retry stays on the model the card chose"
        )
        try expect(
            !Policy.keepsRetryModelOverride(chosenOverModelID: "openai-gpt-transcribe", activeModelID: "whisper-large-v3-turbo"),
            "a dictation model picked since then is the one Retry runs"
        )
        try expect(
            !Policy.keepsRetryModelOverride(chosenOverModelID: nil, activeModelID: "parakeet"),
            "a dictation model set where there was none also wins"
        )
    }
}
