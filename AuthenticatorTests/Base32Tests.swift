import Foundation
import Testing

@testable import Authenticator

struct Base32Tests {
    @Test(
        "RFC 4648 section 10 vectors, unpadded",
        arguments: [
            ("", ""),
            ("f", "MY"),
            ("fo", "MZXQ"),
            ("foo", "MZXW6"),
            ("foob", "MZXW6YQ"),
            ("fooba", "MZXW6YTB"),
            ("foobar", "MZXW6YTBOI"),
        ]
    )
    func rfcVectors(plain: String, encoded: String) {
        #expect(Base32.encode(Data(plain.utf8)) == encoded)
        if !plain.isEmpty {
            let decoded = Base32.decode(encoded)
            #expect(decoded == Data(plain.utf8))
        }
    }

    @Test("The 20-byte TOTP test seed encodes to the well-known string")
    func totpSeed() {
        let encoded = Base32.encode(Data("12345678901234567890".utf8))
        #expect(encoded == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    }

    @Test("Decoding accepts padding, lowercase and separators")
    func lenientDecoding() {
        let canonical = Base32.decode("MZXW6YTBOI")
        #expect(Base32.decode("mzxw6ytboi") == canonical)
        #expect(Base32.decode("MZXW-6YTB-OI") == canonical)
        #expect(Base32.decode("MZXW 6YTB OI") == canonical)
        #expect(Base32.decode("MZXW6YTBOI======") == canonical)
    }

    @Test("Decoding rejects characters outside the alphabet")
    func rejectsInvalid() {
        // 0, 1, 8 and 9 are deliberately absent from the base32 alphabet.
        #expect(Base32.decode("MZXW6YTB01") == nil)
        #expect(Base32.decode("!!!!") == nil)
        #expect(Base32.decode("") == nil)
    }

    @Test("Round-trips arbitrary byte lengths")
    func roundTrip() {
        for length in 1...64 {
            let bytes = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
            let decoded = Base32.decode(Base32.encode(bytes))
            #expect(decoded == bytes, "length \(length)")
        }
    }
}
