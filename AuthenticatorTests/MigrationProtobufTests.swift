import Foundation
import Testing

@testable import Authenticator

struct MigrationProtobufTests {
    // MARK: - Wire format

    @Test("Varints encode to the canonical byte sequences")
    func varintEncoding() {
        var writer = ProtobufWriter()
        writer.varint(0)
        writer.varint(1)
        writer.varint(127)
        writer.varint(128)
        writer.varint(300)
        #expect(Array(writer.data) == [0x00, 0x01, 0x7F, 0x80, 0x01, 0xAC, 0x02])
    }

    @Test("Every wire type can be skipped, including ones we never emit")
    func skipsUnknownFields() throws {
        let raw = Data([
            0x4A, 0x03, 0x61, 0x62, 0x63,  // field 9, wire 2 (length-delimited "abc")
            0x55, 0xDE, 0xAD, 0xBE, 0xEF,  // field 10, wire 5 (fixed32)
            0x59, 0, 1, 2, 3, 4, 5, 6, 7,  // field 11, wire 1 (fixed64)
            0x60, 0xAC, 0x02,  // field 12, wire 0 (varint 300)
        ])

        var reader = ProtobufReader(raw)
        var fields: [Int] = []
        while let (field, _) = try reader.next() {
            fields.append(field)
        }
        #expect(fields == [9, 10, 11, 12])
    }

    @Test("A payload padded with unknown fields still yields its accounts")
    func decodeIgnoresUnknownFields() throws {
        let account = Account(issuer: "A", label: "a", secret: Data("secret!!".utf8))
        let (batches, _) = MigrationPayload.encode(accounts: [account], batchID: 1)

        var padded = try #require(batches.first).payload
        padded.append(contentsOf: [0x4A, 0x03, 0x61, 0x62, 0x63])  // field 9, wire 2
        padded.append(contentsOf: [0x55, 0xDE, 0xAD, 0xBE, 0xEF])  // field 10, wire 5

        let decoded = try MigrationPayload.decode(padded)
        #expect(decoded.count == 1)
        #expect(decoded[0].secret == account.secret)
    }

    @Test("Group wire types are rejected rather than silently mis-parsed")
    func rejectsGroupWireTypes() {
        // field 1, wire 3 (start group) — deprecated and never emitted in practice.
        var reader = ProtobufReader(Data([0x0B]))
        #expect(throws: ProtobufError.unsupportedWireType(3)) { _ = try reader.next() }
    }

    // MARK: - Golden bytes

    /// A pure round-trip would agree with itself even if every field number were wrong.
    /// This pins the actual encoding.
    @Test("A single-account payload encodes to the expected bytes")
    func goldenEncoding() {
        let account = Account(
            issuer: "ACME",
            label: "alice",
            secret: Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]),  // "Hello"
            algorithm: .sha1,
            digits: 6,
            period: 30,
            kind: .totp
        )
        let (batches, rejected) = MigrationPayload.encode(accounts: [account], batchID: 7)
        #expect(rejected.isEmpty)
        #expect(batches.count == 1)

        let expected: [UInt8] = [
            0x0A, 0x1A,  // field 1 (otp_parameters), length 26
            0x0A, 0x05, 0x48, 0x65, 0x6C, 0x6C, 0x6F,  // secret = "Hello"
            0x12, 0x05, 0x61, 0x6C, 0x69, 0x63, 0x65,  // name = "alice"
            0x1A, 0x04, 0x41, 0x43, 0x4D, 0x45,  // issuer = "ACME"
            0x20, 0x01,  // algorithm = SHA1 (1)
            0x28, 0x01,  // digits = SIX (1)
            0x30, 0x02,  // type = TOTP (2)
            0x10, 0x01,  // version = 1
            0x18, 0x01,  // batch_size = 1
            // batch_index = 0 is omitted, as proto3 skips defaults
            0x28, 0x07,  // batch_id = 7
        ]
        #expect(Array(batches[0].payload) == expected)
    }

    // MARK: - Round-trips

    @Test("Accounts survive an encode/decode cycle")
    func structuralRoundTrip() throws {
        let accounts = [
            Account(issuer: "A", label: "one", secret: Data("secret01".utf8), algorithm: .sha1),
            Account(
                issuer: "B", label: "two", secret: Data("secret02".utf8),
                algorithm: .sha256, digits: 8
            ),
            Account(
                issuer: "C", label: "three", secret: Data("secret03".utf8), algorithm: .sha512
            ),
            Account(
                issuer: "", label: "no-issuer", secret: Data("secret04".utf8)
            ),
            Account(
                issuer: "D", label: "counter", secret: Data("secret05".utf8),
                kind: .hotp, counter: 99
            ),
        ]

        let (batches, rejected) = MigrationPayload.encode(accounts: accounts, batchID: 1)
        #expect(rejected.isEmpty)

        let decoded = try batches.flatMap { try MigrationPayload.decode($0.payload) }
        #expect(decoded.count == accounts.count)

        for (original, result) in zip(accounts, decoded) {
            #expect(result.issuer == original.issuer)
            #expect(result.label == original.label)
            #expect(result.secret == original.secret)
            #expect(result.algorithm == original.algorithm)
            #expect(result.digits == original.digits)
            #expect(result.kind == original.kind)
            #expect(result.counter == original.counter)
        }
    }

    @Test("Accounts the format cannot express are reported, not silently dropped")
    func rejections() {
        let sevenDigits = Account(issuer: "A", label: "a", secret: Data("x".utf8), digits: 7)
        let oddPeriod = Account(issuer: "B", label: "b", secret: Data("x".utf8), period: 60)

        let (batches, rejected) = MigrationPayload.encode(
            accounts: [sevenDigits, oddPeriod],
            batchID: 1
        )
        #expect(batches.isEmpty)
        #expect(rejected.count == 2)
        #expect(rejected.contains { $0.account.id == sevenDigits.id })
        #expect(rejected.contains { $0.account.id == oddPeriod.id })
    }

    @Test("Batching splits large exports and keeps consistent metadata")
    func batching() throws {
        let accounts = (0..<200).map { index in
            Account(
                issuer: "Issuer \(index)",
                label: "account\(index)@example.com",
                secret: Data(repeating: UInt8(index % 251), count: 20)
            )
        }

        let (batches, rejected) = MigrationPayload.encode(accounts: accounts, batchID: 4242)
        #expect(rejected.isEmpty)
        #expect(batches.count > 1, "200 accounts should not fit in one QR code")

        for (index, batch) in batches.enumerated() {
            #expect(batch.index == index)
            #expect(batch.total == batches.count)
        }

        let decoded = try batches.flatMap { try MigrationPayload.decode($0.payload) }
        #expect(decoded.count == accounts.count)
        #expect(Set(decoded.map(\.identityKey)) == Set(accounts.map(\.identityKey)))
    }

    @Test("The 'Issuer:' prefix in name is stripped when it duplicates issuer")
    func stripsRedundantPrefix() throws {
        var writer = ProtobufWriter()
        var parameters = ProtobufWriter()
        parameters.bytesField(1, Data("secret!!".utf8))
        parameters.stringField(2, "GitHub:alice")
        parameters.stringField(3, "GitHub")
        parameters.varintField(4, 1)
        parameters.varintField(5, 1)
        parameters.varintField(6, 2)
        writer.messageField(1, parameters)

        let accounts = try MigrationPayload.decode(writer.data)
        #expect(accounts.count == 1)
        #expect(accounts[0].issuer == "GitHub")
        #expect(accounts[0].label == "alice")
    }

    // MARK: - URI layer

    @Test("Transfer URIs percent-encode the base64 payload")
    func uriEncoding() throws {
        let accounts = (0..<3).map { index in
            Account(
                issuer: "Issuer\(index)",
                label: "user\(index)",
                secret: Data(repeating: UInt8(index + 1), count: 20)
            )
        }

        let (uris, rejected) = MigrationURI.uris(for: accounts)
        #expect(rejected.isEmpty)
        #expect(uris.count == 1)

        let uri = try #require(uris.first)
        #expect(uri.hasPrefix("otpauth-migration://offline?data="))

        let dataPart = String(uri.dropFirst("otpauth-migration://offline?data=".count))
        // Raw +, / and = would be misread as query syntax.
        #expect(!dataPart.contains("+"))
        #expect(!dataPart.contains("/"))
        #expect(!dataPart.contains("="))

        let decoded = try MigrationURI.accounts(from: uri)
        #expect(Set(decoded.map(\.identityKey)) == Set(accounts.map(\.identityKey)))
    }

    @Test("Migration URIs are recognised regardless of case")
    func recognisesScheme() {
        #expect(MigrationURI.isMigrationURI("otpauth-migration://offline?data=AAA"))
        #expect(MigrationURI.isMigrationURI("OTPAUTH-MIGRATION://offline?data=AAA"))
        #expect(!MigrationURI.isMigrationURI("otpauth://totp/a?secret=AAA"))
    }

    @Test("Unpadded base64 in a transfer link still decodes")
    func tolerantBase64() throws {
        let account = Account(issuer: "A", label: "a", secret: Data("secret!!".utf8))
        let (uris, _) = MigrationURI.uris(for: [account])
        let uri = try #require(uris.first)

        // Strip the percent-encoded padding a stricter producer might omit.
        let stripped = uri.replacingOccurrences(of: "%3D", with: "")
        let decoded = try MigrationURI.accounts(from: stripped)
        #expect(decoded.count == 1)
        #expect(decoded[0].secret == account.secret)
    }
}
