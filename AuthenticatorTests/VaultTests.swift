import CryptoKit
import Foundation
import Testing

@testable import Authenticator

struct VaultTests {
    /// Each test gets a throwaway directory so nothing touches the real container.
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthenticatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Stored, not computed: `Account` mints a fresh UUID per initialisation, so a
    /// computed property would never compare equal to what was written.
    private let sampleAccounts: [Account] = [
        Account(issuer: "GitHub", label: "alice", secret: Data("secret01".utf8), sortIndex: 0),
        Account(
            issuer: "AWS", label: "root", secret: Data("secret02".utf8),
            algorithm: .sha256, digits: 8, sortIndex: 1
        ),
    ]

    @Test("Saving then loading returns the same accounts")
    func roundTrip() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = SymmetricKey(size: .bits256)
        let vault = try Vault(key: key, directory: directory)
        try vault.save(VaultDocument(accounts: sampleAccounts))

        let reopened = try Vault(key: key, directory: directory)
        let loaded = try reopened.load()

        #expect(loaded.accounts == sampleAccounts)
        #expect(loaded.schemaVersion == VaultDocument.currentSchemaVersion)
    }

    @Test("A missing vault reads as empty rather than failing")
    func missingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let vault = try Vault(key: SymmetricKey(size: .bits256), directory: directory)
        #expect(try vault.load().accounts.isEmpty)
    }

    @Test("Secrets are not recoverable from the file without the key")
    func contentsAreEncrypted() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let vault = try Vault(key: SymmetricKey(size: .bits256), directory: directory)
        try vault.save(VaultDocument(accounts: sampleAccounts))

        let raw = try Data(contentsOf: vault.fileURL)
        // Even the issuer names must not be readable — that is the advantage this
        // design has over one cleartext-attributed keychain item per account.
        #expect(!raw.contains(Data("GitHub".utf8)))
        #expect(!raw.contains(Data("secret01".utf8)))
        #expect(raw.prefix(4) == Data("AUTH".utf8))
    }

    @Test("The wrong key is rejected instead of returning garbage")
    func wrongKeyFails() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let vault = try Vault(key: SymmetricKey(size: .bits256), directory: directory)
        try vault.save(VaultDocument(accounts: sampleAccounts))

        let other = try Vault(key: SymmetricKey(size: .bits256), directory: directory)
        #expect(throws: VaultError.corruptFile) { _ = try other.load() }
    }

    @Test("Tampering with the authenticated header is detected")
    func headerIsAuthenticated() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = SymmetricKey(size: .bits256)
        let vault = try Vault(key: key, directory: directory)
        try vault.save(VaultDocument(accounts: sampleAccounts))

        var raw = try Data(contentsOf: vault.fileURL)
        raw[3] = raw[3] ^ 0xFF  // Corrupt the magic, leaving the ciphertext intact.
        try raw.write(to: vault.fileURL)

        let reopened = try Vault(key: key, directory: directory)
        #expect(throws: VaultError.corruptFile) { _ = try reopened.load() }
    }

    @Test("A corrupt vault falls back to the backup written by the previous save")
    func backupRecovery() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = SymmetricKey(size: .bits256)
        let vault = try Vault(key: key, directory: directory)

        try vault.save(VaultDocument(accounts: sampleAccounts))
        // The second save rotates the first file into vault.dat.bak.
        try vault.save(VaultDocument(accounts: Array(sampleAccounts.prefix(1))))
        #expect(FileManager.default.fileExists(atPath: vault.backupURL.path))

        try Data("not a vault".utf8).write(to: vault.fileURL)

        let recovered = try vault.load()
        #expect(recovered.accounts == sampleAccounts)
    }

    @Test("Destroy removes both the vault and its backup")
    func destroy() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let vault = try Vault(key: SymmetricKey(size: .bits256), directory: directory)
        try vault.save(VaultDocument(accounts: sampleAccounts))
        try vault.save(VaultDocument(accounts: sampleAccounts))

        try vault.destroy()
        #expect(!FileManager.default.fileExists(atPath: vault.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: vault.backupURL.path))
    }
}
