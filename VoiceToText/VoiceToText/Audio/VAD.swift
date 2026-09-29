import Foundation

/// Simple energy-based voice activity detector — the fallback while Silero
/// isn't loaded, and the speech check `SpeechEnergy` runs over transcription
/// chunks. No external dependencies — pure arithmetic over 30 ms RMS frames.
/// `nonisolated` so the transcription paths can call it off the main actor.
nonisolated struct EnergyVAD {
    /// Returns true when enough energy frames exceed the dBFS threshold: a
    /// share of the buffer (`vad.energyVoicedRatio`), not an amount of time.
    /// That is what `SpeechEnergy` needs from its 5 s windows — a cough in a
    /// quiet window must not read as speech the model failed to transcribe.
    func isVoiced(_ samples: ArraySlice<Float>, sampleRate: Int) -> Bool {
        let tuning = VadTuning.current
        let levels = SpeechGate.frameLevels(samples, frameLength: Self.frameLength(sampleRate))
        guard !levels.isEmpty else { return false }
        let voiced = levels.reduce(0) { $0 + ($1 > tuning.energyThresholdDBFS ? 1 : 0) }
        return Float(voiced) / Float(levels.count) >= tuning.energyVoicedRatio
    }

    /// The dictation speech gate's verdict while Silero isn't loaded: the same
    /// frames judged by `SpeechGate`'s rule, which also passes a take on an
    /// absolute amount of voiced time — a whole take that is mostly pauses
    /// still holds the user's words. Only `VoiceActivityGate` asks this.
    func passesSpeechGate(_ samples: ArraySlice<Float>, sampleRate: Int) -> Bool {
        let tuning = VadTuning.current
        let frameLength = Self.frameLength(sampleRate)
        let rule = SpeechGate.Rule(
            speechThreshold: tuning.energyThresholdDBFS,
            minVoicedSeconds: tuning.minVoicedSeconds,
            ratioThreshold: tuning.energyThresholdDBFS,
            minVoicedRatio: tuning.energyVoicedRatio
        )
        return SpeechGate.evaluate(
            scores: SpeechGate.frameLevels(samples, frameLength: frameLength),
            unitSeconds: Double(frameLength) / Double(max(1, sampleRate)),
            rule: rule
        ).isVoiced
    }

    private static func frameLength(_ sampleRate: Int) -> Int {
        max(1, sampleRate * DictationConfig.vadFrameMs / 1_000)
    }
}
