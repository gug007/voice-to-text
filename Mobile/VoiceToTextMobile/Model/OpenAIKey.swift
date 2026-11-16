import Foundation
import Observation
import Security

nonisolated enum OpenAIKeychain {
    private static let service = "voice-to-text-ai.VoiceToText.iOS"
    private static let account = "openai-api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func write(_ key: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

@Observable
final class OpenAIKeyStore {
    static let shared = OpenAIKeyStore()

    private(set) var suffix: String?
    var hasKey: Bool { suffix != nil }

    private init() {
        suffix = Self.suffix(of: OpenAIKeychain.read())
    }

    @discardableResult
    func set(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, OpenAIKeychain.write(key) else { return false }
        suffix = Self.suffix(of: key)
        return true
    }

    func clear() {
        OpenAIKeychain.clear()
        suffix = nil
    }

    private static func suffix(of key: String?) -> String? {
        key.map { String($0.suffix(4)) }
    }
}
