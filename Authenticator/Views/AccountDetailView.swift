import SwiftUI

/// Presented as a sheet from the account list. The main window stays a single screen.
struct AccountDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var showsQRCode = false
    @State private var confirmDelete = false

    /// Re-read from the model so an advancing HOTP counter stays current while open.
    private var current: Account {
        model.accounts.first { $0.id == account.id } ?? account
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider()
                    details
                    Divider()
                    qrSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Delete Account…", role: .destructive) { confirmDelete = true }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420, height: showsQRCode ? 640 : 420)
        .confirmationDialog(
            "Delete “\(current.displayTitle)”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.delete(ids: [account.id])
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access unless you have another copy of this account's setup code.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.displayTitle).font(.title.bold())
            if let subtitle = current.displaySubtitle {
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        Formatting.groupedCode(
                            OTPGenerator.code(for: current, at: context.date)
                        )
                    )
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                }
                if current.kind == .totp {
                    CountdownRing(period: current.period, lineWidth: 4, size: 28)
                }
            }

            HStack {
                Button("Copy Code") { model.copyCode(for: current) }
                if current.kind == .hotp {
                    Button("Next Code") { model.incrementCounter(for: current) }
                }
            }
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            row("Type", current.kind.displayName)
            row("Algorithm", current.algorithm.uriValue)
            row("Digits", "\(current.digits)")
            switch current.kind {
            case .totp: row("Period", "\(current.period) seconds")
            case .hotp: row("Counter", "\(current.counter)")
            }
            row("Added", current.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }

    @ViewBuilder
    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show setup QR code", isOn: $showsQRCode)
                .toggleStyle(.switch)

            if showsQRCode {
                Text("Anyone who scans this gains full access to this account.")
                    .font(.callout)
                    .foregroundStyle(.orange)

                if let image = QRCodeRenderer.image(
                    for: OTPAuthURI.string(for: current),
                    size: 220
                ) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .background(.white)
                        .padding(6)
                }
            }
        }
    }
}
