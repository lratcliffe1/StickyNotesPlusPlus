import Foundation
import Security
import SwiftData
import XCTest

/// The vault link end to end against a fake GitHub (`FakeVaultHTTPClient`): requests, the ETag /
/// 304 path, how answers map to the status line, and the habits write (gate, merge, conflicts).
@MainActor
final class VaultSyncTests: XCTestCase {
    private let munich = TestCalendars.munich
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var tokens: InMemoryVaultTokenStore!
    private var http: FakeVaultHTTPClient!
    private var now = TestCalendars.date("2026-10-14", 22)

    private let goodFile = Data("""
    { "version": 1, "tasks": [
      { "id": "deel", "title": "Chase Deel", "dayKey": "2026-10-14" },
      { "id": "huts", "title": "Book huts", "dayKey": "2026-10-13", "bumpLimit": { "kind": "cantBump" } }
    ] }
    """.utf8)

    override func setUp() async throws {
        context = try StoreTestSupport.makeContext()
        let made = StoreTestSupport.makeDefaults()
        defaults = made.defaults
        suiteName = made.name
        tokens = InMemoryVaultTokenStore(token: "test-token")
        http = FakeVaultHTTPClient { _ in .init(status: 500) }
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private lazy var lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("vault-sync-test-\(UUID().uuidString).lock")

    private func makeSync(role: VaultSync.Role = .app, lock: VaultFileLock?? = nil) -> VaultSync {
        VaultSync(
            tokenStore: tokens, http: http, defaults: defaults, calendar: munich,
            role: role, lock: lock ?? VaultFileLock(url: lockURL), now: { [unowned self] in self.now }
        )
    }

    private func reply(_ status: Int, _ body: String = "{}", headers: [String: String] = [:]) -> FakeVaultHTTPClient.Reply {
        .init(status: status, headers: headers, body: Data(body.utf8))
    }

    private func isRepo(_ request: URLRequest) -> Bool {
        request.url?.absoluteString == "https://api.github.com/repos/lratcliffe1/Obsidian"
    }

    private func rowCount() throws -> Int {
        try StoreTestSupport.all(Occurrence.self, in: context).count
    }

    // MARK: - Fetching tasks.json

    func testFetchSendsTheDocumentedRequestAndImports() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let sync = makeSync()
        let outcome = await sync.refreshTasks(context: context)

        guard case let .reconciled(result) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(result.added, ["deel", "huts"])
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/lratcliffe1/Obsidian/contents/7%20Projects/StickyNotes/tasks.json")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github.raw+json")
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(sync.status.kind, .updated)
        XCTAssertEqual(sync.status.date, now)
        XCTAssertEqual(defaults.string(forKey: VaultSync.etagKey), "\"v1\"")
        XCTAssertEqual(try ListService.occurrence(id: VaultTaskID.occurrenceID(for: "huts", dayKey: "2026-10-14"), context: context)?.dayKey,
                       "2026-10-14", "a past day lands on today")
    }

    func testNotModifiedReconcilesTheStoredCopy() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let sync = makeSync()
        await sync.refreshTasks(context: context)

        // The next day, nothing changed in the vault: a 304. Yesterday's open rows stay (its misses);
        // the still-open tasks get today's rows.
        now = TestCalendars.date("2026-10-15", 8)
        http.handler = { _ in .init(status: 304) }
        let outcome = await sync.refreshTasks(context: context)

        XCTAssertEqual(http.requests.last?.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
        guard case let .reconciled(result) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(Set(result.added), ["deel", "huts"])
        XCTAssertEqual(try ListService.occurrence(id: VaultTaskID.occurrenceID(for: "deel", dayKey: "2026-10-15"), context: context)?.dayKey, "2026-10-15")
        XCTAssertEqual(try ListService.occurrence(id: VaultTaskID.occurrenceID(for: "deel", dayKey: "2026-10-14"), context: context)?.dayKey, "2026-10-14")
        XCTAssertEqual(sync.status, VaultStatus(kind: .updated, date: now))
    }

    func testStatusMapping() async throws {
        let cases: [(FakeVaultHTTPClient.Reply, VaultStatus.Kind, String)] = [
            (reply(401, #"{"message":"Bad credentials"}"#), .tokenNotAccepted, "Token not accepted"),
            (reply(401, #"{"message":"Token expired"}"#), .tokenExpired, "Token expired"),
            (reply(403, #"{"message":"Resource not accessible by personal access token"}"#), .tokenNotAccepted, "Token not accepted"),
            (reply(403, #"{"message":"API rate limit exceeded"}"#, headers: ["x-ratelimit-remaining": "0"]), .problem, "GitHub didn’t answer (403)"),
            (reply(502), .problem, "GitHub didn’t answer (502)"),
            (.init(error: URLError(.notConnectedToInternet)), .offline, "Offline"),
            (.init(error: URLError(.timedOut)), .offline, "Offline"),
        ]
        for (answer, kind, text) in cases {
            http.handler = { _ in answer }
            let sync = makeSync()
            await sync.refreshTasks(context: context)
            XCTAssertEqual(sync.status.kind, kind, text)
            XCTAssertEqual(sync.status.text(now: now, calendar: munich), text)
            XCTAssertEqual(VaultStatus.load(from: defaults)?.kind, kind, "shared with the widget and Settings")
        }
        XCTAssertEqual(try rowCount(), 0, "no answer changes the lists")
    }

    func testA404IsNoFileYetOnlyIfTheTokenSeesTheRepo() async throws {
        http.handler = { request in self.isRepo(request) ? self.reply(200) : self.reply(404, #"{"message":"Not Found"}"#) }
        let sync = makeSync()
        await sync.refreshTasks(context: context)
        XCTAssertEqual(sync.status.kind, .noTasksFile)
        XCTAssertEqual(sync.status.text(), "No tasks file yet")

        http.handler = { _ in self.reply(404, #"{"message":"Not Found"}"#) }
        await sync.refreshTasks(context: context)
        XCTAssertEqual(sync.status.kind, .tokenNotAccepted, "a token without the repo gets 404s too")
    }

    func testA401AfterTheTokensExpiryReadsAsExpired() async throws {
        http.handler = { _ in
            .init(status: 200, headers: ["GitHub-Authentication-Token-Expiration": "2026-10-14 08:00:00 +0200"], body: self.goodFile)
        }
        let sync = makeSync()
        await sync.refreshTasks(context: context)
        XCTAssertEqual(sync.tokenExpiry, TestCalendars.date("2026-10-14", 8))

        http.handler = { _ in self.reply(401, #"{"message":"Bad credentials"}"#) }
        await sync.refreshTasks(context: context)
        XCTAssertEqual(sync.status.kind, .tokenExpired)
    }

    func testANewerFileChangesNothing() async throws {
        http.handler = { _ in self.reply(200, #"{ "version": 2, "tasks": [] }"#, headers: ["ETag": "\"v2\""]) }
        let sync = makeSync()
        let outcome = await sync.refreshTasks(context: context)
        XCTAssertEqual(outcome, .newerVersion)
        XCTAssertEqual(sync.status.text(), "tasks.json is newer than this app")
        XCTAssertNil(defaults.string(forKey: VaultSync.etagKey), "fetched in full again next time")
    }

    func testABadFileChangesNothing() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let sync = makeSync()
        await sync.refreshTasks(context: context)
        XCTAssertEqual(try rowCount(), 2)

        // An empty task list would remove both; a broken file must not.
        http.handler = { _ in self.reply(200, #"{ "version": 1, "tasks": [ { "id": "Bad Id", "title": "x", "dayKey": "2026-10-14" } ] }"#) }
        let outcome1 = await sync.refreshTasks(context: context)
        XCTAssertEqual(outcome1, .badFile)
        http.handler = { _ in self.reply(200, "{ not json") }
        let outcome2 = await sync.refreshTasks(context: context)
        XCTAssertEqual(outcome2, .badFile)
        XCTAssertEqual(try rowCount(), 2)
        XCTAssertEqual(sync.status.kind, .badFile)
        XCTAssertEqual(defaults.string(forKey: VaultSync.etagKey), "\"v1\"", "the last good file's ETag is kept")
    }

    func testWithoutATokenNothingIsSent() async throws {
        tokens = InMemoryVaultTokenStore()
        let sync = makeSync()
        let outcome3 = await sync.refreshTasks(context: context)
        XCTAssertEqual(outcome3, .notSetUp)
        XCTAssertEqual(sync.status, .notSetUp)
        XCTAssertEqual(sync.status.text(), "Not set up")
        let outcome4 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome4, .notSetUp)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testTheWidgetLeavesTheStatusAloneWithoutAToken() async throws {
        VaultStatus(kind: .updated, date: now).save(to: defaults)
        tokens = InMemoryVaultTokenStore()
        let sync = makeSync()
        let outcome5 = await sync.refreshTasks(context: context, quietWithoutToken: true)
        XCTAssertEqual(outcome5, .notSetUp)
        XCTAssertEqual(VaultStatus.load(from: defaults)?.kind, .updated)
    }

    func testSavingATokenSaysConnectedAndRemovingItSaysNotSetUp() throws {
        tokens = InMemoryVaultTokenStore()
        let sync = makeSync()
        XCTAssertFalse(sync.hasToken)
        try sync.saveToken("  github_pat_example  ")
        XCTAssertEqual(tokens.read(), "github_pat_example")
        XCTAssertEqual(sync.status.text(), "Connected")
        sync.removeToken()
        XCTAssertNil(tokens.read())
        XCTAssertEqual(sync.status.text(), "Not set up")
        XCTAssertThrowsError(try sync.saveToken("   "))
    }

    func testTheTokenNeverReachesTheDefaults() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let sync = makeSync()
        try sync.saveToken("github_pat_SECRET123")
        await sync.refreshTasks(context: context)
        let stored = defaults.dictionaryRepresentation().values.map { value -> String in
            if let data = value as? Data { return String(decoding: data, as: UTF8.self) }
            return "\(value)"
        }
        XCTAssertFalse(stored.contains { $0.contains("SECRET123") })
    }

    // MARK: - Writing the habits file

    private func habitsFile(sha: String, days: String = #"{ "2026-10-01": { "morning": { "status": "complete" } } }"#) -> FakeVaultHTTPClient.Reply {
        let content = Data(#"{ "version": 1, "month": "2026-10", "days": \#(days) }"#.utf8).base64EncodedString()
        return reply(200, #"{ "sha": "\#(sha)", "content": "\#(content)", "encoding": "base64" }"#)
    }

    private struct PutBody: Decodable {
        let message: String
        let content: String
        let sha: String?
    }

    private func putBody(_ request: URLRequest?) throws -> PutBody {
        try JSONDecoder().decode(PutBody.self, from: try XCTUnwrap(request?.httpBody))
    }

    func testHabitsAreMergedAndPutWithTheSha() async throws {
        context.insert(Occurrence(list: .day, dayKey: "2026-10-14", title: "A", state: .done, completedAt: TestCalendars.date("2026-10-14", 12)))
        try context.save()
        http.handler = { request in request.httpMethod == "PUT" ? self.reply(201) : self.habitsFile(sha: "s1") }
        let sync = makeSync()

        let outcome = await sync.writeHabitsIfDue(reason: .background, context: context)

        XCTAssertEqual(outcome, .sent(dayKey: "2026-10-14"))
        XCTAssertEqual(http.requests.map(\.httpMethod), ["GET", "PUT"])
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(http.requests[1].url?.absoluteString,
                       "https://api.github.com/repos/lratcliffe1/Obsidian/contents/7%20Projects/StickyNotes/habits/2026-10.json")
        let body = try putBody(http.requests[1])
        XCTAssertEqual(body.message, "StickyNotes: habits 2026-10-14")
        XCTAssertEqual(body.sha, "s1")
        let written = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(Data(base64Encoded: body.content)))
        XCTAssertEqual(written["days"]?["2026-10-01"]?["morning"]?["status"], .string("complete"), "the vault's other days stay")
        XCTAssertEqual(written["days"]?["2026-10-14"]?["day"]?["status"], .string("complete"))
        XCTAssertEqual(defaults.string(forKey: VaultHabitsGate.lastCommitKey), "2026-10-14")
        XCTAssertEqual(sync.habitsStatus?.outcome, .sent)
    }

    func testAtMostOneCommitADay() async throws {
        http.handler = { request in request.httpMethod == "PUT" ? self.reply(201) : self.habitsFile(sha: "s1") }
        let sync = makeSync()
        let outcome6 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome6, .sent(dayKey: "2026-10-14"))
        let outcome7 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome7, .notDue)
        let outcome8 = await sync.writeHabitsIfDue(reason: .launch, context: context)
        XCTAssertEqual(outcome8, .notDue)
        XCTAssertEqual(http.requests.count, 2)
    }

    func testANewFileIsCreatedWithoutASha() async throws {
        http.handler = { request in
            if request.httpMethod == "PUT" { return self.reply(201) }
            return self.isRepo(request) ? self.reply(200) : self.reply(404, #"{"message":"Not Found"}"#)
        }
        let sync = makeSync()
        let outcome9 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome9, .sent(dayKey: "2026-10-14"))
        XCTAssertNil(try putBody(http.requests.last).sha)
    }

    func testAConflictRefetchesTheShaAndRetriesOnce() async throws {
        var puts = 0
        var gets = 0
        http.handler = { request in
            if request.httpMethod == "PUT" {
                puts += 1
                return puts == 1 ? self.reply(409, #"{"message":"is at s2 but expected s1"}"#) : self.reply(200)
            }
            gets += 1
            return self.habitsFile(sha: gets == 1 ? "s1" : "s2")
        }
        let sync = makeSync()
        let outcome10 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome10, .sent(dayKey: "2026-10-14"))
        XCTAssertEqual(http.requests.map(\.httpMethod), ["GET", "PUT", "GET", "PUT"])
        XCTAssertEqual(try putBody(http.requests[1]).sha, "s1")
        XCTAssertEqual(try putBody(http.requests[3]).sha, "s2")
    }

    func testASecondConflictGivesUpUntilTomorrow() async throws {
        http.handler = { request in request.httpMethod == "PUT" ? self.reply(422) : self.habitsFile(sha: "s1") }
        let sync = makeSync()
        let outcome11 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome11, .gaveUp)
        XCTAssertEqual(http.requests.map(\.httpMethod), ["GET", "PUT", "GET", "PUT"], "one retry, no more")
        XCTAssertEqual(sync.habitsStatus?.outcome, .gaveUp)
        let outcome12 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome12, .notDue)

        now = TestCalendars.date("2026-10-15", 22)
        http.handler = { request in request.httpMethod == "PUT" ? self.reply(201) : self.habitsFile(sha: "s1") }
        let outcome13 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome13, .sent(dayKey: "2026-10-15"))
    }

    func testOfflineLeavesTheDayOpenForTheNextChance() async throws {
        http.handler = { _ in .init(error: URLError(.notConnectedToInternet)) }
        let sync = makeSync()
        let outcome14 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome14, .failed(.offline))
        XCTAssertNil(defaults.string(forKey: VaultHabitsGate.lastCommitKey))

        http.handler = { request in request.httpMethod == "PUT" ? self.reply(201) : self.habitsFile(sha: "s1") }
        let outcome15 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome15, .sent(dayKey: "2026-10-14"))
    }

    func testAReadOnlyTokenShowsInTheStatus() async throws {
        http.handler = { request in
            request.httpMethod == "PUT"
                ? self.reply(403, #"{"message":"Resource not accessible by personal access token"}"#)
                : self.habitsFile(sha: "s1")
        }
        let sync = makeSync()
        let outcome16 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome16, .failed(.tokenNotAccepted))
        XCTAssertEqual(sync.status.kind, .tokenNotAccepted)
    }

    func testNothingIsWrittenBeforeTheMorningEnds() async throws {
        now = TestCalendars.date("2026-10-14", 8, 30)
        defaults.set("2026-10-13", forKey: VaultHabitsGate.lastCommitKey)
        let sync = makeSync()
        let outcome17 = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(outcome17, .notDue)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testALaunchSendsAnUnsentYesterday() async throws {
        now = TestCalendars.date("2026-10-14", 7)
        defaults.set("2026-10-12", forKey: VaultHabitsGate.lastCommitKey)
        http.handler = { request in request.httpMethod == "PUT" ? self.reply(201) : self.habitsFile(sha: "s1") }
        let sync = makeSync()
        let outcome18 = await sync.writeHabitsIfDue(reason: .launch, context: context)
        XCTAssertEqual(outcome18, .sent(dayKey: "2026-10-13"))
        XCTAssertEqual(try putBody(http.requests.last).message, "StickyNotes: habits 2026-10-13")
        XCTAssertEqual(defaults.string(forKey: VaultHabitsGate.lastCommitKey), "2026-10-14", "today's commit is used")
    }

    // MARK: - The once-a-day gate

    func testGatePlan() {
        func plan(_ reason: VaultHabitsGate.Reason, today: String, last: String?, morningOver: Bool = true) -> [String] {
            VaultHabitsGate.plan(reason: reason, todayKey: today, lastCommitDayKey: last, morningOver: morningOver, calendar: munich)
        }
        XCTAssertEqual(plan(.background, today: "2026-10-14", last: "2026-10-13"), ["2026-10-14"])
        XCTAssertEqual(plan(.background, today: "2026-10-14", last: "2026-10-14"), [], "one commit a day")
        XCTAssertEqual(plan(.background, today: "2026-10-14", last: "2026-10-13", morningOver: false), [], "not before the morning ends")
        XCTAssertEqual(plan(.background, today: "2026-11-01", last: "2026-10-31"), ["2026-10-31", "2026-11-01"],
                       "the 1st finishes last month, then starts this one")
        XCTAssertEqual(plan(.background, today: "2026-11-03", last: "2026-10-29"), ["2026-10-31", "2026-11-03"],
                       "a gap across a month end finishes the old month")
        XCTAssertEqual(plan(.launch, today: "2026-10-14", last: "2026-10-13"), [], "yesterday was sent")
        XCTAssertEqual(plan(.launch, today: "2026-10-14", last: "2026-10-12"), ["2026-10-13"])
        XCTAssertEqual(plan(.launch, today: "2026-10-14", last: nil), ["2026-10-13"])
        XCTAssertEqual(plan(.launch, today: "2026-11-02", last: "2026-10-30"), ["2026-10-31", "2026-11-01"])
        XCTAssertEqual(plan(.launch, today: "2026-10-14", last: "2026-10-14"), [])
    }

    func testAGapAcrossAMonthEndFinalisesTheOldMonth() async throws {
        now = TestCalendars.date("2026-11-03", 22)
        defaults.set("2026-10-29", forKey: VaultHabitsGate.lastCommitKey)
        context.insert(Occurrence(list: .day, dayKey: "2026-10-31", title: "Last of October", state: .done,
                                  completedAt: TestCalendars.date("2026-10-31", 12)))
        try context.save()
        http.handler = { request in request.httpMethod == "PUT" ? self.reply(201) : self.habitsFile(sha: "s1") }
        let sync = makeSync()

        let outcome = await sync.writeHabitsIfDue(reason: .background, context: context)

        XCTAssertEqual(outcome, .sent(dayKey: "2026-11-03"))
        let puts = http.requests.filter { $0.httpMethod == "PUT" }
        XCTAssertEqual(puts.map { $0.url?.lastPathComponent }, ["2026-10.json", "2026-11.json"])
        XCTAssertEqual(try putBody(puts[0]).message, "StickyNotes: habits 2026-10-31")
        let october = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(Data(base64Encoded: try putBody(puts[0]).content)))
        XCTAssertEqual(october["days"]?["2026-10-31"]?["day"]?["status"], .string("complete"), "the month's last day is final")
        XCTAssertEqual(defaults.string(forKey: VaultHabitsGate.lastCommitKey), "2026-11-03")
    }

    func testAWriteWhoseAnswerWasLostIsNotCommittedAgain() async throws {
        var landed: Data?
        http.handler = { request in
            if request.httpMethod == "PUT" {
                // GitHub took it, but the background window ran out before the answer came.
                landed = (try? JSONDecoder().decode(PutBody.self, from: request.httpBody ?? Data()))
                    .flatMap { Data(base64Encoded: $0.content) }
                return .init(error: URLError(.networkConnectionLost))
            }
            if let landed {
                return self.reply(200, #"{ "sha": "s2", "content": "\#(landed.base64EncodedString())" }"#)
            }
            return self.isRepo(request) ? self.reply(200) : self.reply(404, #"{"message":"Not Found"}"#)
        }
        let sync = makeSync()
        let first = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(first, .failed(.offline))
        XCTAssertNil(defaults.string(forKey: VaultHabitsGate.lastCommitKey))

        now = TestCalendars.date("2026-10-14", 22, 5)
        let second = await sync.writeHabitsIfDue(reason: .background, context: context)
        XCTAssertEqual(second, .sent(dayKey: "2026-10-14"))
        XCTAssertEqual(http.requests.filter { $0.httpMethod == "PUT" }.count, 1, "no second commit")
        XCTAssertEqual(defaults.string(forKey: VaultHabitsGate.lastCommitKey), "2026-10-14")
    }

    // MARK: - The widget

    func testTheWidgetKeepsTheAppsStatusWhenOfflineAndSkipsTheRepoCheck() async throws {
        VaultStatus(kind: .updated, date: now).save(to: defaults)
        http.handler = { _ in .init(error: URLError(.timedOut)) }
        _ = await makeSync(role: .widget).refreshTasks(context: context)
        XCTAssertEqual(VaultStatus.load(from: defaults)?.kind, .updated, "a widget timeout never shows as Offline")

        http.handler = { _ in self.reply(404, #"{"message":"Not Found"}"#) }
        let before = http.requests.count
        _ = await makeSync(role: .widget).refreshTasks(context: context)
        XCTAssertEqual(http.requests.count - before, 1, "one request, no repo check")
        XCTAssertEqual(VaultStatus.load(from: defaults)?.kind, .updated)

        http.handler = { _ in self.reply(401, #"{"message":"Bad credentials"}"#) }
        _ = await makeSync(role: .widget).refreshTasks(context: context)
        XCTAssertEqual(VaultStatus.load(from: defaults)?.kind, .tokenNotAccepted, "auth failures do show")
    }

    func testAReconcileWaitsForTheOtherProcessThenSkips() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let held = try XCTUnwrap(VaultFileLock(url: lockURL).tryLock().held)
        let widget = await makeSync(role: .widget).refreshTasks(context: context)
        XCTAssertEqual(widget, .busy)
        XCTAssertEqual(try rowCount(), 0)
        XCTAssertNil(defaults.string(forKey: VaultSync.etagKey), "nothing recorded: the next check fetches it again")
        held.release()
        let app = await makeSync().refreshTasks(context: context)
        guard case .reconciled = app else { return XCTFail("should import: \(app)") }
        XCTAssertEqual(try rowCount(), 2)
    }

    func testARebuiltManifestShowsInTheStatusOnce() async throws {
        defaults.set(Data("garbage".utf8), forKey: VaultManifest.storageKey)
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let sync = makeSync()
        await sync.refreshTasks(context: context)
        XCTAssertEqual(sync.status.kind, .manifestRebuilt)
        XCTAssertEqual(sync.status.text(), "Imported tasks: rebuilt; a task deleted in the app may come back once")
        XCTAssertTrue(sync.status.isProblem)
        XCTAssertEqual(try rowCount(), 2)

        http.handler = { _ in .init(status: 304) }
        await sync.refreshTasks(context: context)
        XCTAssertEqual(sync.status.kind, .updated, "the next import is back to normal")
    }

    func testAnUnopenableLockFileShowsInTheStatusAndImportsNothing() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let broken = VaultFileLock(url: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/vault.lock"))
        let sync = makeSync(lock: .some(broken))
        let outcome = await sync.refreshTasks(context: context)
        XCTAssertEqual(outcome, .lockFailed)
        XCTAssertEqual(sync.status.text(), "Imported tasks: couldn’t lock")
        XCTAssertEqual(try rowCount(), 0)
    }

    func testWithoutAContainerOnlyTheAppImports() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let widget = await makeSync(role: .widget, lock: .some(nil)).refreshTasks(context: context)
        XCTAssertEqual(widget, .busy)
        XCTAssertEqual(try rowCount(), 0)
        let app = await makeSync(lock: .some(nil)).refreshTasks(context: context)
        guard case .reconciled = app else { return XCTFail("the app imports without a lock: \(app)") }
        XCTAssertEqual(try rowCount(), 2)
    }

    func testAFreshContextSeesARowTheWidgetTicked() async throws {
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v1\""], body: self.goodFile) }
        let sync = makeSync()
        // The app's own context imports, and holds the row in memory.
        await sync.refreshTasks(context: context)
        let appRow = try XCTUnwrap(try ListService.occurrence(id: VaultTaskID.occurrenceID(for: "deel", dayKey: "2026-10-14"), context: context))
        XCTAssertEqual(appRow.state, .open)

        // The widget ticks it in its own context.
        let widgetContext = ModelContext(context.container)
        let widgetRow = try XCTUnwrap(try ListService.occurrence(id: appRow.id, context: widgetContext))
        try ListService.complete(widgetRow, at: now, context: widgetContext)

        // Now.md rewords it; the app imports in a fresh context, as the app does.
        let reworded = Data(String(decoding: goodFile, as: UTF8.self).replacingOccurrences(of: "Chase Deel", with: "Chase Deel again").utf8)
        http.handler = { _ in .init(status: 200, headers: ["ETag": "\"v2\""], body: reworded) }
        await sync.refreshTasks(context: ModelContext(context.container))

        let check = ModelContext(context.container)
        let stored = try XCTUnwrap(try ListService.occurrence(id: appRow.id, context: check))
        XCTAssertEqual(stored.state, .done, "the tick stands")
        XCTAssertEqual(stored.title, "Chase Deel", "a ticked row is never retitled")
    }

    // MARK: - Status text

    func testStatusTexts() {
        let at = TestCalendars.date("2026-10-14", 7, 2)
        XCTAssertTrue(VaultStatus(kind: .updated, date: at).text(now: now, calendar: munich).hasPrefix("Tasks updated "))
        XCTAssertTrue(VaultStatus(kind: .updated, date: TestCalendars.date("2026-10-13", 21)).text(now: now, calendar: munich)
            .hasPrefix("Tasks updated yesterday "))
        XCTAssertEqual(VaultStatus(error: .notFound, at: at).text(), "No tasks file yet")
        XCTAssertEqual(VaultStatus(error: .offline, at: at).text(), "Offline")
        XCTAssertEqual(VaultStatus(error: .tokenExpired, at: at).text(), "Token expired")
        XCTAssertEqual(VaultStatus(error: .tokenNotAccepted, at: at).text(), "Token not accepted")
    }

    func testExpiryHeaderParsing() {
        XCTAssertEqual(VaultGitHubClient.parseExpiry("2027-10-12 08:00:00 +0200"), TestCalendars.date("2027-10-12", 8))
        XCTAssertNil(VaultGitHubClient.parseExpiry("someday"))
    }
}
