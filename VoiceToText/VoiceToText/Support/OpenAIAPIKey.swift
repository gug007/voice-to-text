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
}

@Observable
@MainActor
final class OpenAIAPIKeyStore {
    static let shared = OpenAIAPIKeyStore()

    /// Posted after `setKey`/`clearKey` so non-SwiftUI components
    /// (e.g. `ModelRegistry`) can refresh derived state.
    static let didChangeNotification = Notification.Name("OpenAIAPIKeyStore.didChange")

    private(set) var hasKey: Bool

    private init() {
        self.hasKey = OpenAIAPIKey.read() != nil
    }

    func setKey(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearKey()
            return
        }
        OpenAIAPIKey.write(trimmed)
        hasKey = true
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clearKey() {
        OpenAIAPIKey.clear()
        hasKey = false
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
