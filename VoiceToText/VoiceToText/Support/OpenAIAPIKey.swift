import Foundation
import Observation

/// Storage choice: a plain plist value (UserDefaults) rather than the macOS
/// Keychain. The Keychain prompts the user on every code-signature change,
/// which makes dev builds painful and breaks "Always Allow" on rebuild.
/// UserDefaults lives in `~/Library/Preferences/<bundle-id>.plist`, scoped
/// to this Mac user, with the same effective threat model as the Keychain on
/// a single-user Mac (any process running as the user can read either).
nonisolated enum OpenAIAPIKey {
    private static let defaultsKey = "cloud.openai.apiKey"

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
