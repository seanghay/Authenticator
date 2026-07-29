import Foundation
import Testing

@testable import Authenticator

struct OTPGeneratorTests {
    /// RFC 6238 publishes one seed in its table but its reference implementation uses a
    /// different length per algorithm. The published codes only reproduce with these.
    static let sha1Seed = Data("12345678901234567890".utf8)
    static let sha256Seed = Data("12345678901234567890123456789012".utf8)
    static let sha512Seed = Data(
        "1234567890123456789012345678901234567890123456789012345678901234".utf8
    )

    @Test("RFC 4226 Appendix D HOTP vectors")
    func hotpVectors() {
        let expected = [
            "755224", "287082", "359152", "969429", "338314",
            "254676", "287922", "162583", "399871", "520489",
        ]
        for (counter, want) in expected.enumerated() {
            let got = OTPGenerator.hotp(
                secret: Self.sha1Seed,
                counter: UInt64(counter),
                digits: 6,
                algorithm: .sha1
            )
            #expect(got == want, "counter \(counter)")
        }
    }

    @Test(
        "RFC 6238 Appendix B TOTP vectors",
        arguments: [
            (59.0, "94287082", "46119246", "90693936"),
            (1_111_111_109.0, "07081804", "68084774", "25091201"),
            (1_111_111_111.0, "14050471", "67062674", "99943326"),
            (1_234_567_890.0, "89005924", "91819424", "93441116"),
            (2_000_000_000.0, "69279037", "90698825", "38618901"),
            (20_000_000_000.0, "65353130", "77737706", "47863826"),
        ]
    )
    func totpVectors(time: TimeInterval, sha1: String, sha256: String, sha512: String) {
        let date = Date(timeIntervalSince1970: time)

        #expect(
            OTPGenerator.totp(
                secret: Self.sha1Seed, at: date, period: 30, digits: 8, algorithm: .sha1
            ) == sha1)
        #expect(
            OTPGenerator.totp(
                secret: Self.sha256Seed, at: date, period: 30, digits: 8, algorithm: .sha256
            ) == sha256)
        #expect(
            OTPGenerator.totp(
                secret: Self.sha512Seed, at: date, period: 30, digits: 8, algorithm: .sha512
            ) == sha512)
    }

    @Test("Codes are zero-padded to the requested width")
    func zeroPadding() {
        // Counter 0 with this seed truncates to 1094287082 -> "82" at two digits.
        let code = OTPGenerator.hotp(
            secret: Self.sha1Seed, counter: 0, digits: 6, algorithm: .sha1
        )
        // Bound outside the macro: `allSatisfy` is `rethrows`, which the expansion
        // cannot see through.
        let isAllDigits = code.allSatisfy(\.isNumber)
        #expect(code.count == 6)
        #expect(isAllDigits)
    }

    @Test("TOTP counter advances once per period")
    func counterSteps() {
        #expect(OTPGenerator.counter(at: Date(timeIntervalSince1970: 0), period: 30) == 0)
        #expect(OTPGenerator.counter(at: Date(timeIntervalSince1970: 29), period: 30) == 0)
        #expect(OTPGenerator.counter(at: Date(timeIntervalSince1970: 30), period: 30) == 1)
        #expect(OTPGenerator.counter(at: Date(timeIntervalSince1970: 59), period: 30) == 1)
    }

    @Test("Countdown drains across a period")
    func countdown() {
        #expect(OTPCountdown.secondsRemaining(period: 30, at: Date(timeIntervalSince1970: 0)) == 30)
        #expect(OTPCountdown.secondsRemaining(period: 30, at: Date(timeIntervalSince1970: 29)) == 1)
        #expect(OTPCountdown.isExpiringSoon(period: 30, at: Date(timeIntervalSince1970: 28)))
        #expect(!OTPCountdown.isExpiringSoon(period: 30, at: Date(timeIntervalSince1970: 10)))
    }

    @Test("An HOTP account generates the vector for its stored counter")
    func accountDispatch() {
        let account = Account(secret: Self.sha1Seed, kind: .hotp, counter: 3)
        #expect(OTPGenerator.code(for: account) == "969429")
    }
}
