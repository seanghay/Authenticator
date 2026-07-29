import Foundation

/// RFC 4648 base32, the encoding every authenticator uses for `secret=` in `otpauth://`.
///
/// Encoding emits uppercase and no `=` padding, matching what Google Authenticator
/// produces. Decoding is deliberately lenient — secrets get copied out of web pages
/// with spaces and dashes in them, and casing is not meaningful.
enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    /// Reverse lookup table: byte value -> 5-bit group, or 0xFF for "not a base32 char".
    private static let decodeTable: [UInt8] = {
        var table = [UInt8](repeating: 0xFF, count: 256)
        for (index, character) in alphabet.enumerated() {
            table[Int(character)] = UInt8(index)
            // Accept lowercase too.
            table[Int(character | 0x20)] = UInt8(index)
        }
        return table
    }()

    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }

        var output = [UInt8]()
        output.reserveCapacity((data.count * 8 + 4) / 5)

        var accumulator = 0
        var bitCount = 0
        for byte in data {
            accumulator = (accumulator << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[(accumulator >> bitCount) & 0x1F])
            }
        }
        // Left-align whatever is left over into a final group.
        if bitCount > 0 {
            output.append(alphabet[(accumulator << (5 - bitCount)) & 0x1F])
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Returns nil if the input contains characters that are neither base32 nor
    /// recognised separators, or if it decodes to nothing.
    static func decode(_ string: String) -> Data? {
        var output = Data()
        var accumulator = 0
        var bitCount = 0

        for byte in string.utf8 {
            switch byte {
            case UInt8(ascii: "="), UInt8(ascii: " "), UInt8(ascii: "-"),
                 UInt8(ascii: "_"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
                 UInt8(ascii: "\t"):
                continue
            default:
                break
            }

            let value = decodeTable[Int(byte)]
            guard value != 0xFF else { return nil }

            accumulator = (accumulator << 5) | Int(value)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((accumulator >> bitCount) & 0xFF))
            }
        }

        // Any remaining bits are the zero padding of the final group. If they are
        // non-zero the input was truncated mid-byte rather than merely unpadded.
        if bitCount > 0, (accumulator & ((1 << bitCount) - 1)) != 0 {
            return nil
        }
        return output.isEmpty ? nil : output
    }
}
