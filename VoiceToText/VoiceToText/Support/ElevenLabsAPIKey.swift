import AppKit
import Foundation
import Observation

/// ElevenLabs API key storage. Mirrors `OpenAIAPIKey`: the login keychain,
/// moved across once from the UserDefaults value earlier builds used, which
/// team-less debug builds keep using (see `OpenAIAPIKey` for why, and
/// `APIKeyVault.forProvider` for the details).
nonisolated enum ElevenLabsAPIKey {
    private static let vault = APIKeyVault.forProvider(
        account: "elevenlabs",
        label: "VoiceToText ElevenLabs API key",
        legacyDefaultsKey: "cloud.elevenLabs.apiKey",
        onKeyReadable: { Task { @MainActor in ElevenLabsAPIKeyStore.shared.refreshFromStorage() } }
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

    /// Posted after `setKey`/`clearKey`, and when a key turns up late (see
    /// `refreshFromStorage`), so non-SwiftUI components
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
        // A Keychain that couldn't be read (locked, or a prompt dismissed)
        // would otherwise mean "no key" for the whole session. Coming back to
        // the app is when an unlock or access prompt is welcome.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task.detached(priority: .utility) { ElevenLabsAPIKey.retryIfUnreadable() }
        }
    }

    /// Catches up with a key that became readable after this store last
    /// looked, and tells the rest of the app when that changed anything.
    func refreshFromStorage() {
        let stored = ElevenLabsAPIKey.read()
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
