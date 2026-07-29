import Foundation
import Security

/// A Keychain call that failed, with a message worth showing a human.
struct KeychainError: LocalizedError {
    let status: OSStatus
    let operation: String

    var errorDescription: String? {
        "Keychain \(operation) failed: \(detail)"
    }

    private var detail: String {
        switch status {
        case errSecMissingEntitlement:
            // Reachable if the app is ever built with data-protection keychain
            // options, which need an application-identifier entitlement we do not have.
            "the app is missing a required entitlement (-34018). It may not be signed correctly."
        case errSecAuthFailed:
            "authentication was refused (-25293)."
        case errSecUserCanceled:
            "you cancelled the request."
        case errSecInteractionNotAllowed:
            "the keychain is locked and cannot prompt right now."
        case errSecDuplicateItem:
            "the item already exists."
        case errSecItemNotFound:
            "the item was not found."
        default:
            (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)."
        }
    }
}
