import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds the QR codes an export produces, and writes them out.
enum ExportService {
    /// One renderable code, whether it came from a single account or a transfer batch.
    struct ExportItem: Identifiable {
        let id = UUID()
        let title: String
        let uri: String

        var image: CGImage? { QRCodeRenderer.image(for: uri) }
    }

    struct Plan {
        var items: [ExportItem] = []
        /// Accounts the chosen format cannot represent, with the reason why.
        var rejected: [MigrationPayload.ExportRejection] = []
    }

    enum Format: String, CaseIterable, Identifiable {
        case individual
        case transfer

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .individual: "One QR code per account"
            case .transfer: "Google Authenticator transfer"
            }
        }

        var explanation: String {
            switch self {
            case .individual:
                "Standard otpauth:// codes. Any authenticator app can scan them, one at a time."
            case .transfer:
                "Google Authenticator's batch format. Scan with “Transfer accounts → Import” to move everything at once."
            }
        }
    }

    static func plan(for accounts: [Account], format: Format) -> Plan {
        switch format {
        case .individual:
            Plan(
                items: accounts.map { account in
                    ExportItem(
                        title: account.displayTitle,
                        uri: OTPAuthURI.string(for: account)
                    )
                }
            )
        case .transfer:
            transferPlan(for: accounts)
        }
    }

    private static func transferPlan(for accounts: [Account]) -> Plan {
        let (uris, rejected) = MigrationURI.uris(for: accounts)
        let items = uris.enumerated().map { index, uri in
            ExportItem(
                title: uris.count == 1
                    ? "Transfer code" : "Transfer code \(index + 1) of \(uris.count)",
                uri: uri
            )
        }
        return Plan(items: items, rejected: rejected)
    }

    // MARK: - Writing

    /// Saves one code as a PNG, asking the user where it should go.
    @MainActor
    static func savePNG(for item: ExportItem) throws {
        guard let cgImage = item.image,
              let data = QRCodeRenderer.pngData(for: cgImage)
        else {
            throw ExportError.renderFailed
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = sanitisedFilename(item.title) + ".png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: [.atomic])
    }

    /// Saves every code in a plan into a directory the user chooses.
    @MainActor
    static func savePNGs(for items: [ExportItem]) throws {
        guard !items.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        for (index, item) in items.enumerated() {
            guard let cgImage = item.image,
                  let data = QRCodeRenderer.pngData(for: cgImage)
            else {
                throw ExportError.renderFailed
            }
            // Prefix with the position so a multi-code transfer stays in scanning order.
            let name = String(format: "%02d-%@.png", index + 1, sanitisedFilename(item.title))
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
        }
    }

    private static func sanitisedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "authenticator" : trimmed
    }

    enum ExportError: LocalizedError {
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed: "The QR code could not be rendered."
            }
        }
    }
}
