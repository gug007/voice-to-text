import Foundation

struct APIKeyVaultHarnessFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw APIKeyVaultHarnessFailure(description: message)
    }
}

/// An in-memory store that can be told to fail the ways the Keychain can.
private final class FakeStore: APIKeyBackingStore, @unchecked Sendable {
    var value: String?
    var rejectsWrites = false
    /// Accepts a write but reads back something else (a write that didn't land).
    var losesWrites = false
    var rejectsRemoves = false
    var unreadable = false
    /// When set, a read signals `readStarted` and then waits for the gate, like
    /// a Keychain read behind a prompt.
    var readGate: DispatchSemaphore?
    var readStarted: DispatchSemaphore?
    private(set) var reads = 0

    init(_ value: String? = nil) {
        self.value = value
    }

    func readKey() -> APIKeyLookup {
        readStarted?.signal()
        readGate?.wait()
        reads += 1
        if unreadable { return .unavailable }
        return value.map(APIKeyLookup.found) ?? .absent
    }

    func writeKey(_ key: String) -> Bool {
        guard !rejectsWrites else { return false }
        if !losesWrites { value = key }
        return true
    }

    func removeKey() -> Bool {
        guard !rejectsRemoves else { return false }
        value = nil
        return true
    }
}

private final class FakeFlag: APIKeyFlag, @unchecked Sendable {
    var isSet = false
    func set(_ value: Bool) { isSet = value }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func bump() { lock.lock(); count += 1; lock.unlock() }
}

private func makeVault(
    secure: FakeStore?,
    legacy: FakeStore,
    flag: FakeFlag = FakeFlag(),
    onKeyReadable: (@Sendable () -> Void)? = nil
) -> APIKeyVault {
    APIKeyVault(secure: secure, legacy: legacy, clearPending: flag, onKeyReadable: onKeyReadable)
}

@main
struct APIKeyVaultHarness {
    static func main() throws {
        try teamlessBuildsUseDefaultsOnly()
        try movesDefaultsKeyIntoKeychain()
        try keepsDefaultsKeyWhenKeychainRejectsIt()
        try keepsDefaultsKeyWhenReadBackDiffers()
        try defaultsKeyWinsAfterDowngrade()
        try readsKeychainWhenDefaultsEmpty()
        try cachesAfterFirstRead()
        try writeFallsBackToDefaultsWhenKeychainRejects()
        try writeClearsDefaultsCopy()
        try clearRemovesBoth()
        try refusedClearStaysClearedAndRetries()
        try unreadableIsRetriedOnlyOnRequest()
        try reportsKeysThatTurnUp()
        try readersDontWaitBehindAPrompt()
        print("API key vault harness passed")
    }

    private static func teamlessBuildsUseDefaultsOnly() throws {
        let legacy = FakeStore("sk-old")
        let vault = makeVault(secure: nil, legacy: legacy)
        try expect(vault.read() == "sk-old", "team-less build reads defaults")
        vault.write("sk-new")
        try expect(legacy.value == "sk-new", "team-less build writes defaults")
        vault.clear()
        try expect(legacy.value == nil, "team-less build clears defaults")
    }

    private static func movesDefaultsKeyIntoKeychain() throws {
        let secure = FakeStore()
        let legacy = FakeStore("sk-old")
        let vault = makeVault(secure: secure, legacy: legacy)
        try expect(vault.read() == "sk-old", "migrated key is returned")
        try expect(secure.value == "sk-old", "key lands in the keychain")
        try expect(legacy.value == nil, "plaintext copy removed once confirmed")
    }

    private static func keepsDefaultsKeyWhenKeychainRejectsIt() throws {
        let secure = FakeStore()
        secure.rejectsWrites = true
        let legacy = FakeStore("sk-old")
        try expect(makeVault(secure: secure, legacy: legacy).read() == "sk-old", "key still usable")
        try expect(legacy.value == "sk-old", "defaults copy kept when the keychain refuses")

        // Next launch, the keychain works again: the move completes.
        secure.rejectsWrites = false
        try expect(makeVault(secure: secure, legacy: legacy).read() == "sk-old", "retry returns the key")
        try expect(secure.value == "sk-old" && legacy.value == nil, "retry completes the move")
    }

    private static func keepsDefaultsKeyWhenReadBackDiffers() throws {
        let secure = FakeStore()
        secure.losesWrites = true
        let legacy = FakeStore("sk-old")
        try expect(makeVault(secure: secure, legacy: legacy).read() == "sk-old", "key still usable")
        try expect(legacy.value == "sk-old", "defaults copy kept until the read-back matches")
    }

    private static func defaultsKeyWinsAfterDowngrade() throws {
        // An older build saved a new key to defaults after the keychain copy.
        let secure = FakeStore("sk-stale")
        let legacy = FakeStore("sk-newer")
        try expect(makeVault(secure: secure, legacy: legacy).read() == "sk-newer", "newer defaults key wins")
        try expect(secure.value == "sk-newer" && legacy.value == nil, "and replaces the keychain copy")
    }

    private static func readsKeychainWhenDefaultsEmpty() throws {
        let vault = makeVault(secure: FakeStore("sk-kept"), legacy: FakeStore())
        try expect(vault.read() == "sk-kept", "keychain key read")
        let empty = makeVault(secure: FakeStore(), legacy: FakeStore())
        try expect(empty.read() == nil, "no key anywhere is nil")
    }

    private static func cachesAfterFirstRead() throws {
        let secure = FakeStore("sk-kept")
        let vault = makeVault(secure: secure, legacy: FakeStore())
        _ = vault.read()
        let readsAfterLoad = secure.reads
        for _ in 0..<10 { _ = vault.read() }
        try expect(secure.reads == readsAfterLoad, "later reads come from memory")

        let absent = FakeStore()
        let empty = makeVault(secure: absent, legacy: FakeStore())
        _ = empty.read()
        let absentReads = absent.reads
        _ = empty.read()
        try expect(absent.reads == absentReads, "a confirmed absence is cached too")
    }

    private static func writeFallsBackToDefaultsWhenKeychainRejects() throws {
        let secure = FakeStore()
        secure.rejectsWrites = true
        let legacy = FakeStore()
        let vault = makeVault(secure: secure, legacy: legacy)
        vault.write("sk-new")
        try expect(vault.read() == "sk-new", "written key usable this session")
        try expect(legacy.value == "sk-new", "kept in defaults rather than lost")
    }

    private static func writeClearsDefaultsCopy() throws {
        let secure = FakeStore()
        let legacy = FakeStore("sk-old")
        let vault = makeVault(secure: secure, legacy: legacy)
        vault.write("sk-new")
        try expect(secure.value == "sk-new", "write lands in the keychain")
        try expect(legacy.value == nil, "no plaintext copy left behind")
        try expect(vault.read() == "sk-new", "read returns the new key")
    }

    private static func refusedClearStaysClearedAndRetries() throws {
        let secure = FakeStore("sk-kept")
        secure.rejectsRemoves = true
        let flag = FakeFlag()
        let first = makeVault(secure: secure, legacy: FakeStore(), flag: flag)
        try expect(!first.clear(), "a refused delete is reported")
        try expect(first.read() == nil, "the key reads as cleared this session")
        try expect(flag.isSet, "the refused delete is remembered")

        // Next launch, still refusing: the stale item stays hidden.
        try expect(makeVault(secure: secure, legacy: FakeStore(), flag: flag).read() == nil, "a cleared key doesn't come back")
        try expect(flag.isSet, "still pending while the delete keeps failing")

        // A later launch where the delete works finishes it.
        secure.rejectsRemoves = false
        try expect(makeVault(secure: secure, legacy: FakeStore(), flag: flag).read() == nil, "still cleared")
        try expect(secure.value == nil && !flag.isSet, "the retried delete lands and the flag clears")

        // Saving a new key supersedes a pending clear.
        secure.value = "sk-stale"
        secure.rejectsRemoves = true
        let again = makeVault(secure: secure, legacy: FakeStore(), flag: flag)
        again.clear()
        again.write("sk-new")
        try expect(!flag.isSet, "a write drops the pending clear")
        try expect(makeVault(secure: secure, legacy: FakeStore(), flag: flag).read() == "sk-new", "the new key reads back")
    }

    private static func unreadableIsRetriedOnlyOnRequest() throws {
        let secure = FakeStore("sk-kept")
        secure.unreadable = true
        let v = makeVault(secure: secure, legacy: FakeStore())
        try expect(v.read() == nil, "unreadable keychain yields no key")
        let readsAfterFailure = secure.reads
        _ = v.read()
        _ = v.read()
        try expect(secure.reads == readsAfterFailure, "reads don't ask again (each ask can prompt)")
        try expect(!v.retryIfUnreadable(), "a retry that still fails finds nothing")
        secure.unreadable = false
        try expect(v.retryIfUnreadable(), "a retry that works finds the key")
        try expect(v.read() == "sk-kept", "and reads return it")
        try expect(!v.retryIfUnreadable(), "retry is a no-op once loaded")
    }

    private static func reportsKeysThatTurnUp() throws {
        let secure = FakeStore("sk-kept")
        secure.unreadable = true
        let found = Counter()
        let v = makeVault(secure: secure, legacy: FakeStore(), onKeyReadable: { found.bump() })
        _ = v.read()
        try expect(found.value == 0, "no report while unreadable")
        secure.unreadable = false
        v.retryIfUnreadable()
        try expect(found.value == 1, "a key found on retry is reported")
        _ = v.read()
        try expect(found.value == 1, "cached reads don't report again")
    }

    private static func readersDontWaitBehindAPrompt() throws {
        let secure = FakeStore("sk-kept")
        let gate = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        secure.readGate = gate
        secure.readStarted = started
        let v = makeVault(secure: secure, legacy: FakeStore())
        let loaded = DispatchSemaphore(value: 0)
        let result = Counter()
        DispatchQueue.global().async {
            if v.read() == "sk-kept" { result.bump() }
            loaded.signal()
        }
        started.wait()
        try expect(v.read() == nil, "a read during another thread's load answers at once")
        gate.signal()
        loaded.wait()
        secure.readGate = nil
        secure.readStarted = nil
        try expect(result.value == 1, "the loading thread gets the key")
        try expect(v.read() == "sk-kept", "later reads get it too")
    }

    private static func clearRemovesBoth() throws {
        let secure = FakeStore("sk-kept")
        let legacy = FakeStore("sk-old")
        let vault = makeVault(secure: secure, legacy: legacy)
        vault.clear()
        try expect(secure.value == nil && legacy.value == nil, "clear removes every copy")
        try expect(vault.read() == nil, "and read agrees")
    }
}
