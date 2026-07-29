import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmErase = false

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section("Security") {
                Picker("Lock after", selection: $settings.idleTimeout) {
                    ForEach(AppSettings.idleTimeoutChoices, id: \.self) { seconds in
                        Text(Formatting.idleTimeoutDescription(seconds)).tag(seconds)
                    }
                }
                .onChange(of: settings.idleTimeout) { _, _ in
                    model.applyIdleTimeout()
                }

                Picker("Clear copied codes after", selection: $settings.clipboardClearDelay) {
                    ForEach(AppSettings.clipboardClearChoices, id: \.self) { seconds in
                        Text(Formatting.idleTimeoutDescription(seconds)).tag(seconds)
                    }
                }

                Toggle("Hide codes until pointed at", isOn: $settings.hideCodesUntilHover)

                LabeledContent("Unlock method") {
                    Text(model.lock.availability.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                LabeledContent("Accounts stored") {
                    Text("\(model.accounts.count)")
                        .foregroundStyle(.secondary)
                }
                Button("Erase All Accounts…", role: .destructive) {
                    confirmErase = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .confirmationDialog(
            "Erase all accounts?",
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button("Erase Everything", role: .destructive) { model.eraseAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every stored account and its encryption key. It cannot be undone.")
        }
    }
}
