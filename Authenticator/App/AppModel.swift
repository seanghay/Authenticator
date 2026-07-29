import CryptoKit
import Foundation
import Observation
import SwiftUI

/// Root application state: the account list, the vault behind it, and the lock.
@Observable
@MainActor
final class AppModel {
    private(set) var accounts: [Account] = []
    var searchText: String = ""
    var selection: Account.ID?

    /// A message worth surfacing in a banner or alert.
    var errorMessage: String?
    /// Transient confirmation, e.g. "Code copied".
    var statusMessage: String?

    let settings: AppSettings
    let lock: LockController

    @ObservationIgnored private var vault: Vault?
    @ObservationIgnored private var key: SymmetricKey?

    var filteredAccounts: [Account] {
        accounts
            .filter { $0.matches(searchText: searchText) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Dependencies are optional rather than defaulted, because a default argument is
    /// evaluated outside the main actor and both of these are main-actor isolated.
    init(settings: AppSettings? = nil, lock: LockController? = nil) {
        let settings = settings ?? AppSettings()
        let lock = lock ?? LockController()
        self.settings = settings
        self.lock = lock

        lock.configureIdleTimeout(settings.idleTimeout)
        lock.onUnlock = { [weak self] in
            await self?.loadVault()
        }
        lock.onLock = { [weak self] in
            self?.purgeSecrets()
        }

        // Tests start unlocked, so the vault must be opened without a Touch ID round-trip.
        if lock.state == .unlocked {
            Task { await loadVault() }
        }
    }

    // MARK: - Vault lifecycle

    private func loadVault() async {
        do {
            let key = try VaultKeyStore.shared.loadOrCreateKey()
            let vault = try Vault(key: key)
            let document = try vault.load()

            self.key = key
            self.vault = vault
            self.accounts = document.accounts.sorted { $0.sortIndex < $1.sortIndex }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drops everything sensitive from memory. Best-effort: Swift may have copied
    /// buffers we cannot reach, but this closes the obvious window.
    private func purgeSecrets() {
        accounts.removeAll()
        selection = nil
        searchText = ""
        vault = nil
        key = nil
        Clipboard.clearIfOwned()
    }

    private func persist() {
        guard let vault else { return }
        do {
            try vault.save(VaultDocument(accounts: accounts))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Mutations

    func add(_ newAccounts: [Account]) {
        guard !newAccounts.isEmpty else { return }
        var nextIndex = (accounts.map(\.sortIndex).max() ?? -1) + 1
        for var account in newAccounts {
            account.sortIndex = nextIndex
            nextIndex += 1
            accounts.append(account)
        }
        persist()
    }

    func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        persist()
    }

    func delete(ids: Set<Account.ID>) {
        guard !ids.isEmpty else { return }
        accounts.removeAll { ids.contains($0.id) }
        if let selection, ids.contains(selection) { self.selection = nil }
        renumber()
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Reordering only makes sense over the unfiltered list.
        guard searchText.isEmpty else { return }
        var ordered = accounts.sorted { $0.sortIndex < $1.sortIndex }
        ordered.move(fromOffsets: source, toOffset: destination)
        accounts = ordered
        renumber()
        persist()
    }

    /// HOTP codes only advance when asked.
    func incrementCounter(for account: Account) {
        guard account.kind == .hotp,
              let index = accounts.firstIndex(where: { $0.id == account.id })
        else { return }
        accounts[index].counter &+= 1
        persist()
    }

    private func renumber() {
        for index in accounts.indices {
            accounts[index].sortIndex = index
        }
    }

    // MARK: - Actions

    func code(for account: Account, at date: Date = Date()) -> String {
        OTPGenerator.code(for: account, at: date)
    }

    func copyCode(for account: Account) {
        let code = OTPGenerator.code(for: account)
        Clipboard.copy(code, clearAfter: settings.clipboardClearDelay)
        statusMessage = "Copied code for \(account.displayTitle)"
        lock.noteActivity()

        if account.kind == .hotp {
            incrementCounter(for: account)
        }
    }

    func applyIdleTimeout() {
        lock.configureIdleTimeout(settings.idleTimeout)
    }

    /// Deletes the vault file and its key. Irreversible.
    func eraseAllData() {
        do {
            try vault?.destroy()
            try VaultKeyStore.shared.deleteKey()
            accounts.removeAll()
            selection = nil
            vault = nil
            key = nil
            statusMessage = "All accounts erased"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import

    /// Commits a reviewed import, skipping anything already stored.
    func commitImport(_ candidates: [Account]) {
        let (new, duplicates) = ImportCoordinator.partition(
            candidates: candidates,
            existing: accounts
        )
        add(new)

        switch (new.count, duplicates.count) {
        case (0, 0):
            break
        case (0, _):
            statusMessage = "Already added — nothing new to import"
        case (let added, 0):
            statusMessage = "Imported \(added) account\(added == 1 ? "" : "s")"
        case (let added, let skipped):
            statusMessage =
                "Imported \(added), skipped \(skipped) already added"
        }
    }
}
