import AppKit
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
        legacyDefaultsKey: "cloud.openai.apiKey",
        onKeyReadable: { Task { @MainActor in OpenAIAPIKeyStore.shared.refreshFromStorage() } }
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

    /// Asks the Keychain again if it couldn't be read earlier (locked, or a
    /// prompt was dismissed). May block on a prompt, so call it off the main
    /// thread.
    static func retryIfUnreadable() {
        vault.retryIfUnreadable()
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

    /// Posted after `setKey`/`clearKey`, and when a key turns up late (see
    /// `refreshFromStorage`), so non-SwiftUI components
    /// (e.g. `ModelRegistry`) can refresh derived state.
    static let didChangeNotification = CloudProvider.openAI.keyDidChangeNotification

    private(set) var hasKey: Bool

    /// Last 4 characters of the stored key — enough to tell two keys apart in
    /// the UI without ever showing one.
    private(set) var keySuffix: String?

    private init() {
        let stored = OpenAIAPIKey.read()
        self.hasKey = stored != nil
        self.keySuffix = Self.suffix(of: stored)
        // A Keychain that couldn't be read (locked, or a prompt dismissed)
        // would otherwise mean "no key" for the whole session. Coming back to
        // the app is when an unlock or access prompt is welcome.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task.detached(priority: .utility) { OpenAIAPIKey.retryIfUnreadable() }
        }
    }

    /// Catches up with a key that became readable after this store last
    /// looked, and tells the rest of the app when that changed anything.
    func refreshFromStorage() {
        let stored = OpenAIAPIKey.read()
        let suffix = Self.suffix(of: stored)
        guard (stored != nil) != hasKey || suffix != keySuffix else { return }
        hasKey = stored != nil
        keySuffix = suffix
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
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
