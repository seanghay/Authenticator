import Foundation

/// Timing helpers for the countdown ring and for knowing when a code rolls over.
enum OTPCountdown {
    static func secondsRemaining(period: Int, at date: Date = Date()) -> Int {
        let safePeriod = max(period, 1)
        let elapsed = Int(max(date.timeIntervalSince1970, 0)) % safePeriod
        return safePeriod - elapsed
    }

    /// 1.0 at the start of a step, falling to 0 as it expires.
    static func progress(period: Int, at date: Date = Date()) -> Double {
        let safePeriod = max(period, 1)
        return Double(secondsRemaining(period: safePeriod, at: date)) / Double(safePeriod)
    }

    /// True once a code is close enough to expiry that it is worth warning about.
    static func isExpiringSoon(period: Int, at date: Date = Date()) -> Bool {
        secondsRemaining(period: period, at: date) <= 5
    }
}
