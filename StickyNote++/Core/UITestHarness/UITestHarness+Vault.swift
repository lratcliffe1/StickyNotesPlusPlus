#if DEBUG
import Foundation
import SwiftData

/// The screenshot harness's vault link: an in-memory token and a fake GitHub, so it never touches
/// the network or the real Keychain. `-uiVault <off|updated|rejected>`:
/// - `off` (the default): no token, "Not set up".
/// - `updated`: a token; tasks.json (`sampleTasks`) is imported through the real reconcile at the
///   scenario's time, the status is "Tasks updated <time>", the habits were sent at 21:40 yesterday
///   and the token expires in a year. The fake answers every later check the same way.
/// - `rejected`: a token GitHub refuses (every request answers 401): "Token not accepted".
extension UITestHarness {
    enum VaultState: String {
        case off
        case updated
        case rejected
    }

    @MainActor
    static func makeVault(
        state: VaultState,
        defaults: UserDefaults,
        now: Date,
        context: ModelContext,
        calendar: Calendar
    ) -> VaultSync {
        let tasksData = sampleTasks(now: now, calendar: calendar)
        let http = FakeVaultHTTPClient { request in
            switch state {
            case .off, .rejected:
                return .init(status: 401, body: Data(#"{"message":"Bad credentials"}"#.utf8))
            case .updated:
                guard let url = request.url?.absoluteString else { return .init(status: 400) }
                if url.hasSuffix("/tasks.json") {
                    return .init(status: 200, headers: ["ETag": "\"harness\""], body: tasksData)
                }
                if request.httpMethod == "PUT" {
                    return .init(status: 201, body: Data("{}".utf8))
                }
                if url.contains("/habits/") {
                    return .init(status: 404, body: Data(#"{"message":"Not Found"}"#.utf8))
                }
                return .init(status: 200, body: Data("{}".utf8))
            }
        }
        let tokens = InMemoryVaultTokenStore(token: state == .off ? nil : "harness-fake-token")
        // Its own lock file: the harness never contends with a real widget.
        let lock = VaultFileLock(url: FileManager.default.temporaryDirectory.appendingPathComponent("harness-vault.lock"))
        let vault = VaultSync(tokenStore: tokens, http: http, defaults: defaults, calendar: calendar, lock: lock, now: { now })

        switch state {
        case .off:
            break
        case .updated:
            if case let .tasks(tasks) = VaultTasksFile.decode(tasksData) {
                _ = try? ListService.reconcileVaultTasks(tasks, now: now, calendar: calendar, context: context, defaults: defaults)
            }
            defaults.set(tasksData, forKey: VaultSync.bodyKey)
            defaults.set("\"harness\"", forKey: VaultSync.etagKey)
            VaultStatus(kind: .updated, date: now).save(to: defaults)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let sentAt = calendar.date(bySettingHour: 21, minute: 40, second: 0, of: yesterday) ?? yesterday
            VaultHabitsStatus(outcome: .sent, date: sentAt, dayKey: HomeModel.dayKey(for: yesterday, calendar: calendar))
                .save(to: defaults)
            // Today counts as sent, so the harness never writes habits at launch.
            defaults.set(HomeModel.dayKey(for: now, calendar: calendar), forKey: VaultHabitsGate.lastCommitKey)
            VaultTokenExpiryStore(defaults: defaults).expiry = calendar.date(byAdding: .year, value: 1, to: now)
        case .rejected:
            VaultStatus(kind: .tokenNotAccepted, date: now).save(to: defaults)
            // No habits write at launch either (it would add a "not sent" line).
            defaults.set(HomeModel.dayKey(for: now, calendar: calendar), forKey: VaultHabitsGate.lastCommitKey)
        }
        vault.reloadFromDefaults()
        return vault
    }

    /// Four Now.md tasks relative to the scenario's day: two today (one that must happen today,
    /// one with a deadline in three days), one dated yesterday (moved to today) and one tomorrow.
    static func sampleTasks(now: Date, calendar: Calendar) -> Data {
        func day(_ offset: Int) -> String {
            HomeModel.dayKey(for: calendar.date(byAdding: .day, value: offset, to: now) ?? now, calendar: calendar)
        }
        let json = """
        {
          "version": 1,
          "generatedAt": "2026-10-12T05:00:12Z",
          "sourceCommit": "harness",
          "tasks": [
            { "id": "tmb-huts-booking", "title": "Book TMB huts Days 1–5 (opens today)", "list": "day",
              "dayKey": "\(day(0))", "bumpLimit": { "kind": "cantBump" } },
            { "id": "deel-chase", "title": "Chase Deel if no answers", "list": "day",
              "dayKey": "\(day(0))", "deadlineDayKey": "\(day(3))", "bumpLimit": { "kind": "untilDeadline" } },
            { "id": "passport-photos", "title": "Renew passport photos", "dayKey": "\(day(-1))" },
            { "id": "tax-return-docs", "title": "Send the tax adviser the 2025 documents", "dayKey": "\(day(1))",
              "futureField": "ignored" }
          ]
        }
        """
        return Data(json.utf8)
    }
}
#endif
