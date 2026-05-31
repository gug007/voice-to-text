import Foundation
import Observation

/// ElevenLabs API key storage. Mirrors `OpenAIAPIKey`: a plain UserDefaults
/// value rather than the macOS Keychain (see `OpenAIAPIKey` for the rationale —
/// the Keychain re-prompts on every code-signature change, which breaks dev
/// builds). Same effective threat model on a single-user Mac.
nonisolated enum ElevenLabsAPIKey {
    private static let defaultsKey = "cloud.elevenLabs.apiKey"

    static func read() -> String? {
        let value = UserDefaults.standard.string(forKey: defaultsKey)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func write(_ value: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

@Observable
@MainActor
final class ElevenLabsAPIKeyStore {
    static let shared = ElevenLabsAPIKeyStore()

    /// Posted after `setKey`/`clearKey` so non-SwiftUI components
    /// (e.g. `ModelRegistry`) can refresh derived readiness state.
    static let didChangeNotification = Notification.Name("ElevenLabsAPIKeyStore.didChange")

    private(set) var hasKey: Bool

    private init() {
        self.hasKey = ElevenLabsAPIKey.read() != nil
    }

    func setKey(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearKey()
            return
        }
        ElevenLabsAPIKey.write(trimmed)
        hasKey = true
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clearKey() {
        ElevenLabsAPIKey.clear()
        hasKey = false
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
