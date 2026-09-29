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
    var unreadable = false
    private(set) var reads = 0

    init(_ value: String? = nil) {
        self.value = value
    }

    func readKey() -> APIKeyLookup {
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
        value = nil
        return true
    }
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
        try retriesWhenKeychainUnreadable()
        try writeFallsBackToDefaultsWhenKeychainRejects()
        try writeClearsDefaultsCopy()
        try clearRemovesBoth()
        print("API key vault harness passed")
    }

    private static func teamlessBuildsUseDefaultsOnly() throws {
        let legacy = FakeStore("sk-old")
        let vault = APIKeyVault(secure: nil, legacy: legacy)
        try expect(vault.read() == "sk-old", "team-less build reads defaults")
        vault.write("sk-new")
        try expect(legacy.value == "sk-new", "team-less build writes defaults")
        vault.clear()
        try expect(legacy.value == nil, "team-less build clears defaults")
    }

    private static func movesDefaultsKeyIntoKeychain() throws {
        let secure = FakeStore()
        let legacy = FakeStore("sk-old")
        let vault = APIKeyVault(secure: secure, legacy: legacy)
        try expect(vault.read() == "sk-old", "migrated key is returned")
        try expect(secure.value == "sk-old", "key lands in the keychain")
        try expect(legacy.value == nil, "plaintext copy removed once confirmed")
    }

    private static func keepsDefaultsKeyWhenKeychainRejectsIt() throws {
        let secure = FakeStore()
        secure.rejectsWrites = true
        let legacy = FakeStore("sk-old")
        try expect(APIKeyVault(secure: secure, legacy: legacy).read() == "sk-old", "key still usable")
        try expect(legacy.value == "sk-old", "defaults copy kept when the keychain refuses")

        // Next launch, the keychain works again: the move completes.
        secure.rejectsWrites = false
        try expect(APIKeyVault(secure: secure, legacy: legacy).read() == "sk-old", "retry returns the key")
        try expect(secure.value == "sk-old" && legacy.value == nil, "retry completes the move")
    }

    private static func keepsDefaultsKeyWhenReadBackDiffers() throws {
        let secure = FakeStore()
        secure.losesWrites = true
        let legacy = FakeStore("sk-old")
        try expect(APIKeyVault(secure: secure, legacy: legacy).read() == "sk-old", "key still usable")
        try expect(legacy.value == "sk-old", "defaults copy kept until the read-back matches")
    }

    private static func defaultsKeyWinsAfterDowngrade() throws {
        // An older build saved a new key to defaults after the keychain copy.
        let secure = FakeStore("sk-stale")
        let legacy = FakeStore("sk-newer")
        try expect(APIKeyVault(secure: secure, legacy: legacy).read() == "sk-newer", "newer defaults key wins")
        try expect(secure.value == "sk-newer" && legacy.value == nil, "and replaces the keychain copy")
    }

    private static func readsKeychainWhenDefaultsEmpty() throws {
        let vault = APIKeyVault(secure: FakeStore("sk-kept"), legacy: FakeStore())
        try expect(vault.read() == "sk-kept", "keychain key read")
        let empty = APIKeyVault(secure: FakeStore(), legacy: FakeStore())
        try expect(empty.read() == nil, "no key anywhere is nil")
    }

    private static func cachesAfterFirstRead() throws {
        let secure = FakeStore("sk-kept")
        let vault = APIKeyVault(secure: secure, legacy: FakeStore())
        _ = vault.read()
        let readsAfterLoad = secure.reads
        for _ in 0..<10 { _ = vault.read() }
        try expect(secure.reads == readsAfterLoad, "later reads come from memory")

        let absent = FakeStore()
        let empty = APIKeyVault(secure: absent, legacy: FakeStore())
        _ = empty.read()
        let absentReads = absent.reads
        _ = empty.read()
        try expect(absent.reads == absentReads, "a confirmed absence is cached too")
    }

    private static func retriesWhenKeychainUnreadable() throws {
        let secure = FakeStore("sk-kept")
        secure.unreadable = true
        let vault = APIKeyVault(secure: secure, legacy: FakeStore())
        try expect(vault.read() == nil, "unreadable keychain yields no key for now")
        secure.unreadable = false
        try expect(vault.read() == "sk-kept", "an unreadable keychain isn't cached as no key")
    }

    private static func writeFallsBackToDefaultsWhenKeychainRejects() throws {
        let secure = FakeStore()
        secure.rejectsWrites = true
        let legacy = FakeStore()
        let vault = APIKeyVault(secure: secure, legacy: legacy)
        vault.write("sk-new")
        try expect(vault.read() == "sk-new", "written key usable this session")
        try expect(legacy.value == "sk-new", "kept in defaults rather than lost")
    }

    private static func writeClearsDefaultsCopy() throws {
        let secure = FakeStore()
        let legacy = FakeStore("sk-old")
        let vault = APIKeyVault(secure: secure, legacy: legacy)
        vault.write("sk-new")
        try expect(secure.value == "sk-new", "write lands in the keychain")
        try expect(legacy.value == nil, "no plaintext copy left behind")
        try expect(vault.read() == "sk-new", "read returns the new key")
    }

    private static func clearRemovesBoth() throws {
        let secure = FakeStore("sk-kept")
        let legacy = FakeStore("sk-old")
        let vault = APIKeyVault(secure: secure, legacy: legacy)
        vault.clear()
        try expect(secure.value == nil && legacy.value == nil, "clear removes every copy")
        try expect(vault.read() == nil, "and read agrees")
    }
}
