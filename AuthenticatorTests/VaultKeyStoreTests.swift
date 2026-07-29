import CryptoKit
import Foundation
import Testing

@testable import Authenticator

/// These exercise the real Keychain from inside the app's sandbox, which is the only
/// way to confirm the design choice in `VaultKeyStore`: the legacy file-based keychain
/// works here, whereas the data-protection keychain would fail with
/// `errSecMissingEntitlement` because no provisioning profile grants
/// `com.apple.application-identifier`.
///
/// A dedicated service name keeps them away from the real vault key.
///
/// The suite disables itself where the login keychain is not usable at all — a
/// headless CI runner may have it locked, and a red build there would say nothing
/// about the code. The condition probes the keychain rather than sniffing for a `CI`
/// environment variable, because `xcodebuild` does not pass the shell environment
/// through to the test host.
/// Lives outside the suite: a `@Suite` trait cannot reference a static on the very
/// type it is attached to without forming a circular macro reference.
enum KeychainProbe {
    /// One throwaway write/read/delete cycle, to tell "the keychain is unavailable
    /// here" apart from "this code is broken".
    static let isUsable: Bool = {
        let probe = VaultKeyStore(
            service: "com.seanghay.Authenticator.tests.probe",
            account: UUID().uuidString
        )
        defer { try? probe.deleteKey() }
        do {
            try probe.store(SymmetricKey(size: .bits256))
            return try probe.loadKey() != nil
        } catch {
            return false
        }
    }()
}

@Suite(.enabled(if: KeychainProbe.isUsable))
struct VaultKeyStoreTests {

    private func makeStore() -> VaultKeyStore {
        VaultKeyStore(
            service: "com.seanghay.Authenticator.tests",
            account: "vault-key-\(UUID().uuidString)"
        )
    }

    @Test("A key can be written to and read back from the sandboxed keychain")
    func storeAndLoad() throws {
        let store = makeStore()
        defer { try? store.deleteKey() }

        let key = SymmetricKey(size: .bits256)
        try store.store(key)

        let loaded = try #require(try store.loadKey())
        #expect(
            loaded.withUnsafeBytes { Data($0) } == key.withUnsafeBytes { Data($0) }
        )
    }

    @Test("A missing key reads as nil rather than throwing")
    func missingKey() throws {
        let store = makeStore()
        #expect(try store.loadKey() == nil)
    }

    @Test("loadOrCreateKey creates once and is stable afterwards")
    func createsOnce() throws {
        let store = makeStore()
        defer { try? store.deleteKey() }

        let first = try store.loadOrCreateKey()
        let second = try store.loadOrCreateKey()
        #expect(
            first.withUnsafeBytes { Data($0) } == second.withUnsafeBytes { Data($0) }
        )
        #expect(first.bitCount == 256)
    }

    @Test("Storing over an existing key replaces it")
    func overwrite() throws {
        let store = makeStore()
        defer { try? store.deleteKey() }

        try store.store(SymmetricKey(size: .bits256))
        let replacement = SymmetricKey(size: .bits256)
        try store.store(replacement)

        let loaded = try #require(try store.loadKey())
        #expect(
            loaded.withUnsafeBytes { Data($0) }
                == replacement.withUnsafeBytes { Data($0) }
        )
    }

    @Test("Deleting is idempotent")
    func deleteIsIdempotent() throws {
        let store = makeStore()
        try store.store(SymmetricKey(size: .bits256))
        try store.deleteKey()
        try store.deleteKey()  // Must not throw on an already-absent item.
        #expect(try store.loadKey() == nil)
    }

    @Test("A key from the keychain actually opens a vault written with it")
    func endToEnd() throws {
        let store = makeStore()
        defer { try? store.deleteKey() }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let accounts = [
            Account(issuer: "GitHub", label: "alice", secret: Data("secret01".utf8))
        ]

        let writeVault = try Vault(key: try store.loadOrCreateKey(), directory: directory)
        try writeVault.save(VaultDocument(accounts: accounts))

        // Re-fetch the key from the keychain, as a fresh launch would.
        let readVault = try Vault(key: try #require(try store.loadKey()), directory: directory)
        #expect(try readVault.load().accounts == accounts)
    }
}
