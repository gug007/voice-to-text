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

    /// Cheap client-side shape check, used to decide whether a paste is worth
    /// verifying over the network. ElevenLabs keys carry no reliable prefix, so
    /// this only asks for a single long token.
    static func looksLikeKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        return trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
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

    /// Last 4 characters of the stored key — enough to tell two keys apart in
    /// the UI without ever showing one.
    private(set) var keySuffix: String?

    private init() {
        let stored = ElevenLabsAPIKey.read()
        self.hasKey = stored != nil
        self.keySuffix = Self.suffix(of: stored)
    }

    func setKey(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearKey()
            return
        }
        ElevenLabsAPIKey.write(trimmed)
        hasKey = true
        keySuffix = Self.suffix(of: trimmed)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clearKey() {
        ElevenLabsAPIKey.clear()
        hasKey = false
        keySuffix = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private nonisolated static func suffix(of key: String?) -> String? {
        guard let key, key.count >= 4 else { return nil }
        return String(key.suffix(4))
    }
}
