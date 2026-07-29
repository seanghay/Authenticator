import CryptoKit
import Foundation

enum VaultError: LocalizedError, Equatable {
    case corruptFile
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .corruptFile:
            "The vault file could not be read. It may be damaged or encrypted with a different key."
        case .unsupportedSchema(let version):
            "This vault was written by a newer version of Authenticator (format \(version))."
        }
    }
}

/// Reads and writes the encrypted account store.
///
/// On-disk layout is a 5-byte cleartext header followed by an AES-GCM sealed box:
///
///     "AUTHV" | formatVersion(1) | nonce(12) | ciphertext | tag(16)
///
/// The header is passed to AES-GCM as additional authenticated data, so it is
/// covered by the tag even though it is readable.
struct Vault {
    private static let magic = Data("AUTH".utf8)
    private static let formatVersion: UInt8 = 1
    private static let headerLength = 5

    let directory: URL
    private let key: SymmetricKey

    var fileURL: URL { directory.appendingPathComponent("vault.dat") }
    var backupURL: URL { directory.appendingPathComponent("vault.dat.bak") }

    init(key: SymmetricKey, directory: URL? = nil) throws {
        self.key = key
        if let directory {
            self.directory = directory
        } else {
            // Sandboxed, so this already resolves inside the app container.
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = base.appendingPathComponent("Authenticator", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Reading

    /// Loads the vault, falling back to the backup if the primary file is unreadable.
    /// A missing vault is not an error — it is a first launch.
    func load() throws -> VaultDocument {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            if manager.fileExists(atPath: backupURL.path) {
                return try decodeDocument(from: try Data(contentsOf: backupURL))
            }
            return VaultDocument()
        }

        do {
            return try decodeDocument(from: try Data(contentsOf: fileURL))
        } catch {
            guard manager.fileExists(atPath: backupURL.path),
                  let backupData = try? Data(contentsOf: backupURL),
                  let recovered = try? decodeDocument(from: backupData)
            else {
                throw error
            }
            return recovered
        }
    }

    private func decodeDocument(from raw: Data) throws -> VaultDocument {
        guard raw.count > Self.headerLength else { throw VaultError.corruptFile }

        let header = raw.prefix(Self.headerLength)
        guard header.prefix(4) == Self.magic else { throw VaultError.corruptFile }

        let version = header[header.startIndex + 4]
        guard version == Self.formatVersion else {
            throw VaultError.unsupportedSchema(Int(version))
        }

        let body = raw.suffix(from: raw.startIndex + Self.headerLength)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: body),
              let plaintext = try? AES.GCM.open(sealedBox, using: key, authenticating: header)
        else {
            throw VaultError.corruptFile
        }

        let document = try JSONDecoder().decode(VaultDocument.self, from: plaintext)
        guard document.schemaVersion <= VaultDocument.currentSchemaVersion else {
            throw VaultError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }

    // MARK: - Writing

    /// Encrypts and replaces the vault atomically, keeping the previous file as `.bak`.
    func save(_ document: VaultDocument) throws {
        let plaintext = try JSONEncoder().encode(document)

        var header = Self.magic
        header.append(Self.formatVersion)

        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = sealed.combined else { throw VaultError.corruptFile }

        var output = header
        output.append(combined)

        let manager = FileManager.default
        let temporaryURL = directory.appendingPathComponent("vault.dat.tmp")
        try output.write(to: temporaryURL, options: [.atomic])

        if manager.fileExists(atPath: fileURL.path) {
            // Without `.withoutDeletingBackupItem` the backup is removed once the
            // replace succeeds, which would defeat the whole point of keeping one.
            _ = try manager.replaceItemAt(
                fileURL,
                withItemAt: temporaryURL,
                backupItemName: "vault.dat.bak",
                options: [.withoutDeletingBackupItem]
            )
        } else {
            try manager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    /// Removes the vault and its backup. Used by "erase all data".
    func destroy() throws {
        let manager = FileManager.default
        for url in [fileURL, backupURL] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }
}
