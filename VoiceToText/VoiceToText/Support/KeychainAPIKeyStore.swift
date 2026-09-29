import Foundation
import OSLog
import Security

nonisolated extension APIKeyVault {
    /// The vault for one provider's key.
    ///
    /// Storage choice: a generic-password item in the login keychain, with the
    /// service set to this build's bundle identifier, so the Dev build and the
    /// release keep separate items and never prompt for each other's. The login
    /// keychain trusts an item's creator by its designated requirement, which
    /// every Developer ID build of this app shares across updates, so an update
    /// reads the key without a prompt. It is the file-based login keychain on purpose:
    /// the data-protection keychain (`kSecUseDataProtectionKeychain`) requires an
    /// application-identifier entitlement, which needs a provisioning profile
    /// this Developer ID app doesn't carry.
    ///
    /// A build with no signing team (ad-hoc "Sign to Run Locally", or unsigned)
    /// keeps the key in UserDefaults as before: its designated requirement is a
    /// hash of that exact binary, so the Keychain would prompt after every
    /// rebuild.
    ///
    /// `onKeyReadable` runs, on the reading thread, whenever a load finds a key,
    /// including one the Keychain only gave up on a retry.
    static func forProvider(
        account: String,
        label: String,
        legacyDefaultsKey: String,
        onKeyReadable: (@Sendable () -> Void)? = nil
    ) -> APIKeyVault {
        let legacy = DefaultsAPIKeyStore(defaultsKey: legacyDefaultsKey)
        let clearPending = DefaultsAPIKeyFlag(defaultsKey: legacyDefaultsKey + ".clearPending")
        guard CodeSigning.runningTeamIdentifier != nil,
              let service = Bundle.main.bundleIdentifier, !service.isEmpty else {
            return APIKeyVault(secure: nil, legacy: legacy, clearPending: clearPending)
        }
        return APIKeyVault(
            secure: KeychainAPIKeyStore(service: service, account: account, label: label),
            legacy: legacy,
            clearPending: clearPending,
            onKeyReadable: onKeyReadable
        )
    }
}

/// One provider's API key as a generic-password item in the login keychain.
nonisolated struct KeychainAPIKeyStore: APIKeyBackingStore {
    let service: String
    let account: String
    /// The name Keychain Access shows for the item.
    let label: String

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func readKey() -> APIKeyLookup {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let key = String(data: data, encoding: .utf8),
                  !key.isEmpty else { return .absent }
            return .found(key)
        case errSecItemNotFound:
            return .absent
        default:
            log(status, "read")
            return .unavailable
        }
    }

    func writeKey(_ key: String) -> Bool {
        let data = Data(key.utf8)
        var status = SecItemUpdate(
            itemQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = itemQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = label
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            log(status, "save")
            return false
        }
        return true
    }

    func removeKey() -> Bool {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            log(status, "delete")
            return false
        }
        return true
    }

    private func log(_ status: OSStatus, _ action: String) {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        AppLog.app.error("Keychain couldn't \(action, privacy: .public) the \(account, privacy: .public) API key: \(message, privacy: .public) (\(status, privacy: .public))")
    }
}
