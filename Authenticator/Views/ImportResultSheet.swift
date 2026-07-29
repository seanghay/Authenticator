import SwiftUI

/// Shown after reading QR codes from a file, drop or picker, so nothing lands in the
/// vault without the user seeing it first.
struct ImportResultSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let result: ImportCoordinator.Result

    @State private var selected: Set<Account.ID> = []

    private var partitioned: (new: [Account], duplicates: [Account]) {
        ImportCoordinator.partition(candidates: result.accounts, existing: model.accounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Import")
                .font(.title2.bold())

            if result.accounts.isEmpty {
                nothingFound
            } else {
                accountList
            }

            if !result.problems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(selected.count) Account\(selected.count == 1 ? "" : "s")") {
                    let chosen = result.accounts.filter { selected.contains($0.id) }
                    model.commitImport(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // Pre-select everything that is not already in the vault.
            selected = Set(partitioned.new.map(\.id))
        }
    }

    private var nothingFound: some View {
        ContentUnavailableView {
            Label("No Accounts Found", systemImage: "qrcode.viewfinder")
        } description: {
            Text("The image did not contain a readable setup code.")
        }
        .frame(height: 160)
    }

    private var accountList: some View {
        let duplicateIDs = Set(partitioned.duplicates.map(\.id))

        return List {
            ForEach(result.accounts) { account in
                Toggle(isOn: binding(for: account.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayTitle).font(.headline)
                        HStack(spacing: 6) {
                            if let subtitle = account.displaySubtitle {
                                Text(subtitle)
                            }
                            if duplicateIDs.contains(account.id) {
                                Text("Already added")
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(result.accounts.count) * 52 + 16, 300))
    }

    private func binding(for id: Account.ID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }
}
