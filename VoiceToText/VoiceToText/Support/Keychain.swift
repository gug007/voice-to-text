import Foundation
import Observation
import Security

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        }
    }
}

nonisolated enum Keychain {
    static func set(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unhandled(updateStatus)
        }
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Nonisolated read access to the OpenAI API key — safe to call from any
/// actor. Writes go through `OpenAIAPIKeyStore` so the SwiftUI layer can
/// observe changes.
nonisolated enum OpenAIAPIKey {
    static let service = "VoiceToText.OpenAI"
    static let account = "apiKey"

    static func read() -> String? {
        let value = Keychain.get(service: service, account: account)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

@Observable
@MainActor
final class OpenAIAPIKeyStore {
    static let shared = OpenAIAPIKeyStore()

    /// Posted on the main actor after `setKey`/`clearKey` so other components
    /// (e.g. `ModelRegistry`) can refresh derived state.
    static let didChangeNotification = Notification.Name("OpenAIAPIKeyStore.didChange")

    private(set) var hasKey: Bool

    private init() {
        self.hasKey = OpenAIAPIKey.read() != nil
    }

    func setKey(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearKey()
            return
        }
        try Keychain.set(trimmed, service: OpenAIAPIKey.service, account: OpenAIAPIKey.account)
        hasKey = true
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clearKey() {
        Keychain.delete(service: OpenAIAPIKey.service, account: OpenAIAPIKey.account)
        hasKey = false
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
