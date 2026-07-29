import AppKit
import Foundation

/// Watches for user activity inside this app and for system events that should lock
/// the vault immediately.
///
/// Local event monitors only see events routed to this process, which is exactly the
/// question being asked ("has the user been idle *in Authenticator*") and needs no
/// Accessibility permission.
@MainActor
final class IdleMonitor {
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private(set) var lastActivity = Date()

    /// Called when the idle threshold is crossed or a system event demands a lock.
    var onLockRequested: (() -> Void)?
    /// Seconds of inactivity before locking. Zero or less disables the idle timer.
    var timeout: TimeInterval = 300

    func start() {
        stop()
        lastActivity = Date()

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
                .otherMouseDown, .scrollWheel,
            ]
        ) { [weak self] event in
            self?.lastActivity = Date()
            return event  // Pass through untouched; we are only observing.
        }

        // Checking every 5s is enough for a timeout measured in minutes.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observeImmediateLockTriggers()
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        timer?.invalidate()
        timer = nil

        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func noteActivity() {
        lastActivity = Date()
    }

    private func checkIdle() {
        guard timeout > 0 else { return }
        if Date().timeIntervalSince(lastActivity) >= timeout {
            onLockRequested?()
        }
    }

    private func observeImmediateLockTriggers() {
        let requestLock: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.onLockRequested?() }
        }

        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main,
                using: requestLock
            )
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            observers.append(
                workspaceCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main,
                    using: requestLock
                )
            )
        }
    }

    deinit {
        // Monitors and observers are cleaned up by `stop()`; if the owner forgot,
        // ARC releasing them here is still safe because they hold weak references.
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
