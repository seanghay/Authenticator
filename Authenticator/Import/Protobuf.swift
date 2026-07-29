import Foundation

/// Just enough protocol-buffer wire format to read and write Google Authenticator's
/// migration payload. Adding a dependency for one message would be disproportionate.
enum ProtobufError: LocalizedError, Equatable {
    case truncated
    case unsupportedWireType(Int)
    case malformedVarint

    var errorDescription: String? {
        switch self {
        case .truncated: "The data ended unexpectedly."
        case .unsupportedWireType(let type): "Unsupported protobuf wire type \(type)."
        case .malformedVarint: "A protobuf number was malformed."
        }
    }
}

struct ProtobufWriter {
    private(set) var data = Data()

    mutating func varint(_ value: UInt64) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            data.append(byte)
        } while remaining != 0
    }

    mutating func tag(field: Int, wireType: UInt8) {
        varint(UInt64(field) << 3 | UInt64(wireType))
    }

    /// proto3 omits fields at their default value, and so does Google Authenticator.
    mutating func varintField(_ field: Int, _ value: UInt64) {
        guard value != 0 else { return }
        tag(field: field, wireType: 0)
        varint(value)
    }

    mutating func bytesField(_ field: Int, _ bytes: Data) {
        guard !bytes.isEmpty else { return }
        tag(field: field, wireType: 2)
        varint(UInt64(bytes.count))
        data.append(bytes)
    }

    mutating func stringField(_ field: Int, _ string: String) {
        bytesField(field, Data(string.utf8))
    }

    mutating func messageField(_ field: Int, _ writer: ProtobufWriter) {
        messageBytes(field, writer.data)
    }

    /// Writes an already-encoded sub-message. Unlike `bytesField` this does not skip
    /// empty input, because an empty message is still a present repeated element.
    mutating func messageBytes(_ field: Int, _ encoded: Data) {
        tag(field: field, wireType: 2)
        varint(UInt64(encoded.count))
        data.append(encoded)
    }
}

enum ProtobufValue {
    case varint(UInt64)
    case bytes(Data)
}

/// A forward-only cursor over encoded bytes.
struct ProtobufReader {
    private let data: Data
    private var index: Data.Index

    init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    var isAtEnd: Bool { index >= data.endIndex }

    mutating func next() throws -> (field: Int, value: ProtobufValue)? {
        guard !isAtEnd else { return nil }

        let key = try readVarint()
        let field = Int(key >> 3)
        let wireType = UInt8(key & 0x07)

        switch wireType {
        case 0:
            return (field, .varint(try readVarint()))
        case 1:
            return (field, .bytes(try readBytes(count: 8)))
        case 2:
            let length = Int(try readVarint())
            return (field, .bytes(try readBytes(count: length)))
        case 5:
            return (field, .bytes(try readBytes(count: 4)))
        default:
            // Wire types 3 and 4 are the deprecated group encoding; nothing emits them.
            throw ProtobufError.unsupportedWireType(Int(wireType))
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < data.endIndex else { throw ProtobufError.truncated }
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            guard shift < 64 else { throw ProtobufError.malformedVarint }
        }
        return result
    }

    private mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else {
            throw ProtobufError.truncated
        }
        let end = data.index(index, offsetBy: count)
        defer { index = end }
        return Data(data[index..<end])
    }
}
