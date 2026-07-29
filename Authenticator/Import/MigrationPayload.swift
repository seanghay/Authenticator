import Foundation

/// Google Authenticator's batch transfer format.
///
/// The schema is not published by Google; these field numbers and enum values are the
/// well-corroborated reverse-engineered ones:
///
///     message OtpParameters {
///       bytes secret = 1; string name = 2; string issuer = 3;
///       Algorithm algorithm = 4; DigitCount digits = 5; OtpType type = 6; int64 counter = 7;
///     }
///     message MigrationPayload {
///       repeated OtpParameters otp_parameters = 1;
///       int32 version = 2; int32 batch_size = 3; int32 batch_index = 4; int32 batch_id = 5;
///     }
///
/// Two traps worth naming: `secret` is raw bytes rather than base32, and `digits` is an
/// *enum* (SIX = 1, EIGHT = 2) rather than the literal digit count.
enum MigrationPayload {
    // MARK: - Enum mappings

    enum Algorithm: UInt64 {
        case unspecified = 0
        case sha1 = 1
        case sha256 = 2
        case sha512 = 3
        case md5 = 4

        init(_ algorithm: OTPAlgorithm) {
            switch algorithm {
            case .sha1: self = .sha1
            case .sha256: self = .sha256
            case .sha512: self = .sha512
            }
        }

        /// Unspecified means SHA-1 in practice; MD5 we cannot generate codes for.
        var otpAlgorithm: OTPAlgorithm? {
            switch self {
            case .unspecified, .sha1: .sha1
            case .sha256: .sha256
            case .sha512: .sha512
            case .md5: nil
            }
        }
    }

    enum DigitCount: UInt64 {
        case unspecified = 0
        case six = 1
        case eight = 2

        init?(digits: Int) {
            switch digits {
            case 6: self = .six
            case 8: self = .eight
            default: return nil  // 7 digits cannot be expressed in this format.
            }
        }

        var digits: Int {
            switch self {
            case .unspecified, .six: 6
            case .eight: 8
            }
        }
    }

    enum OtpType: UInt64 {
        case unspecified = 0
        case hotp = 1
        case totp = 2

        init(_ kind: OTPKind) {
            switch kind {
            case .hotp: self = .hotp
            case .totp: self = .totp
            }
        }

        var kind: OTPKind {
            switch self {
            case .hotp: .hotp
            case .unspecified, .totp: .totp
            }
        }
    }

    /// An account that cannot be represented in the migration format.
    struct ExportRejection: Identifiable {
        var id: UUID { account.id }
        let account: Account
        let reason: String
    }

    struct Batch {
        let payload: Data
        let index: Int
        let total: Int
    }

    // MARK: - Decoding

    /// Decodes one migration payload into accounts. Entries that cannot be represented
    /// (MD5, empty secret) are skipped rather than failing the whole import.
    static func decode(_ data: Data) throws -> [Account] {
        var reader = ProtobufReader(data)
        var accounts: [Account] = []

        while let (field, value) = try reader.next() {
            // Fields 2-5 (version, batch metadata) are read and ignored: batch bookkeeping
            // matters to the *sender*, and validating `version` would only reject payloads
            // from future versions we would otherwise parse fine.
            guard field == 1, case .bytes(let chunk) = value else { continue }
            if let account = try decodeParameters(chunk) {
                accounts.append(account)
            }
        }
        return accounts
    }

    private static func decodeParameters(_ data: Data) throws -> Account? {
        var reader = ProtobufReader(data)

        var secret = Data()
        var name = ""
        var issuer = ""
        var algorithm = Algorithm.unspecified
        var digitCount = DigitCount.unspecified
        var type = OtpType.unspecified
        var counter: UInt64 = 0

        while let (field, value) = try reader.next() {
            switch (field, value) {
            case (1, .bytes(let bytes)):
                secret = bytes
            case (2, .bytes(let bytes)):
                name = String(decoding: bytes, as: UTF8.self)
            case (3, .bytes(let bytes)):
                issuer = String(decoding: bytes, as: UTF8.self)
            case (4, .varint(let raw)):
                algorithm = Algorithm(rawValue: raw) ?? .unspecified
            case (5, .varint(let raw)):
                digitCount = DigitCount(rawValue: raw) ?? .unspecified
            case (6, .varint(let raw)):
                type = OtpType(rawValue: raw) ?? .unspecified
            case (7, .varint(let raw)):
                counter = raw
            default:
                continue  // Unknown fields are skipped, per proto3.
            }
        }

        guard !secret.isEmpty, let otpAlgorithm = algorithm.otpAlgorithm else { return nil }

        // `name` often repeats the issuer as an "Issuer:account" prefix.
        var label = name
        if let colonIndex = label.firstIndex(of: ":") {
            let prefix = String(label[label.startIndex..<colonIndex])
            if issuer.isEmpty || prefix.caseInsensitiveCompare(issuer) == .orderedSame {
                if issuer.isEmpty { issuer = prefix }
                label = String(label[label.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return Account(
            issuer: issuer,
            label: label,
            secret: secret,
            algorithm: otpAlgorithm,
            digits: digitCount.digits,
            period: 30,  // The format has no period field; 30s is assumed.
            kind: type.kind,
            counter: counter
        )
    }

    // MARK: - Encoding

    /// Splits accounts across as many payloads as needed and encodes each one.
    ///
    /// - Parameter maximumPayloadBytes: budget per QR code before base64 expansion.
    static func encode(
        accounts: [Account],
        maximumPayloadBytes: Int = 1_400,
        batchID: UInt64 = UInt64.random(in: 1...UInt64(Int32.max))
    ) -> (batches: [Batch], rejected: [ExportRejection]) {
        var encodedAccounts: [Data] = []
        var rejected: [ExportRejection] = []

        for account in accounts {
            guard let digitCount = DigitCount(digits: account.digits) else {
                rejected.append(
                    ExportRejection(
                        account: account,
                        reason: "\(account.digits)-digit codes cannot be transferred; the format only supports 6 or 8."
                    ))
                continue
            }
            if account.kind == .totp, account.period != 30 {
                rejected.append(
                    ExportRejection(
                        account: account,
                        reason: "A \(account.period)-second period cannot be transferred; the format assumes 30 seconds."
                    ))
                continue
            }
            encodedAccounts.append(encodeParameters(account, digitCount: digitCount))
        }

        // Greedily pack into groups that fit the budget.
        var groups: [[Data]] = []
        var current: [Data] = []
        var currentSize = 0
        for encoded in encodedAccounts {
            // 1 tag byte + up to 2 length bytes of framing per entry.
            let cost = encoded.count + 3
            if !current.isEmpty, currentSize + cost > maximumPayloadBytes {
                groups.append(current)
                current = []
                currentSize = 0
            }
            current.append(encoded)
            currentSize += cost
        }
        if !current.isEmpty { groups.append(current) }

        let total = groups.count
        let batches = groups.enumerated().map { index, group in
            var writer = ProtobufWriter()
            for encoded in group {
                writer.messageBytes(1, encoded)
            }
            writer.varintField(2, 1)  // version
            writer.varintField(3, UInt64(total))
            writer.varintField(4, UInt64(index))
            writer.varintField(5, batchID)
            return Batch(payload: writer.data, index: index, total: total)
        }

        return (batches, rejected)
    }

    private static func encodeParameters(_ account: Account, digitCount: DigitCount) -> Data {
        var writer = ProtobufWriter()
        writer.bytesField(1, account.secret)
        // Emit the bare account name; `issuer` carries the issuer on its own field.
        writer.stringField(2, account.label.isEmpty ? account.issuer : account.label)
        writer.stringField(3, account.issuer)
        writer.varintField(4, Algorithm(account.algorithm).rawValue)
        writer.varintField(5, digitCount.rawValue)
        writer.varintField(6, OtpType(account.kind).rawValue)
        if account.kind == .hotp {
            writer.varintField(7, account.counter)
        }
        return writer.data
    }
}
