import SwiftUI

/// Manual entry plus a paste field that accepts either URI flavour.
struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case paste
        case manual

        var id: String { rawValue }
        var title: String {
            switch self {
            case .paste: "Paste Link"
            case .manual: "Enter Manually"
            }
        }
    }

    @State private var mode: Mode = .paste
    @State private var pastedText = ""
    @State private var issuer = ""
    @State private var label = ""
    @State private var secret = ""
    @State private var kind: OTPKind = .totp
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var counter: UInt64 = 0
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account")
                .font(.title2.bold())

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .paste: pasteForm
            case .manual: manualForm
            }

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Forms

    private var pasteForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste an otpauth:// setup link, or a Google Authenticator otpauth-migration:// transfer link.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $pastedText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )

            Button("Paste from Clipboard") {
                pastedText = Clipboard.string() ?? ""
            }
            .buttonStyle(.link)
        }
    }

    private var manualForm: some View {
        Form {
            TextField("Issuer", text: $issuer, prompt: Text("GitHub"))
            TextField("Account", text: $label, prompt: Text("you@example.com"))
            TextField("Secret key", text: $secret, prompt: Text("Base32, e.g. JBSWY3DPEHPK3PXP"))
                .font(.system(.body, design: .monospaced))

            Picker("Type", selection: $kind) {
                ForEach(OTPKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Algorithm", selection: $algorithm) {
                ForEach(OTPAlgorithm.allCases, id: \.self) { Text($0.uriValue).tag($0) }
            }
            Picker("Digits", selection: $digits) {
                ForEach(Array(Account.allowedDigits), id: \.self) { Text("\($0)").tag($0) }
            }
            switch kind {
            case .totp:
                Stepper("Period: \(period)s", value: $period, in: 10...120, step: 5)
            case .hotp:
                // Bounded well below UInt64.max: SwiftUI's Stepper measures the range
                // with `distance(to:)`, which traps when the span overflows Int.
                Stepper("Counter: \(counter)", value: $counter, in: 0...999_999_999)
            }
        }
        .formStyle(.grouped)
    }

    private var canSubmit: Bool {
        switch mode {
        case .paste:
            !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .manual:
            !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (!issuer.isEmpty || !label.isEmpty)
        }
    }

    // MARK: - Submit

    private func submit() {
        problem = nil
        switch mode {
        case .paste:
            let result = ImportCoordinator.accounts(fromPayload: pastedText)
            guard result.accounts.isEmpty == false else {
                problem = result.problems.first ?? "Nothing could be read from that link."
                return
            }
            model.commitImport(result.accounts)
            dismiss()

        case .manual:
            guard let decoded = Base32.decode(secret) else {
                problem = "The secret key is not valid base32."
                return
            }
            let account = Account(
                issuer: issuer.trimmingCharacters(in: .whitespaces),
                label: label.trimmingCharacters(in: .whitespaces),
                secret: decoded,
                algorithm: algorithm,
                digits: digits,
                period: period,
                kind: kind,
                counter: counter
            )
            model.commitImport([account])
            dismiss()
        }
    }
}
