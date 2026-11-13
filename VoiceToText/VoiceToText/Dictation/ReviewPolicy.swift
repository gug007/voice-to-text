import Foundation

/// Settings → Review before pasting: which finished takes open the review
/// card and which paste straight away.
nonisolated enum ReviewMode: String, CaseIterable, Identifiable, Sendable {
    case always
    case longTakes
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always"
        case .longTakes: return "Long takes"
        case .never: return "Never"
        }
    }
}

/// Whether a finished take opens the review card. `review.mode` replaced the
/// Bool `review.beforePaste`, which is still derived from and kept for older builds.
nonisolated enum ReviewPolicy {
    static let modeKey = "review.mode"
    static let legacyKey = "review.beforePaste"
    /// Unexposed override for `defaultLongTakeSeconds`.
    static let longTakeSecondsKey = "review.longTakeSeconds"
    /// "Long takes" are recordings longer than this. Past a sentence or two
    /// a transcript is worth a glance before it lands; below it, the review
    /// step costs more than it catches.
    static let defaultLongTakeSeconds: TimeInterval = 15

    /// The mode a stored `review.mode` names, or — while there is none — the
    /// one the old `review.beforePaste` Bool implies. An unreadable stored
    /// value falls back the same way.
    static func mode(storedMode: String?, legacyBeforePaste: Bool?) -> ReviewMode {
        if let storedMode, let mode = ReviewMode(rawValue: storedMode) { return mode }
        return legacyBeforePaste == false ? .never : .always
    }

    static func mode(in defaults: UserDefaults) -> ReviewMode {
        mode(
            storedMode: defaults.string(forKey: modeKey),
            legacyBeforePaste: defaults.object(forKey: legacyKey) as? Bool
        )
    }

    /// The threshold, honouring the override when it is a positive number.
    static func longTakeSeconds(override: Double?) -> TimeInterval {
        guard let override, override.isFinite, override > 0 else { return defaultLongTakeSeconds }
        return override
    }

    static func longTakeSeconds(in defaults: UserDefaults) -> TimeInterval {
        longTakeSeconds(override: defaults.object(forKey: longTakeSecondsKey) as? Double)
    }

    /// Whether a new take opens the review card. A take exactly
    /// `longTakeSeconds` long is not a long one.
    static func opensReview(
        mode: ReviewMode,
        takeSeconds: TimeInterval,
        longTakeSeconds: TimeInterval
    ) -> Bool {
        switch mode {
        case .always: return true
        case .longTakes: return takeSeconds > longTakeSeconds
        case .never: return false
        }
    }

    static func opensReview(takeSeconds: TimeInterval, in defaults: UserDefaults) -> Bool {
        opensReview(
            mode: mode(in: defaults),
            takeSeconds: takeSeconds,
            longTakeSeconds: longTakeSeconds(in: defaults)
        )
    }

    /// What Settings writes when the user picks `mode`: the new key, and the
    /// old Bool to match, for a build that only knows the old one.
    static func values(for mode: ReviewMode) -> (mode: String, legacyBeforePaste: Bool) {
        (mode.rawValue, mode != .never)
    }
}
