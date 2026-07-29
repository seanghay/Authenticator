import Combine
import SwiftUI

/// Menu bar commands.
///
/// Menu items live outside the window's view hierarchy, so they publish intents on a
/// shared subject that `RootView` subscribes to rather than mutating view state directly.
enum AppCommands {
    enum Command {
        case addAccount
        case scanCamera
        case importImage
        case export
        case copySelectedCode
        case focusSearch
    }

    static let subject = PassthroughSubject<Command, Never>()
    static var publisher: AnyPublisher<Command, Never> { subject.eraseToAnyPublisher() }

    static func send(_ command: Command) {
        subject.send(command)
    }
}

struct AuthenticatorCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // The app has no documents, so "New" belongs to adding an account.
        CommandGroup(replacing: .newItem) {
            Button("Add Account…") { AppCommands.send(.addAccount) }
                .keyboardShortcut("n")
            Button("Scan with Camera…") { AppCommands.send(.scanCamera) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Import from Image…") { AppCommands.send(.importImage) }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .saveItem) {
            Button("Export Accounts…") { AppCommands.send(.export) }
                .keyboardShortcut("e")
                .disabled(model.accounts.isEmpty)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find") { AppCommands.send(.focusSearch) }
                .keyboardShortcut("f")
                .disabled(model.accounts.isEmpty)
        }

        CommandMenu("Account") {
            // Not plain ⌘C: a menu key equivalent wins over the focused control, so
            // binding it here would hijack Copy inside the search and secret fields.
            Button("Copy Code") { AppCommands.send(.copySelectedCode) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.selection == nil)
            Divider()
            Button("Lock Now") { model.lock.lock() }
                .keyboardShortcut("l")
                .disabled(model.lock.isLocked)
        }
    }
}
