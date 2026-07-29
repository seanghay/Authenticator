import Foundation
import Observation

/// Owns whether the vault is readable, and drives the Touch ID prompt.
@Observable
@MainActor
final class LockController {
    enum State: Equatable {
        case locked
        case authenticating
        case unlocked
    }

    private(set) var state: State = .locked
    private(set) var lastError: String?

    var isLocked: Bool { state != .unlocked }

    /// Set by the owner; runs after a successful unlock and after a lock.
    var onUnlock: (() async -> Void)?
    var onLock: (() -> Void)?

    let availability = BiometricAuthenticator.availability()

    @ObservationIgnored private let idleMonitor = IdleMonitor()

    init() {
        // Under `xcodebuild test` there is no one to answer a Touch ID prompt, and the
        // sheet would block the test run forever.
        if Self.isRunningTests {
            state = .unlocked
            return
        }
        idleMonitor.onLockRequested = { [weak self] in
            self?.lock()
        }
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func configureIdleTimeout(_ seconds: TimeInterval) {
        idleMonitor.timeout = seconds
    }

    func unlock() async {
        guard state != .unlocked, state != .authenticating else { return }

        // A Mac that cannot authenticate at all would otherwise be locked out of its
        // own data; fall through to unlocked rather than bricking the app.
        guard availability.canAuthenticate else {
            await finishUnlock()
            return
        }

        state = .authenticating
        lastError = nil

        do {
            let success = try await BiometricAuthenticator.authenticate(
                reason: "unlock your authenticator codes"
            )
            if success {
                await finishUnlock()
            } else {
                state = .locked
            }
        } catch {
            lastError = error.localizedDescription
            state = .locked
        }
    }

    private func finishUnlock() async {
        await onUnlock?()
        state = .unlocked
        idleMonitor.start()
    }

    func lock() {
        guard state != .locked else { return }
        idleMonitor.stop()
        state = .locked
        lastError = nil
        onLock?()
    }

    func noteActivity() {
        idleMonitor.noteActivity()
    }
}
