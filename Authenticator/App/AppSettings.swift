import Foundation
import Observation

/// User preferences, backed by `UserDefaults`.
@Observable
@MainActor
final class AppSettings {
    private enum Key {
        static let idleTimeout = "idleTimeoutSeconds"
        static let clipboardClearDelay = "clipboardClearSeconds"
        static let hideCodesUntilHover = "hideCodesUntilHover"
    }

    /// Seconds of inactivity before re-locking. Zero means never.
    var idleTimeout: TimeInterval {
        didSet { defaults.set(idleTimeout, forKey: Key.idleTimeout) }
    }

    /// Seconds before a copied code is wiped from the clipboard. Zero means never.
    var clipboardClearDelay: TimeInterval {
        didSet { defaults.set(clipboardClearDelay, forKey: Key.clipboardClearDelay) }
    }

    /// When on, codes are dotted out until you point at the row.
    var hideCodesUntilHover: Bool {
        didSet { defaults.set(hideCodesUntilHover, forKey: Key.hideCodesUntilHover) }
    }

    static let idleTimeoutChoices: [TimeInterval] = [60, 300, 900, 1800, 0]
    static let clipboardClearChoices: [TimeInterval] = [15, 30, 60, 0]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.idleTimeout: 300.0,
            Key.clipboardClearDelay: 30.0,
            Key.hideCodesUntilHover: false,
        ])
        self.idleTimeout = defaults.double(forKey: Key.idleTimeout)
        self.clipboardClearDelay = defaults.double(forKey: Key.clipboardClearDelay)
        self.hideCodesUntilHover = defaults.bool(forKey: Key.hideCodesUntilHover)
    }
}
