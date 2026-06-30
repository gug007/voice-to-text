import Foundation

/// Joins the per-chunk transcripts of a long recording back into one string.
/// Pure and dependency-free so it can be unit-tested standalone (see
/// `Tests/RecordingHistoryHarness.swift`). Trims each piece and drops empties so
/// a silent chunk doesn't introduce stray whitespace.
nonisolated enum MeetingTranscriptJoiner {
    static func join(_ pieces: [String]) -> String {
        pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
