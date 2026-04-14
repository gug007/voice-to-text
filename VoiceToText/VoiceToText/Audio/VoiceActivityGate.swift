import FluidAudio
import Foundation

/// Shared VAD gate used by the live transcription loop and stop-time tail.
/// Wraps FluidAudio's Silero-backed `VadManager` with a lazy async init and
/// an `EnergyVAD` fallback if the model fails to load (offline, etc.).
actor VoiceActivityGate {
    static let shared = VoiceActivityGate()

    private var manager: VadManager?
    private var loadFailed = false
    private let fallback = EnergyVAD()

    private init() {}

    /// Best-effort: call at app startup to warm the model download/load.
    func prewarm() async {
        _ = await ensureManager()
    }

    func isVoiced(_ samples: [Float]) async -> Bool {
        let tuning = VadTuning.current
        if let manager = await ensureManager() {
            do {
                let results = try await manager.process(samples)
                guard !results.isEmpty else { return false }
                let voicedCount = results.reduce(0) { $0 + ($1.isVoiceActive ? 1 : 0) }
                let ratio = Float(voicedCount) / Float(results.count)
                return ratio >= tuning.sileroVoicedRatio
            } catch {
                // Fall through to energy VAD on any runtime failure.
            }
        }
        return fallback.isVoiced(samples[...], sampleRate: Int(AudioConfig.targetSampleRate))
    }

    private func ensureManager() async -> VadManager? {
        if let manager { return manager }
        if loadFailed { return nil }
        do {
            let m = try await VadManager()
            manager = m
            return m
        } catch {
            loadFailed = true
            return nil
        }
    }
}
