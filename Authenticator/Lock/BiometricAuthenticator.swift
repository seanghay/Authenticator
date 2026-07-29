import Foundation
import LocalAuthentication

/// Thin wrapper over LocalAuthentication.
///
/// Uses `.deviceOwnerAuthentication` rather than the biometrics-only policy, so the
/// system sheet supplies Apple Watch and login-password fallbacks by itself. That
/// matters because plenty of Macs have no Touch ID at all.
enum BiometricAuthenticator {
    enum Availability: Equatable {
        case touchID
        case passwordOnly
        case unavailable(String)

        var canAuthenticate: Bool {
            switch self {
            case .touchID, .passwordOnly: true
            case .unavailable: false
            }
        }

        var displayName: String {
            switch self {
            case .touchID: "Touch ID"
            case .passwordOnly: "your password"
            case .unavailable: "unavailable"
            }
        }
    }

    static func availability() -> Availability {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
           context.biometryType == .touchID {
            return .touchID
        }

        error = nil
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .passwordOnly
        }
        return .unavailable(
            error?.localizedDescription ?? "This Mac cannot verify your identity."
        )
    }

    /// Returns true on success, false if the user cancelled. Throws on real failures.
    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? AuthenticationError.unavailable
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return false
            default:
                throw laError
            }
        }
    }

    enum AuthenticationError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable: "This Mac cannot verify your identity."
            }
        }
    }
}
