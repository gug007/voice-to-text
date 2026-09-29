import Foundation

// UserDefaults keys exposed to settings-ui:
//   vad.energyThresholdDBFS    – Double (default -45.0)  energy frame counts as voiced
//   vad.energyVoicedRatio      – Double (default 0.30)   energy ratio that also passes
//   vad.sileroVoicedRatio      – Double (default 0.25)   Silero ratio (at p ≥ 0.85) that also passes
//   vad.sileroSpeechThreshold  – Double (default 0.5)    Silero chunk counts toward voiced time
//   vad.minVoicedSeconds       – Double (default 0.4)    voiced time that passes a take
// See `SpeechGate` for how the two tests combine.

/// `nonisolated` because `VoiceActivityGate` and the transcription paths read
/// it off the main actor.
nonisolated struct VadTuning {
    var energyThresholdDBFS: Float
    var energyVoicedRatio: Float
    var sileroVoicedRatio: Float
    var sileroSpeechThreshold: Float
    var minVoicedSeconds: Double

    static var current: VadTuning {
        let ud = UserDefaults.standard

        let energyThreshold: Float
        if let raw = ud.object(forKey: "vad.energyThresholdDBFS") as? Double {
            energyThreshold = Float(raw)
        } else {
            energyThreshold = DictationConfig.vadThresholdDBFS
        }

        let energyRatio: Float
        if let raw = ud.object(forKey: "vad.energyVoicedRatio") as? Double {
            energyRatio = Float(raw)
        } else {
            energyRatio = DictationConfig.vadVoicedRatio
        }

        let sileroRatio: Float
        if let raw = ud.object(forKey: "vad.sileroVoicedRatio") as? Double {
            sileroRatio = Float(raw)
        } else {
            sileroRatio = DictationConfig.sileroVoicedRatio
        }

        let sileroSpeechThreshold: Float
        if let raw = ud.object(forKey: "vad.sileroSpeechThreshold") as? Double {
            sileroSpeechThreshold = Float(raw)
        } else {
            sileroSpeechThreshold = DictationConfig.sileroSpeechThreshold
        }

        let minVoicedSeconds: Double
        if let raw = ud.object(forKey: "vad.minVoicedSeconds") as? Double {
            minVoicedSeconds = raw
        } else {
            minVoicedSeconds = DictationConfig.minVoicedSeconds
        }

        return VadTuning(
            energyThresholdDBFS: energyThreshold,
            energyVoicedRatio: energyRatio,
            sileroVoicedRatio: sileroRatio,
            sileroSpeechThreshold: sileroSpeechThreshold,
            minVoicedSeconds: minVoicedSeconds
        )
    }
}
