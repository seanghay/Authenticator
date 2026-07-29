import Foundation

/// A reference-typed box for key material that zeroes its buffer when released.
///
/// This is best-effort, not a guarantee: Swift's `Data` is copy-on-write and the
/// runtime may have made copies we cannot reach. It closes the obvious window —
/// a long-lived key sitting in a heap buffer after the app locks — and nothing more.
final class SecureBytes {
    private var storage: Data

    init(_ data: Data) {
        self.storage = data
    }

    /// Read the bytes for the duration of the closure.
    func withBytes<T>(_ body: (Data) throws -> T) rethrows -> T {
        try body(storage)
    }

    var count: Int { storage.count }

    /// Overwrite the buffer now, rather than waiting for deallocation.
    func wipe() {
        storage.resetBytes(in: 0..<storage.count)
        storage.removeAll(keepingCapacity: false)
    }

    deinit {
        wipe()
    }
}
