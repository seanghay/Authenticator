import CoreGraphics
import Foundation
import Testing

@testable import Authenticator

struct QRPipelineTests {
    @Test("A rendered otpauth URI reads back identically")
    func renderThenDecode() async throws {
        let account = Account(
            issuer: "ACME Co",
            label: "alice@example.com",
            secret: Data("secret!!".utf8),
            algorithm: .sha256,
            digits: 8
        )
        let uri = OTPAuthURI.string(for: account)
        let image = try #require(QRCodeRenderer.image(for: uri, size: 512))

        let payloads = await QRImageDecoder.payloads(in: image)
        #expect(payloads == [uri])
    }

    @Test("Decoding survives being rendered at different scales", arguments: [128, 256, 1024])
    func scaleTolerance(size: Int) async throws {
        let uri = "otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&issuer=Test&algorithm=SHA1&digits=6&period=30"
        let image = try #require(QRCodeRenderer.image(for: uri, size: CGFloat(size)))

        let payloads = await QRImageDecoder.payloads(in: image)
        #expect(payloads.first == uri)
    }

    @Test("A transfer QR round-trips through render and decode")
    func migrationRoundTrip() async throws {
        let accounts = (0..<5).map { index in
            Account(
                issuer: "Issuer\(index)",
                label: "user\(index)@example.com",
                secret: Data(repeating: UInt8(index + 1), count: 20)
            )
        }
        let (uris, rejected) = MigrationURI.uris(for: accounts)
        #expect(rejected.isEmpty)

        var decoded: [Account] = []
        for uri in uris {
            let image = try #require(QRCodeRenderer.image(for: uri, size: 640))
            let payloads = await QRImageDecoder.payloads(in: image)
            let payload = try #require(payloads.first)
            #expect(payload == uri)
            decoded.append(contentsOf: try MigrationURI.accounts(from: payload))
        }

        #expect(Set(decoded.map(\.identityKey)) == Set(accounts.map(\.identityKey)))
    }

    @Test("An image with no QR code yields nothing")
    func blankImage() async throws {
        let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let blank = try #require(context?.makeImage())

        let payloads = await QRImageDecoder.payloads(in: blank)
        #expect(payloads.isEmpty)
    }

    @Test("Import routes each URI flavour to the right parser")
    func importCoordinatorRouting() throws {
        let single = ImportCoordinator.accounts(
            fromPayload: "otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(single.accounts.count == 1)
        #expect(single.problems.isEmpty)

        let account = Account(issuer: "A", label: "b", secret: Data("secret!!".utf8))
        let (uris, _) = MigrationURI.uris(for: [account])
        let batch = ImportCoordinator.accounts(fromPayload: try #require(uris.first))
        #expect(batch.accounts.count == 1)

        let nonsense = ImportCoordinator.accounts(fromPayload: "https://example.com")
        #expect(nonsense.accounts.isEmpty)
        #expect(!nonsense.problems.isEmpty)
    }

    @Test("Duplicates within one import are collapsed, and known accounts are separated")
    func deduplication() {
        let uri = "otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP"
        let result = ImportCoordinator.accounts(fromPayloads: [uri, uri])
        #expect(result.accounts.count == 1)

        let existing = result.accounts
        let again = ImportCoordinator.accounts(fromPayloads: [uri])
        let (new, duplicates) = ImportCoordinator.partition(
            candidates: again.accounts,
            existing: existing
        )
        #expect(new.isEmpty)
        #expect(duplicates.count == 1)
    }
}
