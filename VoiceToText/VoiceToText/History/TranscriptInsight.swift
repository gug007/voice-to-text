import Foundation

/// The two AI-derived readings of a transcript a recording can carry. The
/// rawValues are persisted inside `RecordingHistoryEntry`, so they are part of
/// the on-disk format and must not be renamed.
///
/// `nonisolated` — like everything else in the history model — so the off-main
/// index IO, the pure generators and the test harness can all touch it while
/// the module defaults to MainActor isolation.
nonisolated enum InsightKind: String, Codable, Sendable, Hashable, CaseIterable {
    case summary
    case actionItems

    /// The tab label. Title case, because these read as proper section names
    /// next to "Transcript" in the row's segmented control.
    var displayName: String {
        switch self {
        case .summary: return "Summary"
        case .actionItems: return "Action Items"
        }
    }

    var symbolName: String {
        switch self {
        case .summary: return "text.alignleft"
        case .actionItems: return "checklist"
        }
    }
}

/// One thing somebody committed to do, as extracted from a transcript.
///
/// `owner` and `due` are optional on purpose: the model is instructed never to
/// invent either, so "nobody was named" and "no timing was given" are the
/// common, correct answers and the UI renders the item without them rather than
/// showing a guess.
nonisolated struct ActionItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    /// The person or group responsible, exactly as the transcript named them;
    /// nil when the transcript names nobody.
    let owner: String?
    /// When it is due, in the transcript's own words ("before Friday"). Free
    /// text rather than a `Date` — the transcript rarely says an actual date,
    /// and parsing one would be the app inventing a deadline.
    let due: String?
    /// Checked off by the user, not by the model. Persisted with the item, so
    /// the checklist survives relaunch.
    let isDone: Bool

    init(id: UUID = UUID(), text: String, owner: String? = nil, due: String? = nil, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.owner = owner
        self.due = due
        self.isDone = isDone
    }

    func marking(done: Bool) -> ActionItem {
        ActionItem(id: id, text: text, owner: owner, due: due, isDone: done)
    }
}

/// A generated summary plus the provenance needed to tell the user when it has
/// gone out of date.
nonisolated struct TranscriptSummary: Codable, Hashable, Sendable {
    let text: String
    let generatedAt: Date
    /// The OpenAI model that wrote it, kept verbatim so an older summary still
    /// says what produced it after the app's default model changes.
    let modelId: String?
    /// Digest of the transcript this was generated from. Regenerating the
    /// transcript leaves the summary in place but makes it *stale* — see
    /// `RecordingHistoryEntry.isStale(_:)`.
    let sourceDigest: String

    init(text: String, generatedAt: Date, modelId: String?, sourceDigest: String) {
        self.text = text
        self.generatedAt = generatedAt
        self.modelId = modelId
        self.sourceDigest = sourceDigest
    }
}

/// The extracted checklist for one recording, with the same provenance fields as
/// `TranscriptSummary` so both insights go stale on the same rule.
nonisolated struct TranscriptActionItems: Codable, Hashable, Sendable {
    let items: [ActionItem]
    let generatedAt: Date
    let modelId: String?
    let sourceDigest: String

    init(items: [ActionItem], generatedAt: Date, modelId: String?, sourceDigest: String) {
        self.items = items
        self.generatedAt = generatedAt
        self.modelId = modelId
        self.sourceDigest = sourceDigest
    }

    var doneCount: Int { items.reduce(0) { $0 + ($1.isDone ? 1 : 0) } }

    /// Flips one item's checkbox. An unknown id returns an identical value, so
    /// the store can compare-and-skip the write rather than persisting a no-op.
    func toggling(itemID: UUID) -> TranscriptActionItems {
        TranscriptActionItems(
            items: items.map { $0.id == itemID ? $0.marking(done: !$0.isDone) : $0 },
            generatedAt: generatedAt,
            modelId: modelId,
            sourceDigest: sourceDigest
        )
    }
}

/// Fingerprints a transcript so an insight can say which text it was generated
/// from.
///
/// FNV-1a rather than `String.hashValue`: Swift seeds its hasher per process, so
/// a stored `hashValue` would compare unequal on the very next launch and every
/// insight in history would read as stale forever. FNV-1a is stable across
/// launches, machines and OS versions, needs no CryptoKit (this file stays
/// Foundation-only for the harness), and is fine here — nothing about this is
/// adversarial, it only has to notice that the transcript changed.
nonisolated enum TranscriptDigest {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// Lowercase 16-character hex of the FNV-1a 64 hash of the UTF-8 bytes.
    static func of(_ text: String) -> String {
        var hash = offsetBasis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}
