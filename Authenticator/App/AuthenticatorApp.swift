import SwiftUI

@main
struct AuthenticatorApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Authenticator", id: "main") {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    handleOpen(url)
                }
        }
        .defaultSize(width: 460, height: 620)
        .windowResizability(.contentSize)
        .commands {
            AuthenticatorCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    /// Handles `otpauth://` and `otpauth-migration://` links opened from elsewhere.
    private func handleOpen(_ url: URL) {
        guard !model.lock.isLocked else {
            model.errorMessage = "Unlock Authenticator before adding an account."
            return
        }
        let result = ImportCoordinator.accounts(fromPayload: url.absoluteString)
        if result.accounts.isEmpty {
            model.errorMessage = result.problems.first ?? "That link could not be read."
        } else {
            model.commitImport(result.accounts)
        }
    }
}
