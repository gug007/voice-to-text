import FluidAudio
import Foundation
import OSLog

/// Shared VAD gate used by the live transcription loop and stop-time tail.
/// Wraps FluidAudio's Silero-backed `VadManager` with a lazy async init and
/// an `EnergyVAD` fallback while the model can't be loaded (offline, etc.).
/// The pass/fail rule itself lives in `SpeechGate`.
actor VoiceActivityGate {
    static let shared = VoiceActivityGate()

    private var manager: VadManager?
    /// The load in flight, shared by every caller that arrives while it runs.
    private var loadTask: Task<VadManager?, Never>?
    /// Consecutive failed loads; zero until the first one fails.
    private var failedLoads = 0
    private var nextLoadAttempt: Date = .distantPast
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
                // The threshold behind each result's `isVoiceActive` — what
                // the old ratio gate counted.
                let strictThreshold = await manager.config.defaultThreshold
                let verdict = SpeechGate.evaluate(
                    scores: results.map(\.probability),
                    unitSeconds: Double(VadManager.chunkSize) / Double(VadManager.sampleRate),
                    rule: SpeechGate.Rule(
                        speechThreshold: tuning.sileroSpeechThreshold,
                        minVoicedSeconds: tuning.minVoicedSeconds,
                        ratioThreshold: strictThreshold,
                        minVoicedRatio: tuning.sileroVoicedRatio
                    )
                )
                AppLog.dictation.info(
                    "Speech gate: \(verdict.isVoiced ? "voiced" : "silent", privacy: .public), \(verdict.voicedSeconds, format: .fixed(precision: 2))s voiced, ratio \(verdict.voicedRatio, format: .fixed(precision: 2)) over \(results.count) chunks"
                )
                return verdict.isVoiced
            } catch {
                // Fall through to energy VAD on any runtime failure.
            }
        }
        return fallback.passesSpeechGate(samples[...], sampleRate: Int(AudioConfig.targetSampleRate))
    }

    /// The loaded model, or nil while only the energy fallback is available.
    ///
    /// The first load is awaited, as it always was: at launch it is what
    /// `prewarm` is for, and a take that beats it waits for the real gate. A
    /// load that has failed is retried after `SpeechGate.sileroRetryDelay`,
    /// but in the background — a retry is a network download when the model
    /// isn't cached, and the stop-to-text path must not wait on one. The take
    /// that triggers it uses the fallback; the next one gets Silero.
    private func ensureManager() async -> VadManager? {
        if let manager { return manager }
        if let loadTask {
            return failedLoads == 0 ? await loadTask.value : nil
        }
        guard Date() >= nextLoadAttempt else { return nil }
        let task = Task { try? await VadManager() }
        loadTask = task
        guard failedLoads == 0 else {
            Task { await self.finishLoad(task) }
            return nil
        }
        return await finishLoad(task)
    }

    @discardableResult
    private func finishLoad(_ task: Task<VadManager?, Never>) async -> VadManager? {
        let loaded = await task.value
        // Only the first awaiter settles the outcome; everyone else who joined
        // the same load just reads it.
        guard loadTask == task else { return manager }
        loadTask = nil
        if let loaded {
            manager = loaded
            failedLoads = 0
        } else {
            failedLoads += 1
            let delay = SpeechGate.sileroRetryDelay(afterFailures: failedLoads)
            nextLoadAttempt = Date().addingTimeInterval(delay)
            AppLog.dictation.error("Silero VAD failed to load (\(self.failedLoads) in a row); using the energy gate, retrying in \(Int(delay))s")
        }
        return loaded
    }
}
