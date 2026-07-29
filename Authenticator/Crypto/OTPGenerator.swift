import CryptoKit
import Foundation

/// RFC 4226 (HOTP) and RFC 6238 (TOTP) code generation.
enum OTPGenerator {
    /// 10^n for n in 0...8, used by the final modulo step.
    private static let powersOfTen: [UInt32] = [
        1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000,
    ]

    /// RFC 4226 §5.3. Returns a zero-padded decimal string of length `digits`.
    static func hotp(
        secret: Data,
        counter: UInt64,
        digits: Int,
        algorithm: OTPAlgorithm
    ) -> String {
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let key = SymmetricKey(data: secret)

        let mac: Data =
            switch algorithm {
            case .sha1:
                Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
            case .sha256:
                Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
            case .sha512:
                Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
            }

        // Dynamic truncation: the low nibble of the last byte picks a 4-byte window.
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let truncated =
            (UInt32(mac[offset]) & 0x7F) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])

        let clampedDigits = min(max(digits, 1), powersOfTen.count - 1)
        let code = truncated % powersOfTen[clampedDigits]
        return String(format: "%0\(clampedDigits)u", code)
    }

    /// RFC 6238 — HOTP over the number of `period`-second steps since the Unix epoch.
    static func totp(
        secret: Data,
        at date: Date = Date(),
        period: Int,
        digits: Int,
        algorithm: OTPAlgorithm
    ) -> String {
        hotp(
            secret: secret,
            counter: counter(at: date, period: period),
            digits: digits,
            algorithm: algorithm
        )
    }

    static func counter(at date: Date, period: Int) -> UInt64 {
        let safePeriod = max(period, 1)
        // Dates before 1970 have no meaning here; clamp rather than trap on overflow.
        let seconds = max(date.timeIntervalSince1970, 0)
        return UInt64(seconds) / UInt64(safePeriod)
    }

    /// The current code for an account, dispatching on its kind.
    static func code(for account: Account, at date: Date = Date()) -> String {
        switch account.kind {
        case .totp:
            totp(
                secret: account.secret,
                at: date,
                period: account.period,
                digits: account.digits,
                algorithm: account.algorithm
            )
        case .hotp:
            hotp(
                secret: account.secret,
                counter: account.counter,
                digits: account.digits,
                algorithm: account.algorithm
            )
        }
    }
}
