import Foundation

/// Word-level longest-common-subsequence merge for overlapping Whisper chunk outputs.
enum TranscriptMerge {

    /// Appends `newChunk` to `existing`, removing words duplicated in the overlap window.
    static func merge(existing: String, newChunk: String, overlapWords: Int) -> String {
        guard !newChunk.isEmpty else { return existing }
        guard !existing.isEmpty else { return newChunk }

        let existingWords = existing.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let newWords      = newChunk.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        // Tail of existing transcript to compare against the head of the new chunk.
        let tailCount  = min(overlapWords, existingWords.count)
        let headCount  = min(overlapWords, newWords.count)
        let tail = Array(existingWords.suffix(tailCount))
        let head = Array(newWords.prefix(headCount))

        // LCS length table over tail vs head.
        var dp = Array(repeating: Array(repeating: 0, count: head.count + 1), count: tail.count + 1)
        for i in 1...tail.count {
            for j in 1...head.count {
                if tail[i - 1].lowercased() == head[j - 1].lowercased() {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        let lcsLen = dp[tail.count][head.count]

        // Find the longest suffix of `tail` that matches a prefix of `head` via LCS alignment.
        // Simple heuristic: find the best contiguous overlap using the LCS length as a budget.
        var bestOverlapInNew = 0
        outer: for overlapLen in stride(from: min(lcsLen, head.count), through: 1, by: -1) {
            let candidate = Array(head.prefix(overlapLen))
            let tailSuffix = Array(tail.suffix(overlapLen))
            var matched = 0
            for (a, b) in zip(tailSuffix, candidate) where a.lowercased() == b.lowercased() {
                matched += 1
            }
            if Float(matched) / Float(overlapLen) >= 0.6 {
                bestOverlapInNew = overlapLen
                break outer
            }
        }

        let suffix = Array(newWords.dropFirst(bestOverlapInNew))
        if suffix.isEmpty { return existing }
        return (existingWords + suffix).joined(separator: " ")
    }
}
