import Foundation
import os

/// The widget's share of the vault link: before a timeline is built, fetch tasks.json and
/// reconcile it, so new Now.md tasks reach the widget without opening the app.
/// - Only when the token was saved to the shared keychain group; otherwise (or with no token) the
///   widget shows what the app last imported, and leaves the status line alone.
/// - At most once every 15 minutes (the app reloads the widget on every tick), and time-boxed:
///   each request gives up after 5 seconds.
enum WidgetVaultRefresh {
    static let lastAttemptKey = "vault_widget_last_fetch"
    static let minimumInterval: TimeInterval = 15 * 60
    static let requestTimeout: TimeInterval = 5

    @MainActor
    static func runIfPossible(now: Date = Date()) async {
        let defaults = SharedPersistence.sharedDefaults
        guard VaultTokenLocation.load(from: defaults) == .sharedWithWidget else { return }
        if let last = defaults.object(forKey: lastAttemptKey) as? Date, now.timeIntervalSince(last) < minimumInterval {
            return
        }
        let vault = VaultSync(
            tokenStore: KeychainVaultTokenStore(),
            http: URLSessionVaultHTTPClient(timeout: requestTimeout),
            defaults: defaults,
            timeout: requestTimeout
        )
        guard vault.hasToken else { return }
        defaults.set(now, forKey: lastAttemptKey)
        do {
            let context = try WidgetTaskStore.makeContext()
            await vault.refreshTasks(context: context, quietWithoutToken: true)
        } catch {
            AppLogger.widget.error("Widget vault refresh skipped: \(error.localizedDescription, privacy: .public)")
        }
    }
}
