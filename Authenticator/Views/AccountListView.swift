import SwiftUI

struct AccountListView: View {
    @Environment(AppModel.self) private var model

    /// Opens the detail sheet. The list itself stays a single flat screen.
    let onShowDetail: (Account) -> Void

    var body: some View {
        @Bindable var model = model

        Group {
            if model.accounts.isEmpty {
                emptyVault
            } else if model.filteredAccounts.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                list(selection: $model.selection)
            }
        }
        // Always claim the full remaining height. Without this the placeholder views
        // size to their content, the enclosing VStack centres everything, and the
        // search field slides down the window whenever a search comes up empty.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(selection: Binding<Account.ID?>) -> some View {
        List(selection: selection) {
            ForEach(model.filteredAccounts) { account in
                AccountRowView(
                    account: account,
                    isHidden: model.settings.hideCodesUntilHover,
                    onCopy: { model.copyCode(for: account) },
                    onAdvance: { model.incrementCounter(for: account) }
                )
                .tag(account.id)
                // Copying is the whole point of the app, so a plain click does it.
                // Selection is set by hand because the gesture consumes the click the
                // List would otherwise have used to select the row.
                .onTapGesture {
                    model.selection = account.id
                    model.copyCode(for: account)
                }
                .contextMenu {
                    Button("Copy Code") { model.copyCode(for: account) }
                    Button("Account Info…") { onShowDetail(account) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        model.delete(ids: [account.id])
                    }
                }
            }
            .onMove { source, destination in
                model.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.inset)
    }

    private var emptyVault: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "lock.shield")
        } description: {
            Text("Add an account by scanning a QR code, opening a screenshot, or pasting a setup link.")
        }
    }
}
