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

/// A remembered yes/no that survives relaunch.
nonisolated protocol APIKeyFlag: Sendable {
    var isSet: Bool { get }
    func set(_ value: Bool)
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
/// Store calls can block on a Keychain unlock or access prompt, so they never
/// run under the lock readers take: a read that finds another thread's load
/// in flight answers nil at once instead of hanging behind the prompt. A
/// Keychain that couldn't be read isn't asked again on every read (each
/// attempt can prompt); `retryIfUnreadable` asks again, and `onKeyReadable`
/// reports a key that turned up late, so "has a key" state can catch up.
///
/// Foundation-only, with the stores injected, so the harness can drive it.
nonisolated final class APIKeyVault: @unchecked Sendable {
    private let secure: (any APIKeyBackingStore)?
    private let legacy: any APIKeyBackingStore
    /// Set when the Keychain refused to delete a cleared key. The key then
    /// stays cleared, and the delete is retried at each launch until it lands,
    /// so a removed key can't come back.
    private let clearPending: any APIKeyFlag
    private let onKeyReadable: (@Sendable () -> Void)?

    /// Guards `state` only, and is never held across a store call.
    private let stateLock = NSLock()
    /// Serializes store calls, so a load finishing a move out of UserDefaults
    /// can't land after a newer write and leave the old key in the Keychain.
    private let ioLock = NSLock()

    private enum State {
        case unloaded
        /// Some thread is loading, perhaps behind a prompt; readers don't wait.
        case loading
        case loaded(String?)
        /// The Keychain couldn't be read; reads answer nil until a retry.
        case unreadable
    }
    private var state = State.unloaded

    init(
        secure: (any APIKeyBackingStore)?,
        legacy: any APIKeyBackingStore,
        clearPending: any APIKeyFlag,
        onKeyReadable: (@Sendable () -> Void)? = nil
    ) {
        self.secure = secure
        self.legacy = legacy
        self.clearPending = clearPending
        self.onKeyReadable = onKeyReadable
    }

    func read() -> String? {
        stateLock.lock()
        switch state {
        case .loaded(let key):
            stateLock.unlock()
            return key
        case .loading, .unreadable:
            stateLock.unlock()
            return nil
        case .unloaded:
            state = .loading
            stateLock.unlock()
            return loadAndSettle()
        }
    }

    /// Asks the Keychain again after it couldn't be read. Returns true when
    /// that found a key. Does nothing (and returns false) in any other state.
    @discardableResult
    func retryIfUnreadable() -> Bool {
        stateLock.lock()
        guard case .unreadable = state else {
            stateLock.unlock()
            return false
        }
        state = .loading
        stateLock.unlock()
        return loadAndSettle() != nil
    }

    func write(_ key: String) {
        ioLock.lock(); defer { ioLock.unlock() }
        settle(.loaded(key))
        clearPending.set(false)
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

    /// Removes the key everywhere. Returns false when the Keychain refused to
    /// delete it: the key still reads as cleared, now and after relaunch, and
    /// the delete is retried at the next launch.
    @discardableResult
    func clear() -> Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        settle(.loaded(nil))
        legacy.removeKey()
        guard let secure else { return true }
        let removed = secure.removeKey()
        clearPending.set(!removed)
        return removed
    }

    private func settle(_ newState: State) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }

    /// Loads under `ioLock` and records the answer before releasing it, so a
    /// write or clear waiting behind this load always has the last word.
    private func loadAndSettle() -> String? {
        ioLock.lock()
        let (key, settled) = load()
        settle(settled ? .loaded(key) : .unreadable)
        ioLock.unlock()
        if key != nil { onKeyReadable?() }
        return key
    }

    /// The key, and whether that answer may be cached: not when the Keychain
    /// couldn't be read.
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
                clearPending.set(false)
            }
            return (legacyKey, true)
        }
        if clearPending.isSet {
            if secure.removeKey() { clearPending.set(false) }
            return (nil, true)
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

/// A flag kept in UserDefaults; unset means the key is absent.
nonisolated struct DefaultsAPIKeyFlag: APIKeyFlag {
    let defaultsKey: String

    var isSet: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func set(_ value: Bool) {
        if value {
            UserDefaults.standard.set(true, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}
