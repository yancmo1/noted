import Foundation
import Security

final class KeychainStore {
    private let service = "com.memorygarden.ios"

    func savePassword(_ password: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClass, kSecAttrService as String: service, kSecAttrAccount as String: "password"]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeychainError.unableToSave }
        } else if status != errSecSuccess {
            throw KeychainError.unableToSave
        }
    }

    func password() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClass, kSecAttrService as String: service, kSecAttrAccount as String: "password", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deletePassword() {
        let query: [String: Any] = [kSecClass as String: kSecClass, kSecAttrService as String: service, kSecAttrAccount as String: "password"]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error { case unableToSave }
