import CryptoKit
import Foundation
import Security

/// Holds the single AES key that protects the vault file.
///
/// This deliberately uses the *legacy* file-based macOS keychain: no
/// `kSecUseDataProtectionKeychain`, no `kSecAttrAccessGroup`, no
/// `kSecAttrAccessControl`. Those all require a `com.apple.application-identifier`
/// entitlement that only arrives with a provisioning profile, and without one they
/// fail with `errSecMissingEntitlement` (-34018). The legacy keychain works under
/// App Sandbox with no entitlement at all.
struct VaultKeyStore {
    let service: String
    let account: String

    static let shared = VaultKeyStore(
        service: "com.seanghay.Authenticator",
        account: "vault-key"
    )

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Fetches the existing key, or creates and stores a fresh one on first launch.
    func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        try store(key)
        return key
    }

    func loadKey() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status, operation: "read")
        }
    }

    func store(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        var query = baseQuery
        query[kSecValueData as String] = keyData
        query[kSecAttrLabel as String] = "Authenticator vault key"
        query[kSecAttrDescription as String] = "Encrypts your authenticator accounts"

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: keyData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError(status: updateStatus, operation: "update")
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status, operation: "write")
        }
    }

    /// Used by "erase all data".
    func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, operation: "delete")
        }
    }
}
