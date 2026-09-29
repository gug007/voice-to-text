import Foundation

/// Keeps a chunk of a long recording that came back empty from vanishing out
/// of its transcript without a trace.
///
/// A chunk after the first carries the tail of the previous one as a context
/// prompt, and a prompted Whisper decode can end before it starts (an
/// end-of-text sampled during the prompt prefill), returning nothing for ten
/// minutes of speech. The joiner dropped the empty piece, so the transcript
/// read as if the conversation had simply skipped ahead. Such a chunk is tried
/// once more without the prompt; if it is still empty over speech energy, the
/// transcript says so where the text is missing.
///
/// Foundation-only so the harness can pin the rules.
nonisolated enum MeetingChunkRecovery {
    /// Only a prompted chunk can hit the prefill failure, and only speech is
    /// worth a second decode: an unprompted pass over silence is where Whisper
    /// invents lines.
    static func shouldRetryWithoutContext(text: String, contextPrompt: String?, hasSpeech: Bool) -> Bool {
        guard isBlank(text), let contextPrompt, !isBlank(contextPrompt) else { return false }
        return hasSpeech
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "[untranscribed 12:30–14:10]", times from the start of the recording.
    static func marker(for span: ClosedRange<Double>) -> String {
        "[untranscribed \(clock(span.lowerBound))–\(clock(span.upperBound))]"
    }

    /// `pieces` with each empty piece that had speech in it (`gaps`, aligned
    /// with `pieces`) spelled out as a marker. Only when some other piece has
    /// text: a recording where nothing transcribed stays empty, so the
    /// caller's "no speech detected" handling still applies to it.
    static func fillingGaps(_ pieces: [String], gaps: [ClosedRange<Double>?]) -> [String] {
        guard pieces.contains(where: { !isBlank($0) }) else { return pieces }
        return pieces.enumerated().map { index, piece in
            guard isBlank(piece), index < gaps.count, let gap = gaps[index] else { return piece }
            return marker(for: gap)
        }
    }

    /// Matches `formattedClock`: "12:05" under an hour, "1:02:33" past it.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
