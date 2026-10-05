import Foundation
import Observation

/// Which cloud providers have refused a take for an empty balance, and since
/// when — the pure part of `CloudCreditStatus`, so a harness can walk it.
///
/// A flag is set by a refusal and cleared by the only two things that say the
/// balance may be back: a request to that provider that worked, or a new API
/// key. Never by a timer — the flag doesn't keep a single request from the
/// cloud (every take still tries it first), so a stale one costs nothing,
/// while one that expired on its own would forget a refusal the user is still
/// living with.
nonisolated struct CloudCreditLedger: Equatable, Sendable {
    private(set) var outOfCreditSince: [CloudProvider: Date] = [:]

    init(outOfCreditSince: [CloudProvider: Date] = [:]) {
        self.outOfCreditSince = outOfCreditSince
    }

    /// `UserDefaults` key holding the date `provider` was flagged.
    static func defaultsKey(for provider: CloudProvider) -> String {
        "cloud.outOfCreditSince.\(provider.rawValue)"
    }

    /// The flags as last saved.
    static func load(from defaults: UserDefaults) -> CloudCreditLedger {
        var since: [CloudProvider: Date] = [:]
        for provider in CloudProvider.allCases {
            if let date = defaults.object(forKey: defaultsKey(for: provider)) as? Date {
                since[provider] = date
            }
        }
        return CloudCreditLedger(outOfCreditSince: since)
    }

    /// Writes `provider`'s flag, or its absence.
    func save(_ provider: CloudProvider, to defaults: UserDefaults) {
        if let date = outOfCreditSince[provider] {
            defaults.set(date, forKey: Self.defaultsKey(for: provider))
        } else {
            defaults.removeObject(forKey: Self.defaultsKey(for: provider))
        }
    }

    func isOutOfCredit(_ provider: CloudProvider?) -> Bool {
        provider.map { outOfCreditSince[$0] != nil } ?? false
    }

    /// Takes in a failed request. Only an empty balance flags the provider;
    /// a dropped connection or a rate limit says nothing about the balance
    /// either way, and leaves the flag as it was.
    ///
    /// Returns whether this is a repeat refusal: the provider was already
    /// flagged before this failure. Read and marked in one step, so no caller
    /// can mark first and then mistake its own mark for an earlier one. A
    /// provider flagged again keeps the date it was first flagged.
    mutating func noteFailure(
        _ failure: TranscriptionFailure,
        from provider: CloudProvider?,
        at date: Date
    ) -> (isRepeatRefusal: Bool, changed: Bool) {
        guard failure == .quotaExhausted, let provider else { return (false, false) }
        if outOfCreditSince[provider] != nil { return (true, false) }
        outOfCreditSince[provider] = date
        return (false, true)
    }

    /// A request to `provider` worked, so its balance isn't empty. Returns
    /// whether that cleared a flag. nil — a local model — clears nothing.
    mutating func noteSuccess(from provider: CloudProvider?) -> Bool {
        guard let provider else { return false }
        return clear(provider)
    }

    /// Forgets `provider`'s flag: its API key changed, and the new one may
    /// well bill an account with credit. Returns whether there was one.
    mutating func clear(_ provider: CloudProvider) -> Bool {
        outOfCreditSince.removeValue(forKey: provider) != nil
    }
}

/// The app's memory of which cloud providers are out of credit, and of a
/// dictation model switched away from one.
///
/// Set where a take's transcription fails with `.quotaExhausted` — the
/// dictation pipeline and `TranscriptRegenerator` — and cleared where one
/// succeeds on a cloud model of that provider, or when its API key changes.
/// v1 leaves Meetings, Actions and Insights out of both. The failure card
/// reads it to tell a first refusal from a repeat one; History, the Models
/// pane and the Cloud pane read it to lead with the model on this Mac and to
/// say "Out of credit" where they would say "Connected". Persisted, so the
/// flag survives a relaunch: the balance doesn't refill on one.
@Observable
@MainActor
final class CloudCreditStatus {
    static let shared = CloudCreditStatus()

    /// `UserDefaults` key for `switchedFromModelId`.
    static let switchedFromDefaultsKey = "dictation.switchedFromModelId"

    private(set) var ledger: CloudCreditLedger

    /// The cloud model "Use for Dictation" switched the dictation model away
    /// from, while that switch stands: what the Models pane's "Switch Back"
    /// returns to. Cleared by any model picked in the Models pane, Switch
    /// Back included (`ModelRegistry.setActive`).
    private(set) var switchedFromModelId: String?

    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults` and `notificationCenter` are injectable for the harness;
    /// the app uses `shared`.
    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.ledger = CloudCreditLedger.load(from: defaults)
        self.switchedFromModelId = defaults.string(forKey: Self.switchedFromDefaultsKey)
        // The same notifications `ModelRegistry` refreshes readiness on. The
        // observers live as long as the store — for `shared`, the app.
        for provider in CloudProvider.allCases {
            notificationCenter.addObserver(
                forName: provider.keyDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyDidChange(for: provider) }
            }
        }
    }

    var outOfCreditSince: [CloudProvider: Date] { ledger.outOfCreditSince }

    /// Whether `provider` refused a take for an empty balance and nothing has
    /// worked since. False for nil (a local model).
    func isOutOfCredit(_ provider: CloudProvider?) -> Bool {
        ledger.isOutOfCredit(provider)
    }

    /// When `provider` was first flagged, if it is.
    func flaggedSince(_ provider: CloudProvider) -> Date? {
        ledger.outOfCreditSince[provider]
    }

    /// Takes in a failed transcription by a model of `provider` (nil for a
    /// local model) and returns `isRepeatRefusal` for the failure card: true
    /// when this is an empty-balance refusal and the provider was flagged
    /// *before* it. Call once per failure, with the failure already
    /// classified; any failure but `.quotaExhausted` changes nothing.
    @discardableResult
    func noteFailure(_ failure: TranscriptionFailure, provider: CloudProvider?, at date: Date = Date()) -> Bool {
        let outcome = ledger.noteFailure(failure, from: provider, at: date)
        if outcome.changed, let provider { ledger.save(provider, to: defaults) }
        return outcome.isRepeatRefusal
    }

    /// A transcription by a model of `provider` produced text: its balance
    /// isn't empty. Call for every success; nil (a local model) does nothing.
    func noteSuccess(provider: CloudProvider?) {
        guard ledger.noteSuccess(from: provider), let provider else { return }
        ledger.save(provider, to: defaults)
    }

    /// Remembers that "Use for Dictation" moved the dictation model off
    /// `cloudModelID`. Call right after `ModelRegistry.setActive`, which
    /// clears it (see `ModelRegistry.useForDictation`).
    func noteSwitchedForDictation(from cloudModelID: String) {
        switchedFromModelId = cloudModelID
        defaults.set(cloudModelID, forKey: Self.switchedFromDefaultsKey)
    }

    /// Forgets the switch: the user picked a model themselves.
    func clearSwitchedFrom() {
        guard switchedFromModelId != nil else { return }
        switchedFromModelId = nil
        defaults.removeObject(forKey: Self.switchedFromDefaultsKey)
    }

    private func keyDidChange(for provider: CloudProvider) {
        guard ledger.clear(provider) else { return }
        ledger.save(provider, to: defaults)
    }
}
