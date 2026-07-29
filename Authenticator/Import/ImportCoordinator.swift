import CoreGraphics
import Foundation

/// Normalises every import source down to a list of accounts plus a report of what
/// could not be read, so the UI can show one consistent review sheet.
enum ImportCoordinator {
    struct Result {
        var accounts: [Account] = []
        /// Human-readable reasons for payloads that were understood but unusable.
        var problems: [String] = []

        var isEmpty: Bool { accounts.isEmpty && problems.isEmpty }

        mutating func merge(_ other: Result) {
            accounts.append(contentsOf: other.accounts)
            problems.append(contentsOf: other.problems)
        }
    }

    /// Interprets a single decoded string, which may be either URI flavour.
    static func accounts(fromPayload payload: String) -> Result {
        var result = Result()
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }

        if MigrationURI.isMigrationURI(trimmed) {
            do {
                result.accounts = try MigrationURI.accounts(from: trimmed)
                if result.accounts.isEmpty {
                    result.problems.append("The transfer code contained no usable accounts.")
                }
            } catch {
                result.problems.append(error.localizedDescription)
            }
            return result
        }

        do {
            result.accounts = [try OTPAuthURI.parse(trimmed)]
        } catch {
            result.problems.append(error.localizedDescription)
        }
        return result
    }

    /// Interprets several payloads, e.g. every QR code found in one screenshot.
    static func accounts(fromPayloads payloads: [String]) -> Result {
        var result = Result()
        for payload in payloads {
            result.merge(accounts(fromPayload: payload))
        }
        return deduplicated(result)
    }

    /// Reads every QR code out of the given images and interprets them.
    static func accounts(fromImages images: [CGImage]) async -> Result {
        var payloads: [String] = []
        for image in images {
            payloads.append(contentsOf: await QRImageDecoder.payloads(in: image))
        }
        guard !payloads.isEmpty else {
            return Result(problems: ["No QR code was found in the image."])
        }
        return accounts(fromPayloads: payloads)
    }

    /// Drops entries that duplicate one another within a single import.
    private static func deduplicated(_ result: Result) -> Result {
        var seen = Set<String>()
        var output = result
        output.accounts = result.accounts.filter { seen.insert($0.identityKey).inserted }
        return output
    }

    /// Splits candidates against what is already stored, so the review sheet can say
    /// which ones are new.
    static func partition(
        candidates: [Account],
        existing: [Account]
    ) -> (new: [Account], duplicates: [Account]) {
        let existingKeys = Set(existing.map(\.identityKey))
        var new: [Account] = []
        var duplicates: [Account] = []
        for candidate in candidates {
            if existingKeys.contains(candidate.identityKey) {
                duplicates.append(candidate)
            } else {
                new.append(candidate)
            }
        }
        return (new, duplicates)
    }
}
