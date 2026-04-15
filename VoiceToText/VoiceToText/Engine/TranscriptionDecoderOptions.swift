import Foundation

// UserDefaults keys exposed to settings-ui:
//   decoder.language                  – String? (e.g. "en"; nil = auto-detect)
//   decoder.initialPrompt             – String? (freeform context hint)
//   decoder.temperatureFallbackCount  – Int (default 5)
//   decoder.compressionRatioThreshold – Float? (default 2.4)
//   decoder.logProbThreshold          – Float? (default -1.0)
//   decoder.suppressBlank             – Bool (default true)
//   decoder.withoutTimestamps         – Bool (default true)
//   decoder.suppressTokens            – String (comma-separated Whisper token IDs, default "")
//   decoder.noSpeechThreshold         – Float? (default 0.6)

struct TranscriptionDecoderOptions {
    var language: String?
    var initialPrompt: String?
    var temperatureFallbackCount: Int
    var compressionRatioThreshold: Float?
    var logProbThreshold: Float?
    var suppressBlank: Bool
    var withoutTimestamps: Bool
    var suppressTokens: [Int]
    var noSpeechThreshold: Float?

    static var current: TranscriptionDecoderOptions {
        let ud = UserDefaults.standard
        return TranscriptionDecoderOptions(
            language: ud.nonEmptyString(forKey: "decoder.language"),
            initialPrompt: ud.nonEmptyString(forKey: "decoder.initialPrompt"),
            temperatureFallbackCount: ud.int(forKey: "decoder.temperatureFallbackCount", default: 5),
            compressionRatioThreshold: ud.float(forKey: "decoder.compressionRatioThreshold", default: 2.4),
            logProbThreshold: ud.float(forKey: "decoder.logProbThreshold", default: -1.0),
            suppressBlank: ud.bool(forKey: "decoder.suppressBlank", default: true),
            withoutTimestamps: ud.bool(forKey: "decoder.withoutTimestamps", default: true),
            suppressTokens: ud.intListCSV(forKey: "decoder.suppressTokens"),
            noSpeechThreshold: ud.float(forKey: "decoder.noSpeechThreshold", default: 0.6)
        )
    }
}

private extension UserDefaults {
    func nonEmptyString(forKey key: String) -> String? {
        guard let value = string(forKey: key), !value.isEmpty else { return nil }
        return value
    }

    func int(forKey key: String, default fallback: Int) -> Int {
        object(forKey: key) != nil ? integer(forKey: key) : fallback
    }

    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) != nil ? bool(forKey: key) : fallback
    }

    func float(forKey key: String, default fallback: Float) -> Float {
        if let raw = object(forKey: key) as? Double {
            return Float(raw)
        }
        return fallback
    }

    func intListCSV(forKey key: String) -> [Int] {
        guard let raw = string(forKey: key), !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

