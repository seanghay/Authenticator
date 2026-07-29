import Foundation
import Testing

@testable import Authenticator

struct OTPAuthURITests {
    @Test("Parses a canonical Google-style URI")
    func canonical() throws {
        let account = try OTPAuthURI.parse(
            "otpauth://totp/ACME%20Co:john@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60"
        )
        #expect(account.issuer == "ACME Co")
        #expect(account.label == "john@example.com")
        #expect(account.algorithm == .sha256)
        #expect(account.digits == 8)
        #expect(account.period == 60)
        #expect(account.kind == .totp)
        #expect(account.secret == Base32.decode("JBSWY3DPEHPK3PXP"))
    }

    @Test("Applies defaults when optional parameters are absent")
    func defaults() throws {
        let account = try OTPAuthURI.parse("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP")
        #expect(account.issuer == "")
        #expect(account.label == "alice")
        #expect(account.algorithm == .sha1)
        #expect(account.digits == 6)
        #expect(account.period == 30)
    }

    @Test("Strips the leading space in an 'Issuer: account' label")
    func labelLeadingSpace() throws {
        let account = try OTPAuthURI.parse(
            "otpauth://totp/GitHub:%20user@host?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(account.issuer == "GitHub")
        #expect(account.label == "user@host")
    }

    @Test("Splits the label on the first colon only")
    func firstColonOnly() throws {
        let account = try OTPAuthURI.parse(
            "otpauth://totp/Issuer:a:b:c?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(account.issuer == "Issuer")
        #expect(account.label == "a:b:c")
    }

    @Test("The issuer query parameter wins over the label prefix")
    func issuerQueryWins() throws {
        let account = try OTPAuthURI.parse(
            "otpauth://totp/Old:user?secret=JBSWY3DPEHPK3PXP&issuer=New"
        )
        #expect(account.issuer == "New")
        #expect(account.label == "user")
    }

    @Test("Reads HOTP counters")
    func hotp() throws {
        let account = try OTPAuthURI.parse(
            "otpauth://hotp/bank?secret=JBSWY3DPEHPK3PXP&counter=42"
        )
        #expect(account.kind == .hotp)
        #expect(account.counter == 42)
    }

    @Test("Accepts lowercase and unpadded secrets")
    func lenientSecret() throws {
        let account = try OTPAuthURI.parse("otpauth://totp/a?secret=jbswy3dpehpk3pxp")
        #expect(account.secret == Base32.decode("JBSWY3DPEHPK3PXP"))
    }

    @Test(
        "Rejects malformed URIs",
        arguments: [
            "https://example.com",
            "otpauth://sms/a?secret=JBSWY3DPEHPK3PXP",
            "otpauth://totp/a",
            "otpauth://totp/a?secret=",
            "otpauth://totp/a?secret=1111",
            "otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&digits=5",
            "otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&algorithm=MD5",
        ]
    )
    func rejectsMalformed(uri: String) {
        #expect(throws: (any Error).self) { try OTPAuthURI.parse(uri) }
    }

    @Test("Parsing a serialized account is a fixed point")
    func roundTrip() throws {
        let originals = [
            Account(issuer: "GitHub", label: "user@host", secret: Data("secret!!".utf8)),
            Account(issuer: "", label: "bare", secret: Data("abcdefgh".utf8)),
            Account(
                issuer: "Ünïcodé Co", label: "a+b@c.d", secret: Data("12345678".utf8),
                algorithm: .sha512, digits: 8, period: 60
            ),
            Account(
                issuer: "Bank", label: "acct", secret: Data("hotpseed".utf8),
                kind: .hotp, counter: 42
            ),
        ]

        for original in originals {
            let uri = OTPAuthURI.string(for: original)
            let parsed = try OTPAuthURI.parse(uri)

            #expect(parsed.issuer == original.issuer, "\(uri)")
            #expect(parsed.label == original.label, "\(uri)")
            #expect(parsed.secret == original.secret, "\(uri)")
            #expect(parsed.algorithm == original.algorithm, "\(uri)")
            #expect(parsed.digits == original.digits, "\(uri)")
            #expect(parsed.kind == original.kind, "\(uri)")
            if original.kind == .totp {
                #expect(parsed.period == original.period, "\(uri)")
            } else {
                #expect(parsed.counter == original.counter, "\(uri)")
            }

            // Serializing again must produce identical bytes.
            #expect(OTPAuthURI.string(for: parsed) == uri)
        }
    }
}
