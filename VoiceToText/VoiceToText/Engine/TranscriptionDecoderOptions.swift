import Foundation

// UserDefaults keys exposed to settings-ui:
//   decoder.language           – String? (e.g. "en"; nil = auto-detect)
//   decoder.initialPrompt      – String? (freeform context hint)
//   decoder.temperatureFallbackCount – Int (default 5)
//   decoder.compressionRatioThreshold – Float? (default 2.4)
//   decoder.logProbThreshold   – Float? (default -1.0)
//   decoder.suppressBlank      – Bool (default true)
//   decoder.withoutTimestamps  – Bool (default true)

struct TranscriptionDecoderOptions {
    var language: String?
    var initialPrompt: String?
    var temperatureFallbackCount: Int
    var compressionRatioThreshold: Float?
    var logProbThreshold: Float?
    var suppressBlank: Bool
    var withoutTimestamps: Bool

    static var current: TranscriptionDecoderOptions {
        let ud = UserDefaults.standard
        let language = ud.string(forKey: "decoder.language")
        let initialPrompt = ud.string(forKey: "decoder.initialPrompt")

        let fallbackCount: Int
        if ud.object(forKey: "decoder.temperatureFallbackCount") != nil {
            fallbackCount = ud.integer(forKey: "decoder.temperatureFallbackCount")
        } else {
            fallbackCount = 5
        }

        let compressionRatio: Float?
        if let raw = ud.object(forKey: "decoder.compressionRatioThreshold") as? Double {
            compressionRatio = Float(raw)
        } else {
            compressionRatio = 2.4
        }

        let logProb: Float?
        if let raw = ud.object(forKey: "decoder.logProbThreshold") as? Double {
            logProb = Float(raw)
        } else {
            logProb = -1.0
        }

        let suppressBlank: Bool
        if ud.object(forKey: "decoder.suppressBlank") != nil {
            suppressBlank = ud.bool(forKey: "decoder.suppressBlank")
        } else {
            suppressBlank = true
        }

        let withoutTimestamps: Bool
        if ud.object(forKey: "decoder.withoutTimestamps") != nil {
            withoutTimestamps = ud.bool(forKey: "decoder.withoutTimestamps")
        } else {
            withoutTimestamps = true
        }

        return TranscriptionDecoderOptions(
            language: language?.isEmpty == false ? language : nil,
            initialPrompt: initialPrompt?.isEmpty == false ? initialPrompt : nil,
            temperatureFallbackCount: fallbackCount,
            compressionRatioThreshold: compressionRatio,
            logProbThreshold: logProb,
            suppressBlank: suppressBlank,
            withoutTimestamps: withoutTimestamps
        )
    }
}
