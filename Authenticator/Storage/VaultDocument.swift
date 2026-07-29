import Foundation

/// The plaintext shape of the vault, before encryption.
struct VaultDocument: Codable, Sendable {
    /// Bumped only when the on-disk shape changes incompatibly.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var accounts: [Account] = []

    init(accounts: [Account] = []) {
        self.accounts = accounts
    }
}
