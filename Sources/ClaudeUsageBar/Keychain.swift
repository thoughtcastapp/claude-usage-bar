import Foundation
import Security

enum KeychainError: Error, CustomStringConvertible {
    case notFound
    case osStatus(OSStatus)
    case invalidData

    var description: String {
        switch self {
        case .notFound: return "Claude Safe Storage password not found in Keychain"
        case .osStatus(let status): return "Keychain error \(status)"
        case .invalidData: return "Keychain returned invalid data"
        }
    }
}

enum Keychain {
    static func claudeSafeStoragePassword() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecAttrAccount as String: "Claude Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw KeychainError.notFound
        }
        guard status == errSecSuccess else {
            throw KeychainError.osStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        return data
    }
}
