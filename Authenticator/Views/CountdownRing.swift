import SwiftUI

/// A ring that drains over one TOTP period and turns amber just before rollover.
struct CountdownRing: View {
    let period: Int
    var lineWidth: CGFloat = 3
    var size: CGFloat = 22

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = OTPCountdown.secondsRemaining(period: period, at: context.date)
            let progress = OTPCountdown.progress(period: period, at: context.date)
            let expiring = OTPCountdown.isExpiringSoon(period: period, at: context.date)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        expiring ? Color.orange : Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: progress)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("\(remaining) seconds remaining")
        }
    }
}
