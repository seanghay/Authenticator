import Foundation

enum MigrationURIError: LocalizedError, Equatable {
    case notAMigrationURI
    case missingData
    case invalidBase64

    var errorDescription: String? {
        switch self {
        case .notAMigrationURI:
            "This is not an otpauth-migration:// link."
        case .missingData:
            "The transfer link has no data."
        case .invalidBase64:
            "The transfer link's data is not valid base64."
        }
    }
}

/// The `otpauth-migration://offline?data=…` wrapper around a `MigrationPayload`.
enum MigrationURI {
    static let scheme = "otpauth-migration"

    static func isMigrationURI(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix(scheme + "://")
    }

    // MARK: - Decoding

    static func accounts(from string: String) throws -> [Account] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme
        else {
            throw MigrationURIError.notAMigrationURI
        }

        guard let encoded = components.queryItems?
            .first(where: { $0.name.lowercased() == "data" })?.value,
            !encoded.isEmpty
        else {
            throw MigrationURIError.missingData
        }

        guard let payload = decodeBase64(encoded) else {
            throw MigrationURIError.invalidBase64
        }
        return try MigrationPayload.decode(payload)
    }

    /// Standard-alphabet base64, tolerating missing padding and the `+`→space
    /// substitution that some form decoders apply to query values.
    private static func decodeBase64(_ string: String) -> Data? {
        var candidates = [string]
        if string.contains(" ") {
            candidates.append(string.replacingOccurrences(of: " ", with: "+"))
        }
        // Also accept the URL-safe alphabet, which some tools emit.
        candidates.append(
            string.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
        )

        for candidate in candidates {
            var padded = candidate
            let remainder = padded.count % 4
            if remainder > 0 {
                padded += String(repeating: "=", count: 4 - remainder)
            }
            if let data = Data(base64Encoded: padded), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    // MARK: - Encoding

    /// One URI per batch. `+`, `/` and `=` are all query-significant, so the base64
    /// must be percent-encoded; encoding everything but alphanumerics is the safe choice.
    static func uris(
        for accounts: [Account]
    ) -> (uris: [String], rejected: [MigrationPayload.ExportRejection]) {
        let (batches, rejected) = MigrationPayload.encode(accounts: accounts)
        let uris = batches.map { batch -> String in
            let base64 = batch.payload.base64EncodedString()
            let escaped =
                base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64
            return "\(scheme)://offline?data=\(escaped)"
        }
        return (uris, rejected)
    }
}
