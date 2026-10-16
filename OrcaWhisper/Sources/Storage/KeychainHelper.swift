import Foundation
import Security
import os

final class KeychainHelper {
    static let shared = KeychainHelper()
    private let logger = Logger(subsystem: "com.orca.whisper", category: "Keychain")
    private let service = "com.orca.whisper"

    private init() {}

    func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            logger.debug("Successfully updated keychain key: \(key, privacy: .public)")
            return true
        }

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            if addStatus == errSecSuccess {
                logger.debug("Successfully added keychain key: \(key, privacy: .public)")
                return true
            } else {
                logger.error("Failed to add keychain key \(key, privacy: .public): status \(addStatus)")
                return false
            }
        }

        logger.error("Failed to update keychain key \(key, privacy: .public): status \(updateStatus)")
        return false
    }

    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
