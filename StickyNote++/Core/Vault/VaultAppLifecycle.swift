import BackgroundTasks
import SwiftData
import SwiftUI
import UIKit
import os

/// When the app runs the vault link (`docs/VAULT-API.md`):
/// - becoming active (launch, or back from the background): send the habits if yesterday went
///   unsent, then fetch tasks.json;
/// - going to the background: schedule the next background refresh, and send the habits if due,
///   inside a `beginBackgroundTask` window;
/// - background refresh (`BGAppRefreshTask`): fetch tasks.json, reschedule.
/// Nothing here blocks the UI: the work is async and every failure ends as a status line.
enum VaultBackground {
    /// Listed in Info.plist under `BGTaskSchedulerPermittedIdentifiers`.
    static let refreshTaskID = "com.liamratcliffe.Sticky-Notes-Sticky-Life.vault-refresh"

    /// Asks for the next background refresh (iOS decides when; at most every couple of hours).
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.vault.info("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The background refresh itself: reschedule first, then fetch.
    @MainActor
    static func runRefresh(vault: VaultSync, container: ModelContainer) async {
        scheduleRefresh()
        await vault.refreshTasks(context: container.mainContext, quietWithoutToken: true)
        TaskWidgetReloader.reloadTopTasksWidget()
    }

    /// Going to the background: the habits write gets a background-task window.
    @MainActor
    static func didEnterBackground(vault: VaultSync, container: ModelContainer) {
        scheduleRefresh()
        guard vault.hasToken else { return }
        let application = UIApplication.shared
        let token = BackgroundTaskToken()
        token.id = application.beginBackgroundTask(withName: "Vault habits") {
            token.end(in: application)
        }
        Task { @MainActor in
            await vault.writeHabitsIfDue(reason: .background, context: container.mainContext)
            token.end(in: application)
        }
    }
}

/// One `beginBackgroundTask` window, ended exactly once.
private final class BackgroundTaskToken {
    var id: UIBackgroundTaskIdentifier = .invalid

    @MainActor
    func end(in application: UIApplication) {
        guard id != .invalid else { return }
        application.endBackgroundTask(id)
        id = .invalid
    }
}

/// Runs the vault link from the app root as the scene phase changes, and reloads the widget when
/// an import changed the lists.
struct VaultLifecycle: ViewModifier {
    let vault: VaultSync
    let container: ModelContainer
    /// False in the screenshot harness: no background work is scheduled there.
    var schedulesBackgroundWork = true

    @Environment(\.scenePhase) private var scenePhase

    init(vault: VaultSync, container: ModelContainer, schedulesBackgroundWork: Bool = true) {
        self.vault = vault
        self.container = container
        self.schedulesBackgroundWork = schedulesBackgroundWork
    }

    func body(content: Content) -> some View {
        content
            .environment(\.vaultSync, vault)
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    Task { @MainActor in
                        vault.reloadFromDefaults()
                        // Yesterday's results go out before the import can add today's rows.
                        await vault.writeHabitsIfDue(reason: .launch, context: container.mainContext)
                        await vault.refreshTasks(context: container.mainContext)
                    }
                case .background:
                    if schedulesBackgroundWork {
                        VaultBackground.didEnterBackground(vault: vault, container: container)
                    }
                default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: VaultSync.tasksDidChange)) { _ in
                TaskWidgetReloader.reloadTopTasksWidget()
            }
    }
}
