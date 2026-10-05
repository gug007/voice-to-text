import Foundation

struct CloudCreditStatusHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CloudCreditStatusHarnessFailure(description: message)
    }
}

@main
struct CloudCreditStatusHarness {
    @MainActor
    static func main() throws {
        try onlyAnEmptyBalanceFlagsAProvider()
        try aRepeatIsOnlyARefusalFlaggedBeforeThisOne()
        try successClearsOnlyItsOwnProvider()
        try theFlagSurvivesARelaunch()
        try aKeyChangeClearsOnlyThatProvider()
        try aSwitchForDictationIsRememberedUntilCleared()
        print("Cloud credit status harness passed")
    }

    private static let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// A store on its own defaults suite and notification center, so the
    /// harness touches neither the app's settings nor another case's flags.
    @MainActor
    private static func freshStore(
        named name: String,
        center: NotificationCenter = NotificationCenter()
    ) -> (CloudCreditStatus, UserDefaults) {
        let suite = "CloudCreditStatusHarness.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CloudCreditStatus(defaults: defaults, notificationCenter: center), defaults)
    }

    private static func onlyAnEmptyBalanceFlagsAProvider() throws {
        var ledger = CloudCreditLedger()
        let others: [TranscriptionFailure] = [.offline, .unauthorized, .rateLimited(retryAfter: 5), .server, .other]
        for failure in others {
            let outcome = ledger.noteFailure(failure, from: .openAI, at: start)
            try expect(!outcome.changed && !outcome.isRepeatRefusal, "\(failure) says nothing about the balance")
        }
        try expect(!ledger.isOutOfCredit(.openAI), "no flag without a quota refusal")
        _ = ledger.noteFailure(.quotaExhausted, from: nil, at: start)
        try expect(ledger.outOfCreditSince.isEmpty, "a local model has no balance to flag")
        let first = ledger.noteFailure(.quotaExhausted, from: .openAI, at: start)
        try expect(first.changed && ledger.isOutOfCredit(.openAI), "a quota refusal flags the provider")
        try expect(!ledger.isOutOfCredit(.elevenLabs), "and only that provider")
        try expect(!ledger.isOutOfCredit(nil), "nil is never out of credit")
    }

    private static func aRepeatIsOnlyARefusalFlaggedBeforeThisOne() throws {
        var ledger = CloudCreditLedger()
        let first = ledger.noteFailure(.quotaExhausted, from: .openAI, at: start)
        try expect(!first.isRepeatRefusal, "the refusal that sets the flag isn't a repeat of itself")
        let second = ledger.noteFailure(.quotaExhausted, from: .openAI, at: start.addingTimeInterval(600))
        try expect(second.isRepeatRefusal && !second.changed, "the next refusal is a repeat")
        try expect(ledger.outOfCreditSince[.openAI] == start, "a repeat keeps the date of the first refusal")
        try expect(
            !ledger.noteFailure(.offline, from: .openAI, at: start).isRepeatRefusal,
            "an offline failure on a flagged provider isn't a refusal at all"
        )
        try expect(
            !ledger.noteFailure(.quotaExhausted, from: .elevenLabs, at: start).isRepeatRefusal,
            "another provider's first refusal is a first"
        )
    }

    private static func successClearsOnlyItsOwnProvider() throws {
        var ledger = CloudCreditLedger()
        _ = ledger.noteFailure(.quotaExhausted, from: .openAI, at: start)
        _ = ledger.noteFailure(.quotaExhausted, from: .elevenLabs, at: start)
        try expect(!ledger.noteSuccess(from: nil), "a local model's success clears nothing")
        try expect(ledger.noteSuccess(from: .openAI), "an OpenAI success clears OpenAI")
        try expect(!ledger.isOutOfCredit(.openAI), "OpenAI is clear")
        try expect(ledger.isOutOfCredit(.elevenLabs), "ElevenLabs is still flagged")
        try expect(!ledger.noteSuccess(from: .openAI), "a second success has nothing left to clear")
        try expect(
            !ledger.noteFailure(.quotaExhausted, from: .openAI, at: start).isRepeatRefusal,
            "after a success, the next refusal is a first again"
        )
    }

    @MainActor
    private static func theFlagSurvivesARelaunch() throws {
        let (store, defaults) = freshStore(named: "relaunch")
        try expect(!store.noteFailure(.quotaExhausted, provider: .openAI, at: start), "first refusal")
        try expect(
            defaults.object(forKey: "cloud.outOfCreditSince.openAI") as? Date == start,
            "persisted under cloud.outOfCreditSince.<provider>"
        )
        let relaunched = CloudCreditStatus(defaults: defaults, notificationCenter: NotificationCenter())
        try expect(relaunched.isOutOfCredit(.openAI), "the flag is read back on launch")
        try expect(relaunched.flaggedSince(.openAI) == start, "with its date")
        try expect(
            relaunched.noteFailure(.quotaExhausted, provider: .openAI),
            "a refusal after a relaunch is still a repeat"
        )
        relaunched.noteSuccess(provider: .openAI)
        try expect(defaults.object(forKey: "cloud.outOfCreditSince.openAI") == nil, "a success removes it")
    }

    @MainActor
    private static func aKeyChangeClearsOnlyThatProvider() throws {
        let center = NotificationCenter()
        let (store, defaults) = freshStore(named: "keys", center: center)
        store.noteFailure(.quotaExhausted, provider: .openAI, at: start)
        store.noteFailure(.quotaExhausted, provider: .elevenLabs, at: start)
        center.post(name: CloudProvider.elevenLabs.keyDidChangeNotification, object: nil)
        try expect(!store.isOutOfCredit(.elevenLabs), "a new ElevenLabs key clears ElevenLabs")
        try expect(defaults.object(forKey: "cloud.outOfCreditSince.elevenLabs") == nil, "and its saved flag")
        try expect(store.isOutOfCredit(.openAI), "but leaves OpenAI flagged")
        center.post(name: CloudProvider.openAI.keyDidChangeNotification, object: nil)
        try expect(store.outOfCreditSince.isEmpty, "a new OpenAI key clears OpenAI")
        try expect(
            CloudProvider.openAI.keyDidChangeNotification.rawValue == "OpenAIAPIKeyStore.didChange"
                && CloudProvider.elevenLabs.keyDidChangeNotification.rawValue == "ElevenLabsAPIKeyStore.didChange",
            "the notifications keep the names the key stores have always posted"
        )
    }

    @MainActor
    private static func aSwitchForDictationIsRememberedUntilCleared() throws {
        let (store, defaults) = freshStore(named: "switch")
        try expect(store.switchedFromModelId == nil, "no switch on a fresh install")
        store.noteSwitchedForDictation(from: "openai-gpt-transcribe")
        try expect(store.switchedFromModelId == "openai-gpt-transcribe", "Use for Dictation remembers the cloud model")
        try expect(
            defaults.string(forKey: "dictation.switchedFromModelId") == "openai-gpt-transcribe",
            "under dictation.switchedFromModelId"
        )
        let relaunched = CloudCreditStatus(defaults: defaults, notificationCenter: NotificationCenter())
        try expect(relaunched.switchedFromModelId == "openai-gpt-transcribe", "across a relaunch")
        relaunched.clearSwitchedFrom()
        try expect(relaunched.switchedFromModelId == nil, "picking a model forgets it")
        try expect(defaults.string(forKey: "dictation.switchedFromModelId") == nil, "on disk too")
    }
}
