import Foundation

struct MeetingChunkRecoveryHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw MeetingChunkRecoveryHarnessFailure(description: message)
    }
}

private let rate = 16_000

/// `seconds` of silence with a 440 Hz tone at `amplitude` over `toneRange`.
private func signal(seconds: Double, tone toneRange: Range<Double>? = nil, amplitude: Float = 0.3) -> [Float] {
    var samples = [Float](repeating: 0, count: Int(seconds * Double(rate)))
    guard let toneRange else { return samples }
    let start = Int(toneRange.lowerBound * Double(rate))
    let end = min(samples.count, Int(toneRange.upperBound * Double(rate)))
    for index in start..<end {
        samples[index] = amplitude * sin(2 * .pi * 440 * Float(index) / Float(rate))
    }
    return samples
}

@main
struct MeetingChunkRecoveryHarness {
    static func main() throws {
        try retriesOnlyPromptedEmptySpeech()
        try markerReadsAsClockRange()
        try fillsGapsOnlyAroundRealText()
        try voicedSpanFollowsWindows()
        try energyVADFindsSpeechAndIgnoresSilence()
        try coughInQuietIsNotSpeech()
        print("Meeting chunk recovery harness passed")
    }

    private static func retriesOnlyPromptedEmptySpeech() throws {
        typealias R = MeetingChunkRecovery
        try expect(R.shouldRetryWithoutContext(text: "", contextPrompt: "…and that's the plan.", hasSpeech: true),
                   "an empty chunk that carried context over speech is retried without it")
        try expect(!R.shouldRetryWithoutContext(text: "Next item.", contextPrompt: "plan.", hasSpeech: true),
                   "a chunk with text is kept")
        try expect(!R.shouldRetryWithoutContext(text: "", contextPrompt: nil, hasSpeech: true),
                   "the first chunk had no context to blame")
        try expect(!R.shouldRetryWithoutContext(text: "", contextPrompt: "  ", hasSpeech: true),
                   "a blank context (after an empty chunk) isn't a prompt")
        try expect(!R.shouldRetryWithoutContext(text: " \n", contextPrompt: "plan.", hasSpeech: false),
                   "silence isn't decoded twice — an unprompted pass over it invites a hallucination")
    }

    private static func markerReadsAsClockRange() throws {
        try expect(MeetingChunkRecovery.marker(for: 750...850) == "[untranscribed 12:30–14:10]",
                   "minutes:seconds under an hour, en dash: \(MeetingChunkRecovery.marker(for: 750...850))")
        try expect(MeetingChunkRecovery.marker(for: 3_599.6...3_725) == "[untranscribed 1:00:00–1:02:05]",
                   "hours past an hour, rounded to the second")
        try expect(MeetingChunkRecovery.clock(5) == "0:05", "short times keep a leading minute")
    }

    private static func fillsGapsOnlyAroundRealText() throws {
        let pieces = ["First part.", "", "Third part.", ""]
        let gaps: [ClosedRange<Double>?] = [nil, 600...1_195, nil, nil]
        let filled = MeetingChunkRecovery.fillingGaps(pieces, gaps: gaps)
        try expect(filled == ["First part.", "[untranscribed 10:00–19:55]", "Third part.", ""],
                   "an empty voiced piece becomes a marker; an empty silent one stays empty: \(filled)")

        let allEmpty = MeetingChunkRecovery.fillingGaps(["", " "], gaps: [0...600, 600...900])
        try expect(allEmpty == ["", " "],
                   "nothing transcribed at all stays empty, so the caller still reports no speech")

        let textWithGap = MeetingChunkRecovery.fillingGaps(["Hello.", "Again."], gaps: [0...5, nil])
        try expect(textWithGap == ["Hello.", "Again."], "a gap never overwrites text")

        let short = MeetingChunkRecovery.fillingGaps(["Hello.", ""], gaps: [nil])
        try expect(short == ["Hello.", ""], "a missing gap entry is treated as no speech")
    }

    private static func voicedSpanFollowsWindows() throws {
        let samples = [Float](repeating: 0, count: rate * 30)
        let window = Int(SpeechEnergy.windowSeconds) * rate
        // Windows 2 and 4 (10–15 s, 20–25 s) are "voiced".
        let span = SpeechEnergy.voicedSpan(in: samples, sampleRate: rate) { slice in
            let index = (slice.startIndex / window)
            return index == 2 || index == 4
        }
        try expect(span == 10...25, "first voiced window's start to last voiced window's end: \(String(describing: span))")

        let none = SpeechEnergy.voicedSpan(in: samples, sampleRate: rate) { _ in false }
        try expect(none == nil, "no voiced window, no span")
        try expect(SpeechEnergy.voicedSpan(in: [], sampleRate: rate) { _ in true } == nil, "empty audio has no span")

        let ragged = [Float](repeating: 0, count: rate * 7)
        let tail = SpeechEnergy.voicedSpan(in: ragged, sampleRate: rate) { $0.count < window }
        try expect(tail == 5...7, "a short last window ends at the audio's end: \(String(describing: tail))")
    }

    private static func energyVADFindsSpeechAndIgnoresSilence() throws {
        try expect(SpeechEnergy.voicedSpan(in: signal(seconds: 30), sampleRate: rate) == nil,
                   "digital silence has no speech energy")
        try expect(SpeechEnergy.voicedSpan(in: signal(seconds: 30, tone: 0..<30, amplitude: 0.0005), sampleRate: rate) == nil,
                   "a -66 dBFS hum stays under the -45 dBFS threshold")
        let burst = SpeechEnergy.voicedSpan(in: signal(seconds: 30, tone: 11..<14), sampleRate: rate)
        try expect(burst == 10...15,
                   "a 3 s burst inside a long quiet chunk is found by its 5 s window: \(String(describing: burst))")
    }

    /// A window is voiced by a share of its frames, not by the dictation
    /// gate's absolute 0.4 s: a cough in a quiet room is not speech the model
    /// failed on, and marking it [untranscribed] — or re-decoding it without a
    /// prompt, inviting a hallucination — would be wrong.
    private static func coughInQuietIsNotSpeech() throws {
        let hum = signal(seconds: 30, tone: 0..<30, amplitude: 0.0014)  // ≈ -60 dBFS
        let cough = signal(seconds: 30, tone: 12..<12.45)
        let take = zip(hum, cough).map { $0 + $1 }
        try expect(SpeechEnergy.voicedSpan(in: take, sampleRate: rate) == nil,
                   "a 0.45 s cough in -60 dBFS noise leaves its 5 s window unvoiced")
        let window = take[(10 * rate)..<(15 * rate)]
        try expect(!EnergyVAD().isVoiced(window, sampleRate: rate), "the ratio test rejects the window")
        try expect(EnergyVAD().passesSpeechGate(window, sampleRate: rate),
                   "while the dictation gate, which judges a whole take by voiced time, would pass it")
    }
}
