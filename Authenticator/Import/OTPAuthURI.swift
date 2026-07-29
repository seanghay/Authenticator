import Foundation

enum OTPAuthURIError: LocalizedError, Equatable {
    case notAnOTPAuthURI
    case unknownType(String)
    case missingSecret
    case invalidSecret
    case unsupportedAlgorithm(String)
    case invalidDigits(String)

    var errorDescription: String? {
        switch self {
        case .notAnOTPAuthURI:
            "This is not an otpauth:// link."
        case .unknownType(let type):
            "Unsupported OTP type “\(type)”. Only totp and hotp are supported."
        case .missingSecret:
            "The link has no secret."
        case .invalidSecret:
            "The secret is not valid base32."
        case .unsupportedAlgorithm(let name):
            "Unsupported algorithm “\(name)”. Use SHA1, SHA256 or SHA512."
        case .invalidDigits(let value):
            "Unsupported digit count “\(value)”. Use 6, 7 or 8."
        }
    }
}

/// Parser and serializer for the de-facto `otpauth://` key URI format.
///
///     otpauth://totp/Issuer:account?secret=BASE32&issuer=Issuer&algorithm=SHA1&digits=6&period=30
enum OTPAuthURI {
    static let scheme = "otpauth"

    /// Characters left literal in the label. Percent-encoding the rest keeps the URI
    /// unambiguous while staying byte-identical to what other authenticators emit.
    private static let labelAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~@")
        return set
    }()

    // MARK: - Parsing

    static func parse(_ string: String) throws -> Account {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme
        else {
            throw OTPAuthURIError.notAnOTPAuthURI
        }

        guard let host = components.host?.lowercased(),
              let kind = OTPKind(rawValue: host)
        else {
            throw OTPAuthURIError.unknownType(components.host ?? "")
        }

        let queryItems = components.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name }?.value
        }

        guard let secretText = value("secret"), !secretText.isEmpty else {
            throw OTPAuthURIError.missingSecret
        }
        guard let secret = Base32.decode(secretText) else {
            throw OTPAuthURIError.invalidSecret
        }

        // `URLComponents.path` is already percent-decoded.
        var issuer = ""
        var label = components.path
        if label.hasPrefix("/") { label.removeFirst() }

        // The label conventionally carries an "Issuer:" prefix. Split on the first
        // colon only — account names legitimately contain colons after that.
        if let colonIndex = label.firstIndex(of: ":") {
            issuer = String(label[label.startIndex..<colonIndex])
            label = String(label[label.index(after: colonIndex)...])
            // "Issuer:%20user@host" is common; the space is not part of the name.
            label = label.trimmingCharacters(in: .whitespaces)
        }

        // When both are present the query parameter is authoritative.
        if let queryIssuer = value("issuer"), !queryIssuer.isEmpty {
            issuer = queryIssuer
        }

        var algorithm = OTPAlgorithm.sha1
        if let algorithmText = value("algorithm"), !algorithmText.isEmpty {
            guard let parsed = OTPAlgorithm(uriValue: algorithmText) else {
                throw OTPAuthURIError.unsupportedAlgorithm(algorithmText)
            }
            algorithm = parsed
        }

        var digits = 6
        if let digitsText = value("digits"), !digitsText.isEmpty {
            guard let parsed = Int(digitsText), Account.allowedDigits.contains(parsed) else {
                throw OTPAuthURIError.invalidDigits(digitsText)
            }
            digits = parsed
        }

        var period = 30
        if let periodText = value("period"), let parsed = Int(periodText), parsed > 0 {
            period = parsed
        }

        // Absent counters are treated as zero — some issuers omit it on first enrolment.
        let counter = UInt64(value("counter") ?? "") ?? 0

        return Account(
            issuer: issuer,
            label: label,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: period,
            kind: kind,
            counter: counter
        )
    }

    // MARK: - Serializing

    /// Emits every parameter, including ones at their default, because some
    /// authenticators guess badly when a field is missing.
    static func string(for account: Account) -> String {
        var path = ""
        if !account.issuer.isEmpty {
            path += encode(account.issuer) + ":"
        }
        path += encode(account.label)

        var query = "secret=\(Base32.encode(account.secret))"
        if !account.issuer.isEmpty {
            query += "&issuer=\(encode(account.issuer))"
        }
        query += "&algorithm=\(account.algorithm.uriValue)"
        query += "&digits=\(account.digits)"
        switch account.kind {
        case .totp: query += "&period=\(account.period)"
        case .hotp: query += "&counter=\(account.counter)"
        }

        return "\(scheme)://\(account.kind.rawValue)/\(path)?\(query)"
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: labelAllowed) ?? value
    }
}
