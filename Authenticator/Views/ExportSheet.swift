import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportService.Format = .individual
    @State private var selected: Set<Account.ID> = []
    @State private var previewIndex = 0
    @State private var problem: String?

    private var chosenAccounts: [Account] {
        model.accounts
            .filter { selected.contains($0.id) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    private var plan: ExportService.Plan {
        ExportService.plan(for: chosenAccounts, format: format)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Accounts")
                .font(.title2.bold())

            Picker("Format", selection: $format) {
                ForEach(ExportService.Format.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Text(format.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                accountPicker
                previewPane
            }

            warnings

            HStack {
                Button("Select All") { selected = Set(model.accounts.map(\.id)) }
                Button("Select None") { selected.removeAll() }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save PNG…", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
        .onAppear {
            if let selection = model.selection {
                selected = [selection]
            } else {
                selected = Set(model.accounts.map(\.id))
            }
        }
        .onChange(of: plan.items.count) { _, count in
            if previewIndex >= count { previewIndex = max(0, count - 1) }
        }
    }

    private var accountPicker: some View {
        List {
            ForEach(model.accounts.sorted { $0.sortIndex < $1.sortIndex }) { account in
                Toggle(isOn: binding(for: account.id)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.displayTitle)
                        if let subtitle = account.displaySubtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(width: 260, height: 260)
    }

    @ViewBuilder
    private var previewPane: some View {
        let items = plan.items
        VStack(spacing: 8) {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Export", systemImage: "qrcode")
                } description: {
                    Text("Select at least one account.")
                }
                .frame(width: 300, height: 260)
            } else {
                let item = items[min(previewIndex, items.count - 1)]
                if let image = item.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .background(.white)
                        .padding(6)
                }
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if items.count > 1 {
                    Stepper(
                        "Code \(previewIndex + 1) of \(items.count)",
                        value: $previewIndex,
                        in: 0...(items.count - 1)
                    )
                    .font(.caption)
                }
            }
        }
        .frame(width: 300)
    }

    @ViewBuilder
    private var warnings: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(plan.rejected) { rejection in
                Label(
                    "\(rejection.account.displayTitle): \(rejection.reason)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Label(problem, systemImage: "xmark.octagon")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if format == .transfer && !plan.items.isEmpty {
                Label(
                    "Anyone who scans these codes gains full access to the accounts. Delete the files once you have transferred them.",
                    systemImage: "exclamationmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() {
        problem = nil
        do {
            if plan.items.count == 1 {
                try ExportService.savePNG(for: plan.items[0])
            } else {
                try ExportService.savePNGs(for: plan.items)
            }
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
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
