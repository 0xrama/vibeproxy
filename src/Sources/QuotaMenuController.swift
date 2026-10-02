import Cocoa

/// Refreshes only when the menu is opened or the user asks. No background polling.
@MainActor
final class QuotaMenuController: NSObject, NSMenuDelegate {
    private let client = CodexQuotaClient()
    private let authManager = AuthManager()
    private let quotaMenu = NSMenu(title: "Codex quota")
    private var accounts: [AuthAccount] = []
    private var snapshots: [String: CodexQuotaSnapshot] = [:]
    private var errors: [String: String] = [:]
    private var refreshedAt: Date?
    private var busy = false

    func install(in menu: NSMenu) {
        quotaMenu.delegate = self
        let item = NSMenuItem(title: "Codex quota", action: nil, keyEquivalent: "")
        item.submenu = quotaMenu
        menu.insertItem(item, at: 2)
        render()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 60 { return }
        refresh()
    }

    @objc private func refresh() {
        guard !busy else { return }
        busy = true
        render()
        authManager.checkAuthStatus { [weak self] in
            guard let self else { return }
            self.accounts = self.authManager.accounts(for: .codex).filter { !$0.isDisabled }
                .sorted { $0.displayName < $1.displayName }
            let accounts = self.accounts
            Task { @MainActor in
                self.snapshots = [:]
                self.errors = [:]
                for account in accounts {
                    await self.fetch(account)
                }
                self.refreshedAt = Date()
                self.busy = false
                self.render()
            }
        }
    }

    private func fetch(_ account: AuthAccount) async {
        snapshots[account.id] = nil
        errors[account.id] = nil
        do { snapshots[account.id] = try await client.fetch(account: account) }
        catch { errors[account.id] = error.localizedDescription }
    }

    private func render() {
        quotaMenu.removeAllItems()
        quotaMenu.autoenablesItems = false
        let refreshItem = NSMenuItem(title: busy ? "Refreshing…" : "Refresh quota", action: #selector(refresh), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = !busy
        quotaMenu.addItem(refreshItem)
        if let refreshedAt {
            label("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))", in: quotaMenu)
        }
        quotaMenu.addItem(.separator())
        if accounts.isEmpty { label(busy ? "Loading accounts…" : "Connect Codex in Settings to see quota", in: quotaMenu) }
        for account in accounts {
            let summary = snapshots[account.id]?.windows.map { window in
                let remaining = window.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "?"
                return "\(window.name) \(remaining)"
            }.joined(separator: ", ")
            let title = summary.map { "\(account.displayName): \($0)" } ?? account.displayName
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let detail = NSMenu()
            detail.autoenablesItems = false
            item.submenu = detail
            quotaMenu.addItem(item)
            guard let snapshot = snapshots[account.id] else {
                label(errors[account.id] ?? "Loading…", in: detail)
                continue
            }
            for window in snapshot.windows {
                let remaining = window.remainingPercent.map { String(format: "%.0f%% remaining", $0) } ?? "Unavailable"
                label("\(window.name): \(remaining)", in: detail)
                if let date = window.resetsAt {
                    label("Resets \(date.formatted(date: .abbreviated, time: .shortened))", in: detail)
                }
            }
            detail.addItem(.separator())
            label(snapshot.availableCount.map { "\($0) manual resets available" } ?? "Reset count unavailable", in: detail)
            if let error = snapshot.creditsError { label("Reset credits: \(error)", in: detail) }
            for (index, credit) in snapshot.credits.filter({ $0.expiresAt > Date() }).enumerated() {
                let days = max(1, Int(ceil(credit.expiresAt.timeIntervalSinceNow / 86400)))
                label("Reset \(index + 1): expires in \(days) days", in: detail)
                label(credit.expiresAt.formatted(date: .abbreviated, time: .shortened), in: detail)
            }
            label("Listed earliest expiry first. Codex chooses the credit.", in: detail)
            let reset = NSMenuItem(title: "Use a manual reset…", action: #selector(useReset(_:)), keyEquivalent: "")
            reset.target = self
            reset.representedObject = account.id
            reset.isEnabled = !busy && snapshot.creditsError == nil && (snapshot.availableCount ?? 0) > 0
            detail.addItem(reset)
        }
    }

    private func label(_ title: String, in menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func useReset(_ sender: NSMenuItem) {
        guard !busy, let id = sender.representedObject as? String,
              let account = accounts.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Spend one Codex reset for \(account.displayName)?"
        alert.informativeText = "This spends one manual reset credit, using the same reset action as CLIProxyAPI."
        alert.addButton(withTitle: "Use reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        render()
        Task { @MainActor in
            do { try await client.reset(account: account) }
            catch {
                // A timeout may have happened after consumption. Do not retry the write.
                let failure = NSAlert()
                failure.messageText = "Reset not confirmed"
                failure.informativeText = "\(error.localizedDescription) Quota will be refreshed. Check the credit count before trying another reset."
                failure.runModal()
            }
            await fetch(account)
            busy = false
            render()
        }
    }
}
