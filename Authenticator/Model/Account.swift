import Foundation

/// Which OTP standard an account uses.
enum OTPKind: String, Codable, CaseIterable, Sendable {
    case totp
    case hotp

    var displayName: String {
        switch self {
        case .totp: "Time-based (TOTP)"
        case .hotp: "Counter-based (HOTP)"
        }
    }
}

/// The HMAC hash backing code generation.
enum OTPAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha1
    case sha256
    case sha512

    /// The spelling used in `otpauth://` URIs.
    var uriValue: String {
        switch self {
        case .sha1: "SHA1"
        case .sha256: "SHA256"
        case .sha512: "SHA512"
        }
    }

    init?(uriValue: String) {
        switch uriValue.uppercased() {
        case "SHA1": self = .sha1
        case "SHA256": self = .sha256
        case "SHA512": self = .sha512
        default: return nil
        }
    }
}

/// One stored credential.
///
/// `secret` holds the raw key bytes. Base32 is purely a transport encoding used by
/// `otpauth://` URIs and manual entry — it never appears in the model or on disk.
struct Account: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var issuer: String = ""
    var label: String = ""
    var secret: Data
    var algorithm: OTPAlgorithm = .sha1
    var digits: Int = 6
    var period: Int = 30
    var kind: OTPKind = .totp
    var counter: UInt64 = 0
    var createdAt: Date = Date()
    /// Explicit ordering, so a merge or re-import cannot silently reshuffle the list.
    var sortIndex: Int = 0

    /// What the list shows as the primary line.
    var displayTitle: String {
        if !issuer.isEmpty { return issuer }
        if !label.isEmpty { return label }
        return "Unnamed"
    }

    /// The secondary line — omitted when it would just repeat the title.
    var displaySubtitle: String? {
        guard !label.isEmpty, !issuer.isEmpty else { return nil }
        return label
    }

    /// Fields that make two entries "the same account" for de-duplication on import.
    var identityKey: String {
        "\(issuer.lowercased())\u{1}\(label.lowercased())\u{1}\(secret.base64EncodedString())"
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return issuer.localizedCaseInsensitiveContains(query)
            || label.localizedCaseInsensitiveContains(query)
    }
}

extension Account {
    /// Digit counts we accept. Six is near-universal; eight shows up in banking and AWS.
    static let allowedDigits = 6...8
}
