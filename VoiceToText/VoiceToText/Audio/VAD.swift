import Foundation

/// Simple energy-based voice activity detector — the fallback while Silero
/// isn't loaded, and the speech check `SpeechEnergy` runs over transcription
/// chunks. No external dependencies — pure arithmetic over 30 ms RMS frames,
/// judged by the same `SpeechGate` rule as Silero's chunks. `nonisolated` so
/// the transcription paths can call it off the main actor.
nonisolated struct EnergyVAD {
    /// Returns true when enough frames exceed the dBFS threshold (see
    /// `SpeechGate` for what "enough" means).
    func isVoiced(_ samples: ArraySlice<Float>, sampleRate: Int) -> Bool {
        let tuning = VadTuning.current
        let frameLength = max(1, sampleRate * DictationConfig.vadFrameMs / 1_000)
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
}
