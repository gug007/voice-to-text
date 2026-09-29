import Foundation
import Observation

/// Storage choice: the login keychain, not UserDefaults. Earlier builds kept
/// the key in `~/Library/Preferences/<bundle-id>.plist` on the grounds that the
/// Keychain prompts on every code-signature change, but that holds only for
/// ad-hoc builds. A Developer ID build's designated requirement survives
/// updates, so the login keychain hands the key back without a prompt, and
/// unlike the plist no other process can read it silently and backups don't
/// copy it in plaintext. The key moves across once, on first read; team-less
/// debug builds keep using UserDefaults. See `APIKeyVault.forProvider`.
nonisolated enum OpenAIAPIKey {
    private static let vault = APIKeyVault.forProvider(
        account: "openai",
        label: "VoiceToText OpenAI API key",
        legacyDefaultsKey: "cloud.openai.apiKey"
    )

    static func read() -> String? {
        vault.read()
    }

    static func write(_ value: String) {
        vault.write(value)
    }

    static func clear() {
        vault.clear()
    }

    /// Cheap client-side shape check, used to decide whether a paste is worth
    /// verifying over the network. OpenAI keys are `sk-…`, `sk-proj-…` or
    /// `sk-svcacct-…`; the server is still the authority on validity.
    static func looksLikeKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-"), trimmed.count >= 20 else { return false }
        return trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

@Observable
@MainActor
final class OpenAIAPIKeyStore {
    static let shared = OpenAIAPIKeyStore()

    /// Posted after `setKey`/`clearKey` so non-SwiftUI components
    /// (e.g. `ModelRegistry`) can refresh derived state.
    static let didChangeNotification = Notification.Name("OpenAIAPIKeyStore.didChange")

    private(set) var hasKey: Bool

    /// Last 4 characters of the stored key — enough to tell two keys apart in
    /// the UI without ever showing one.
    private(set) var keySuffix: String?

    private init() {
        let stored = OpenAIAPIKey.read()
        self.hasKey = stored != nil
        self.keySuffix = Self.suffix(of: stored)
    }

    func setKey(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearKey()
            return
        }
        OpenAIAPIKey.write(trimmed)
        hasKey = true
        keySuffix = Self.suffix(of: trimmed)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clearKey() {
        OpenAIAPIKey.clear()
        hasKey = false
        keySuffix = nil
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private nonisolated static func suffix(of key: String?) -> String? {
        guard let key, key.count >= 4 else { return nil }
        return String(key.suffix(4))
    }
}
