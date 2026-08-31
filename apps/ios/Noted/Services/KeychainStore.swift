import Foundation
import Security

protocol KeychainOperations {
    func add(_ item: [String: Any]) -> OSStatus
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyData(matching query: [String: Any]) -> (status: OSStatus, data: Data?)
    func delete(matching query: [String: Any]) -> OSStatus
}

struct SystemKeychainOperations: KeychainOperations {
    func add(_ item: [String: Any]) -> OSStatus {
        SecItemAdd(item as CFDictionary, nil)
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyData(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func delete(matching query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

final class KeychainStore {
    private static let service = "com.memorygarden.ios"
    private static let account = "password"
    private let operations: KeychainOperations

    init(operations: KeychainOperations = SystemKeychainOperations()) {
        self.operations = operations
    }

    func savePassword(_ password: String) throws {
        let itemQuery = stableQuery
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = operations.update(query: itemQuery, attributes: attributes)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            try addOrReplace(item: itemQuery.merging(attributes) { _, new in new })
            return
        }

        // An old or partially written item can reject an update. The query is
        // scoped to this app's service/account, so replacing only that item is
        // safe and avoids touching unrelated Keychain entries.
        try replaceItem(itemQuery: itemQuery, attributes: attributes)
    }

    func password() -> String? {
        let query = stableQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        let result = operations.copyData(matching: query)
        guard result.status == errSecSuccess, let data = result.data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deletePassword() {
        _ = operations.delete(matching: stableQuery)
    }

    private var stableQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }

    private func addOrReplace(item: [String: Any]) throws {
        let addStatus = operations.add(item)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let retryStatus = operations.update(query: stableQuery, attributes: [
                kSecValueData as String: item[kSecValueData as String] as Any,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ])
            if retryStatus == errSecSuccess {
                return
            }
            try replaceItem(query: stableQuery, item: item)
            return
        }

        throw KeychainError.unableToSave(status: addStatus)
    }

    private func replaceItem(itemQuery: [String: Any], attributes: [String: Any]) throws {
        try replaceItem(query: itemQuery, item: itemQuery.merging(attributes) { _, new in new })
    }

    private func replaceItem(query: [String: Any], item: [String: Any]) throws {
        let deleteStatus = operations.delete(matching: query)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.unableToSave(status: deleteStatus)
        }

        let addStatus = operations.add(item)
        if addStatus == errSecSuccess {
            return
        }
        if addStatus == errSecDuplicateItem {
            let retryStatus = operations.update(query: query, attributes: [
                kSecValueData as String: item[kSecValueData as String] as Any,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ])
            if retryStatus == errSecSuccess {
                return
            }
            throw KeychainError.unableToSave(status: retryStatus)
        }

        throw KeychainError.unableToSave(status: addStatus)
    }
}

enum KeychainError: LocalizedError, Equatable {
    case unableToSave(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToSave(let status):
            return "Unable to save your password securely (Keychain status \(status))."
        }
    }
}
