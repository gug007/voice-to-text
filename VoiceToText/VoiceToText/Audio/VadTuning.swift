import Foundation

// UserDefaults keys exposed to settings-ui:
//   vad.energyThresholdDBFS  – Double (default -45.0)
//   vad.energyVoicedRatio    – Double (default 0.30)
//   vad.sileroVoicedRatio    – Double (default 0.25)

struct VadTuning {
    var energyThresholdDBFS: Float
    var energyVoicedRatio: Float
    var sileroVoicedRatio: Float

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

        return VadTuning(
            energyThresholdDBFS: energyThreshold,
            energyVoicedRatio: energyRatio,
            sileroVoicedRatio: sileroRatio
        )
    }
}
