import Foundation

/// What a store answered when asked for a key.
nonisolated enum APIKeyLookup: Equatable, Sendable {
    case found(String)
    case absent
    /// The store couldn't be read (a locked keychain, a denied prompt), so the
    /// key may well exist. Never cached as "no key".
    case unavailable
}

/// One place a provider's API key can be kept.
nonisolated protocol APIKeyBackingStore: Sendable {
    func readKey() -> APIKeyLookup
    /// Stores `key` over any previous one. False when it couldn't.
    func writeKey(_ key: String) -> Bool
    /// True once the key is gone, including when there never was one.
    @discardableResult func removeKey() -> Bool
}

/// A provider's API key: where it's kept, the one-time move out of
/// UserDefaults, and an in-memory copy so the per-request reads (every
/// transcription, action and insight call asks) don't each go to securityd.
///
/// `secure` is the login keychain (see `APIKeyVault.forProvider`), or nil for a
/// build with no signing team, which keeps using `legacy`. `legacy` is the
/// UserDefaults value earlier builds kept the key in: a plaintext plist any
/// process running as the user can read without a prompt, and one that backups
/// copy. With a secure store, a key found there is a move still to make and is
/// removed only once the Keychain demonstrably holds it (written, then read
/// back), so a failed move never loses the key.
///
/// Foundation-only, with the stores injected, so the harness can drive it.
nonisolated final class APIKeyVault: @unchecked Sendable {
    private let secure: (any APIKeyBackingStore)?
    private let legacy: any APIKeyBackingStore
    private let lock = NSLock()
    private enum Cache { case unloaded, loaded(String?) }
    private var cache = Cache.unloaded

    init(secure: (any APIKeyBackingStore)?, legacy: any APIKeyBackingStore) {
        self.secure = secure
        self.legacy = legacy
    }

    func read() -> String? {
        lock.lock(); defer { lock.unlock() }
        if case .loaded(let key) = cache { return key }
        let (key, settled) = load()
        if settled { cache = .loaded(key) }
        return key
    }

    func write(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        cache = .loaded(key)
        guard let secure else {
            _ = legacy.writeKey(key)
            return
        }
        if moveIsConfirmed(key, into: secure) {
            legacy.removeKey()
        } else {
            // The Keychain refused. Keep the key where earlier builds did rather
            // than lose it; the next launch's first read retries the move.
            _ = legacy.writeKey(key)
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache = .loaded(nil)
        secure?.removeKey()
        legacy.removeKey()
    }

    /// The key, and whether that answer may be cached: not when the Keychain
    /// couldn't be read, so a later read tries again.
    private func load() -> (key: String?, settled: Bool) {
        let legacyKey: String?
        if case .found(let key) = legacy.readKey() { legacyKey = key } else { legacyKey = nil }
        guard let secure else { return (legacyKey, true) }

        // A key still in UserDefaults is a move not yet made: the first launch
        // after the switch, a Keychain write that failed, or a key saved by an
        // older build after a downgrade, which is newer than any Keychain copy
        // and so wins.
        if let legacyKey {
            if moveIsConfirmed(legacyKey, into: secure) {
                legacy.removeKey()
            }
            return (legacyKey, true)
        }
        switch secure.readKey() {
        case .found(let key): return (key, true)
        case .absent: return (nil, true)
        case .unavailable: return (nil, false)
        }
    }

    private func moveIsConfirmed(_ key: String, into secure: any APIKeyBackingStore) -> Bool {
        secure.writeKey(key) && secure.readKey() == .found(key)
    }
}

/// The UserDefaults value a key used to live in, and still does for a build
/// with no signing team.
nonisolated struct DefaultsAPIKeyStore: APIKeyBackingStore {
    let defaultsKey: String

    func readKey() -> APIKeyLookup {
        guard let key = UserDefaults.standard.string(forKey: defaultsKey), !key.isEmpty else {
            return .absent
        }
        return .found(key)
    }

    func writeKey(_ key: String) -> Bool {
        UserDefaults.standard.set(key, forKey: defaultsKey)
        return true
    }

    func removeKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return true
    }
}
