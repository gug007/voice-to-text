import Foundation
import SwiftUI

// `HistorySearch.highlighted` paints hits with the app's palette; the harness
// only needs the two tokens it names.
enum Palette {
    static let accent = Color.accentColor
    static let ink = Color.primary
}

struct HistorySearchHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw HistorySearchHarnessFailure(description: message)
    }
}

private func entry(
    transcript: String,
    status: RecordingHistoryEntry.Status? = nil
) -> RecordingHistoryEntry {
    let id = UUID()
    return RecordingHistoryEntry(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        transcript: transcript,
        audioFileName: "\(id.uuidString).wav",
        durationSeconds: 12,
        sampleRate: 16_000,
        modelId: "gpt-4o-transcribe",
        modelName: "GPT-4o Transcribe",
        source: .dictation,
        status: status
    )
}

private let placeholder = "⚠︎ Audio saved without a transcript."

/// History search over the rows a failed take leaves behind: they hold a
/// placeholder, not words, so what they can be found by is what their row
/// says went wrong.
@main
struct HistorySearchHarness {
    static func main() throws {
        try failedRowsAreFoundByTheirReason()
        try anEmptyBalanceAnswersToItsUsualNames()
        try transcribedRowsDontMatchFailureWords()
        try legacyPlaceholderRowsReadAsNotTranscribed()
        print("History search harness passed")
    }

    private static func failedRowsAreFoundByTheirReason() throws {
        let key = entry(
            transcript: placeholder,
            status: .init(kind: .failed, message: "OpenAI didn't accept your API key.")
        )
        for query in ["not transcribed", "Not Transcribed", "failed", "API key", "openai accept"] {
            try expect(!HistorySearch.filter([key], query: query).isEmpty, "\"\(query)\" finds a row the key failed")
        }
        try expect(HistorySearch.filter([key], query: "quota").isEmpty, "a refused key isn't an empty balance")
    }

    private static func anEmptyBalanceAnswersToItsUsualNames() throws {
        let broke = entry(
            transcript: placeholder,
            status: .init(
                kind: .failed,
                message: "OpenAI says your account is out of credit. Top up, or transcribe with a model on this Mac."
            )
        )
        for query in ["quota", "billing", "credit", "balance", "top up", "not transcribed"] {
            try expect(!HistorySearch.filter([broke], query: query).isEmpty, "\"\(query)\" finds the empty-balance row")
        }
        let raw = entry(
            transcript: placeholder,
            status: .init(
                kind: .failed,
                message: "Transcription failed: OpenAI refused the session (quota exceeded: You exceeded your current quota.)."
            )
        )
        try expect(!HistorySearch.filter([raw], query: "quota failed").isEmpty, "the provider's own words match too")
    }

    /// Conversations archived before `status` existed, and recovered orphans,
    /// carry only a placeholder. They are just as untranscribed, so they get
    /// the row's generic reason and answer to the same words.
    private static func legacyPlaceholderRowsReadAsNotTranscribed() throws {
        let legacy = [
            entry(transcript: placeholder),
            entry(transcript: RecordingHistoryEntry.legacyRecoveredTranscript),
        ]
        for row in legacy {
            try expect(HistorySearch.untranscribedStatus(of: row)?.message == HistorySearch.savedWithoutTranscriptReason,
                       "a placeholder row with no status gets the generic reason")
            for query in ["not transcribed", "saved without a transcript"] {
                try expect(!HistorySearch.filter([row], query: query).isEmpty, "\"\(query)\" finds a legacy placeholder row")
            }
        }
        let failed = entry(
            transcript: placeholder,
            status: .init(kind: .failed, message: "OpenAI didn't accept your API key.")
        )
        try expect(HistorySearch.untranscribedStatus(of: failed)?.message == "OpenAI didn't accept your API key.",
                   "a row with its own status keeps its reason")
        try expect(HistorySearch.untranscribedStatus(of: entry(transcript: "Send the invoice.")) == nil,
                   "a transcribed row has no status to show")
    }

    private static func transcribedRowsDontMatchFailureWords() throws {
        let fine = entry(transcript: "Send the invoice to Kara by Friday.")
        try expect(HistorySearch.filter([fine], query: "not transcribed").isEmpty, "a transcribed row isn't a failed one")
        try expect(HistorySearch.filter([fine], query: "failed").isEmpty, "nor does it say failed")
        try expect(!HistorySearch.filter([fine], query: "kara invoice").isEmpty, "and is still found by its words")
        try expect(HistorySearch.statusFields(of: .init(kind: .failed, message: "OpenAI didn't accept your API key.")).count == 3,
                   "no balance words for a reason that names no balance")
    }
}
