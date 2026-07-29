import SwiftUI

struct AccountRowView: View {
    let account: Account
    let isHidden: Bool
    let onCopy: () -> Void
    let onAdvance: () -> Void

    @State private var isHovering = false

    private var shouldMask: Bool { isHidden && !isHovering }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayTitle)
                    .font(.headline)
                if let subtitle = account.displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                codeText
            }

            Spacer(minLength: 8)

            switch account.kind {
            case .totp:
                CountdownRing(period: account.period)
            case .hotp:
                Button(action: onAdvance) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Generate the next code")
            }

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy code")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var codeText: some View {
        if shouldMask {
            Text(String(repeating: "•", count: account.digits))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            // Re-rendered every second so a TOTP code never goes stale on screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Formatting.groupedCode(OTPGenerator.code(for: account, at: context.date)))
                    .font(.system(.title2, design: .monospaced))
                    .textSelection(.enabled)
                    .contentTransition(.numericText())
            }
        }
    }
}
