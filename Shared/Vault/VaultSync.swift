import Combine
import Foundation
import SwiftData
import os

/// When the habits file may be written: at most one commit a day (`docs/VAULT-API.md`).
enum VaultHabitsGate {
    enum Reason: Equatable {
        /// The app went to the background.
        case background
        /// The app launched or came back to the foreground.
        case launch
    }

    /// The day of the last commit (or of giving up after two conflicts), in the App Group defaults.
    static let lastCommitKey = "vault_habits_last_commit_day"

    /// The days to write through, one per file (month), oldest first; empty if nothing is due.
    /// - One commit a day: nothing once today has had one.
    /// - Going to the background after the morning: this month through today (today still open).
    /// - Launching (or returning) when yesterday had no commit at all: through yesterday, so a day
    ///   is never left unsent. That uses today's commit; today goes with tomorrow's.
    /// - If the last commit was in an earlier month, that month is finished first (through its last
    ///   day), so a month's last day never stays `open`. Only then can one sync make two commits,
    ///   one per file (provisional exception, at most at a month end). Months in between, with no
    ///   commit at all, are not written.
    static func plan(
        reason: Reason,
        todayKey: String,
        lastCommitDayKey: String?,
        morningOver: Bool,
        calendar: Calendar
    ) -> [String] {
        if let last = lastCommitDayKey, last >= todayKey { return [] }
        let math = DayMath(calendar: calendar)
        let yesterday = math.adding(days: -1, to: todayKey)
        let target: String
        switch reason {
        case .background:
            guard morningOver else { return [] }
            target = todayKey
        case .launch:
            guard (lastCommitDayKey ?? "") < yesterday else { return [] }
            target = yesterday
        }
        var throughs = [target]
        if let last = lastCommitDayKey, last.prefix(7) < target.prefix(7), let ymd = DayMath.parse(last) {
            throughs.insert(math.lastDayOfMonth(year: ymd.year, month: ymd.month), at: 0)
        }
        return throughs
    }
}

/// The vault link: reads `tasks.json` into the app and writes the habits file back. Used by the
/// app (launch, foreground, background refresh, going to the background) and the widget (fetch
/// only, time-boxed). Calm by design: every failure ends as a status line, never an alert, and
/// never blocks the UI (all network work is `async`).
@MainActor
final class VaultSync: ObservableObject {
    nonisolated static let tasksDidChange = Notification.Name("VaultSync.tasksDidChange")

    nonisolated static let etagKey = "vault_tasks_etag"
    /// The last good tasks.json (not secret), reconciled again on a 304 so a day that moved on
    /// still moves past-dated tasks to today.
    nonisolated static let bodyKey = "vault_tasks_body"

    @Published private(set) var status: VaultStatus
    @Published private(set) var habitsStatus: VaultHabitsStatus?
    @Published private(set) var hasToken: Bool
    @Published private(set) var isChecking = false

    let tokenStore: VaultTokenStore
    let github: VaultGitHubClient
    let defaults: UserDefaults
    let calendar: Calendar
    let now: () -> Date
    let role: Role
    let lock: VaultFileLock
    private var isWritingHabits = false
#if DEBUG
    /// Screenshot harness only: Settings opens the Vault link screen once, on appear.
    var opensLinkScreenOnAppear = false
#endif

    /// Who is syncing. The widget never waits for the lock, makes one request for tasks.json (no
    /// repo check on a 404), and writes the status only on success or an auth failure, so a
    /// transient "Offline" in the widget never covers the app's status.
    enum Role {
        case app
        case widget
    }

    init(
        tokenStore: VaultTokenStore,
        http: VaultHTTPClient,
        defaults: UserDefaults,
        calendar: Calendar = .current,
        timeout: TimeInterval = 20,
        role: Role = .app,
        lock: VaultFileLock = .shared(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.role = role
        self.lock = lock
        self.github = VaultGitHubClient(
            http: http, timeout: timeout, expiryStore: VaultTokenExpiryStore(defaults: defaults),
            checksRepoOn404: role == .app, now: now
        )
        let hasToken = tokenStore.read() != nil
        self.hasToken = hasToken
        self.status = hasToken ? (VaultStatus.load(from: defaults) ?? VaultStatus(kind: .connected)) : .notSetUp
        self.habitsStatus = VaultHabitsStatus.load(from: defaults)
    }

    /// The app's own: the real Keychain and network.
    static func live() -> VaultSync {
        VaultSync(
            tokenStore: KeychainVaultTokenStore(),
            http: URLSessionVaultHTTPClient(),
            defaults: SharedPersistence.sharedDefaults
        )
    }

    var tokenExpiry: Date? { github.expiryStore?.expiry }
    var tokenLocation: VaultTokenLocation? { VaultTokenLocation.load(from: defaults) }

    /// Re-reads what another process (the widget, a background run) may have written.
    func reloadFromDefaults() {
        hasToken = tokenStore.read() != nil
        status = hasToken ? (VaultStatus.load(from: defaults) ?? VaultStatus(kind: .connected)) : .notSetUp
        habitsStatus = VaultHabitsStatus.load(from: defaults)
    }

    // MARK: - Token

    /// Saves a pasted token and starts over: the next check fetches tasks.json in full.
    func saveToken(_ token: String) throws {
        try tokenStore.save(token)
        defaults.removeObject(forKey: Self.etagKey)
        VaultTokenExpiryStore(defaults: defaults).expiry = nil
        hasToken = true
        setStatus(VaultStatus(kind: .connected, date: now()))
    }

    /// Removes the token. Imported tasks stay as they are; nothing more is fetched or sent.
    func removeToken() {
        tokenStore.delete()
        defaults.removeObject(forKey: Self.etagKey)
        VaultTokenExpiryStore(defaults: defaults).expiry = nil
        hasToken = false
        setStatus(.notSetUp)
    }

    // MARK: - tasks.json → the app

    enum FetchOutcome: Equatable {
        case notSetUp
        case busy
        case failed(VaultError)
        case newerVersion
        case badFile
        case storeFailed
        case reconciled(ListService.VaultReconcileResult)
    }

    /// Fetches tasks.json (If-None-Match with the stored ETag; a 304 reconciles the stored copy
    /// again) and reconciles it. `quietWithoutToken`: the widget and background runs, which leave
    /// the status alone when they can't reach a token.
    @discardableResult
    func refreshTasks(context: ModelContext, quietWithoutToken: Bool = false) async -> FetchOutcome {
        guard !isChecking else { return .busy }
        guard let token = tokenStore.read() else {
            if !quietWithoutToken {
                hasToken = false
                setStatus(.notSetUp)
            }
            return .notSetUp
        }
        isChecking = true
        defer { isChecking = false }

        let cached = defaults.data(forKey: Self.bodyKey)
        let etag = cached == nil ? nil : defaults.string(forKey: Self.etagKey)

        let body: Data
        var newETag: String?
        switch await github.fetchTasks(token: token, etag: etag) {
        case let .failure(error):
            if role == .app || error == .tokenNotAccepted || error == .tokenExpired {
                setStatus(VaultStatus(error: error, at: now()))
            }
            return .failed(error)
        case .success(.notModified):
            guard let cached else { return .failed(.badResponse) }
            body = cached
        case let .success(.fetched(data, etag)):
            body = data
            newETag = etag
        }

        switch VaultTasksFile.decode(body) {
        case .newerVersion:
            if role == .app { setStatus(VaultStatus(kind: .newerVersion, date: now())) }
            return .newerVersion
        case let .invalid(reason):
            AppLogger.vault.error("tasks.json rejected: \(reason, privacy: .public)")
            if role == .app { setStatus(VaultStatus(kind: .badFile, date: now())) }
            return .badFile
        case let .tasks(tasks):
            // One reconcile at a time across the app and the widget: the app waits up to 1 s, the
            // widget not at all; either skips if the other is still at it.
            guard let held = await lock.lock(waitingUpTo: role == .app ? 1 : 0) else {
                AppLogger.vault.info("Reconcile skipped: another process holds the lock")
                return .busy
            }
            defer { held.release() }
            do {
                let result = try ListService.reconcileVaultTasks(tasks, now: now(), calendar: calendar, context: context, defaults: defaults)
                // Only after the store saved: a failed save fetches the whole file again next time.
                if body != cached {
                    defaults.set(body, forKey: Self.bodyKey)
                }
                if let newETag {
                    defaults.set(newETag, forKey: Self.etagKey)
                }
                setStatus(result.manifestUnreadable
                          ? VaultStatus(kind: .manifestUnreadable, date: now())
                          : VaultStatus(kind: .updated, date: now()))
                AppLogger.vault.info("Tasks reconciled: +\(result.added.count, privacy: .public) ~\(result.updated.count, privacy: .public) -\(result.removed.count, privacy: .public)")
                if result.changedStore {
                    NotificationCenter.default.post(name: Self.tasksDidChange, object: self)
                }
                return .reconciled(result)
            } catch {
                AppLogger.vault.error("Reconcile failed: \(error.localizedDescription, privacy: .public)")
                if role == .app { setStatus(VaultStatus(kind: .problem, date: now())) }
                return .storeFailed
            }
        }
    }

    // MARK: - The app → habits file

    enum HabitsOutcome: Equatable {
        case notSetUp
        case notDue
        case busy
        case sent(dayKey: String)
        /// Two sha conflicts in a row: given up until tomorrow.
        case gaveUp
        /// Offline, auth or a GitHub error: tried again at the next chance.
        case failed(VaultError)
        case storeFailed
    }

    /// Writes `habits/YYYY-MM.json` if the gate says it's due (`VaultHabitsGate.plan`: usually one
    /// file; two when an earlier month is still to finish). Per file: GET for the sha, merge (the
    /// app's days win), PUT with the sha; a 409/422 refetches the sha and retries once, and a second
    /// conflict gives up until tomorrow. Other failures leave the day open for the next chance.
    @discardableResult
    func writeHabitsIfDue(reason: VaultHabitsGate.Reason, context: ModelContext) async -> HabitsOutcome {
        guard let token = tokenStore.read() else { return .notSetUp }
        guard !isWritingHabits else { return .busy }

        let current = now()
        let todayKey = HomeModel.dayKey(for: current, calendar: calendar)
        let rules = DayRulesStore.resolvedHistory(in: defaults, todayKey: todayKey).rules(for: todayKey)
        let morningOver = current >= rules.morningDeadline(on: current, calendar: calendar)
        let throughs = VaultHabitsGate.plan(
            reason: reason,
            todayKey: todayKey,
            lastCommitDayKey: defaults.string(forKey: VaultHabitsGate.lastCommitKey),
            morningOver: morningOver,
            calendar: calendar
        )
        guard let lastThrough = throughs.last else { return .notDue }

        isWritingHabits = true
        defer { isWritingHabits = false }

        for targetKey in throughs {
            switch await writeHabitsFile(through: targetKey, now: current, token: token, context: context) {
            case .written:
                continue
            case .gaveUp:
                defaults.set(todayKey, forKey: VaultHabitsGate.lastCommitKey)
                recordHabits(.gaveUp, dayKey: targetKey)
                return .gaveUp
            case let .failed(error):
                return failHabits(error, dayKey: targetKey)
            case .storeFailed:
                return .storeFailed
            }
        }
        defaults.set(todayKey, forKey: VaultHabitsGate.lastCommitKey)
        recordHabits(.sent, dayKey: lastThrough)
        AppLogger.vault.info("Habits sent through \(lastThrough, privacy: .public)")
        return .sent(dayKey: lastThrough)
    }

    private enum FileWrite {
        case written
        case gaveUp
        case failed(VaultError)
        case storeFailed
    }

    /// One month file through `targetKey`: GET for the sha, merge (the app's days win), PUT with
    /// the sha; a 409/422 refetches and retries once. If the vault's file already holds exactly
    /// what would be sent (apart from `updatedAt`), nothing is PUT: an earlier write whose answer
    /// was lost (the background window ran out) isn't committed twice.
    private func writeHabitsFile(through targetKey: String, now current: Date, token: String, context: ModelContext) async -> FileWrite {
        let document: JSONValue
        do {
            document = try ListService.vaultHabitsDocument(through: targetKey, now: current, calendar: calendar, context: context, defaults: defaults)
        } catch {
            AppLogger.vault.error("Habits not built: \(error.localizedDescription, privacy: .public)")
            return .storeFailed
        }
        let path = VaultAPI.habitsPath(month: String(targetKey.prefix(7)))
        let message = VaultHabits.commitMessage(for: targetKey)
        for attempt in 1...2 {
            let existing: VaultGitHubClient.RemoteFile?
            switch await github.getFile(path: path, token: token) {
            case let .failure(error):
                return .failed(error)
            case let .success(file):
                existing = file
            }
            let merged = VaultHabits.merge(document, into: existing?.content)
            if let existing, VaultHabits.sameIgnoringUpdatedAt(merged, existing.content) {
                AppLogger.vault.info("Habits already in the vault for \(targetKey, privacy: .public)")
                return .written
            }
            let content: Data
            do {
                content = try VaultHabits.encode(merged)
            } catch {
                return .storeFailed
            }
            switch await github.putFile(path: path, content: content, sha: existing?.sha, message: message, token: token) {
            case .success:
                return .written
            case .failure(.conflict) where attempt == 1:
                AppLogger.vault.info("Habits sha conflict; refetching once")
                continue
            case .failure(.conflict):
                return .gaveUp
            case let .failure(error):
                return .failed(error)
            }
        }
        return .gaveUp
    }

    // MARK: - Helpers

    private func failHabits(_ error: VaultError, dayKey: String) -> HabitsOutcome {
        AppLogger.vault.error("Habits not sent: \(String(describing: error), privacy: .public)")
        recordHabits(.failed, dayKey: dayKey)
        if error == .tokenNotAccepted || error == .tokenExpired {
            setStatus(VaultStatus(error: error, at: now()))
        }
        return .failed(error)
    }

    private func recordHabits(_ outcome: VaultHabitsStatus.Outcome, dayKey: String) {
        let record = VaultHabitsStatus(outcome: outcome, date: now(), dayKey: dayKey)
        record.save(to: defaults)
        habitsStatus = record
    }

    private func setStatus(_ newStatus: VaultStatus) {
        newStatus.save(to: defaults)
        status = newStatus
    }
}
