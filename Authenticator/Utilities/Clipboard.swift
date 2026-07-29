import AppKit
import Foundation

/// Clipboard writes, with an optional timed wipe so codes do not linger.
enum Clipboard {
    /// Tracks what we last wrote, so auto-clear never erases something the user
    /// copied from another app in the meantime.
    private nonisolated(unsafe) static var lastWrittenChangeCount: Int?

    @MainActor
    static func copy(_ string: String, clearAfter seconds: TimeInterval? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        lastWrittenChangeCount = pasteboard.changeCount

        guard let seconds, seconds > 0 else { return }
        let expectedChangeCount = pasteboard.changeCount
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            clearIfUnchanged(since: expectedChangeCount)
        }
    }

    /// Wipes the pasteboard only if nothing else has written to it since.
    @MainActor
    static func clearIfUnchanged(since changeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        lastWrittenChangeCount = nil
    }

    /// Called when locking: drop a code we put there, but leave unrelated content alone.
    @MainActor
    static func clearIfOwned() {
        guard let lastWrittenChangeCount else { return }
        clearIfUnchanged(since: lastWrittenChangeCount)
    }

    @MainActor
    static func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
