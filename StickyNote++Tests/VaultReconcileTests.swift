import Foundation
import SwiftData
import XCTest

/// Reconciling tasks.json into the store (docs/VAULT-API.md, "App reconciliation"), on an in-memory
/// V2 store: one row per task per day, past days frozen. Today is Wednesday 14.10.2026 in Munich.
final class VaultReconcileTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let today = "2026-10-14"
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        context = try StoreTestSupport.makeContext()
        let made = StoreTestSupport.makeDefaults()
        defaults = made.defaults
        suiteName = made.name
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        context = nil
        defaults = nil
    }

    private var now: Date { TestCalendars.date(today, 12) }

    private func task(
        _ id: String,
        _ title: String? = nil,
        list: ListKind = .day,
        day: String = "2026-10-14",
        deadline: String? = nil,
        limit: BumpLimit = .upToDays(3)
    ) -> VaultTask {
        VaultTask(id: id, title: title ?? id, list: list, dayKey: day, deadlineDayKey: deadline, bumpLimit: limit)
    }

    @discardableResult
    private func reconcile(_ tasks: [VaultTask], at date: Date? = nil) throws -> ListService.VaultReconcileResult {
        try ListService.reconcileVaultTasks(tasks, now: date ?? now, calendar: munich, context: context, defaults: defaults)
    }

    private func row(_ id: String, on day: String = "2026-10-14") throws -> Occurrence? {
        try ListService.occurrence(id: VaultTaskID.occurrenceID(for: id, dayKey: day), context: context)
    }

    private func allRows() throws -> [Occurrence] {
        try StoreTestSupport.all(Occurrence.self, in: context)
    }

    private var manifest: VaultManifest? { VaultManifest.load(from: defaults) }

    // MARK: - New

    func testNewTasksAreAddedAsOneOffsWithPerDayIDs() throws {
        let result = try reconcile([
            task("deel", "Chase Deel", day: "2026-10-16", deadline: "2026-10-16", limit: .untilDeadline(dayKey: "2026-10-16")),
            task("huts", "Book huts", list: .morning, limit: .cantBump),
        ])
        XCTAssertEqual(result.added, ["deel", "huts"])

        let deel = try XCTUnwrap(row("deel", on: "2026-10-16"))
        XCTAssertNil(deel.itemID, "a one-off")
        XCTAssertEqual(deel.title, "Chase Deel")
        XCTAssertEqual(deel.list, .day)
        XCTAssertEqual(deel.dayKey, "2026-10-16")
        XCTAssertEqual(deel.deadlineDayKey, "2026-10-16")
        XCTAssertEqual(deel.bumpLimit, .untilDeadline(dayKey: "2026-10-16"))
        XCTAssertEqual(deel.state, .open)

        let huts = try XCTUnwrap(row("huts"))
        XCTAssertEqual(huts.list, .morning)
        XCTAssertEqual(huts.bumpLimit, .cantBump)

        XCTAssertEqual(manifest?.entries["deel"]?.rows, ["2026-10-16": deel.id])
        XCTAssertEqual(Set(manifest?.entries.keys.map { $0 } ?? []), ["deel", "huts"])
    }

    func testAPastDayLandsOnToday() throws {
        try reconcile([task("old", day: "2026-10-10")])
        XCTAssertEqual(try row("old")?.dayKey, today)
        XCTAssertNil(try row("old", on: "2026-10-10"))
    }

    func testReconcilingTwiceChangesNothing() throws {
        try reconcile([task("a"), task("b", day: "2026-10-20")])
        let second = try reconcile([task("a"), task("b", day: "2026-10-20")])
        XCTAssertFalse(second.changedStore)
        XCTAssertEqual(try allRows().count, 2)
    }

    func testAnExistingRowIsNeverInsertedAgainSoATickSurvives() throws {
        try reconcile([task("a")])
        let row = try XCTUnwrap(row("a"))
        try ListService.complete(row, at: now, context: context)
        // The widget's manifest write was lost: the derived id still finds the row, ticked.
        defaults.removeObject(forKey: VaultManifest.storageKey)
        let result = try reconcile([task("a")])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(try allRows().count, 1)
        XCTAssertEqual(row.state, .done)
    }

    // MARK: - Update (today and later only)

    func testAnOpenNeverBumpedRowFollowsTheFile() throws {
        try reconcile([task("a", "Old title", day: "2026-10-15")])
        let result = try reconcile([
            task("a", "New title", list: .evening, day: "2026-10-15", deadline: "2026-10-18", limit: .untilDeadline(dayKey: "2026-10-18")),
        ])
        XCTAssertEqual(result.updated, ["a"])
        let row = try XCTUnwrap(row("a", on: "2026-10-15"))
        XCTAssertEqual(row.title, "New title")
        XCTAssertEqual(row.list, .evening)
        XCTAssertEqual(row.dayKey, "2026-10-15")
        XCTAssertEqual(row.deadlineDayKey, "2026-10-18")
        XCTAssertEqual(row.bumpLimit, .untilDeadline(dayKey: "2026-10-18"))
    }

    func testADeadlineCanBeDropped() throws {
        try reconcile([task("a", deadline: "2026-10-18", limit: .untilDeadline(dayKey: "2026-10-18"))])
        try reconcile([task("a", limit: .upToDays(3))])
        let row = try XCTUnwrap(row("a"))
        XCTAssertNil(row.deadlineDayKey)
        XCTAssertEqual(row.bumpLimit, .upToDays(3))
    }

    func testAMovedDateReplacesTheOpenFutureRow() throws {
        try reconcile([task("a", day: "2026-10-20")])
        let result = try reconcile([task("a", day: "2026-10-15")])
        XCTAssertEqual(result.added, ["a"])
        XCTAssertEqual(result.removed, ["a"])
        XCTAssertNotNil(try row("a", on: "2026-10-15"))
        XCTAssertNil(try row("a", on: "2026-10-20"))
        XCTAssertEqual(try allRows().count, 1)
        XCTAssertEqual(manifest?.entries["a"]?.rows.keys.sorted(), ["2026-10-15"])
    }

    func testAnEditMadeInTheAppLastsUntilTheFileChanges() throws {
        try reconcile([task("a", "From Now.md")])
        let row = try XCTUnwrap(row("a"))
        XCTAssertTrue(try ListService.editOneOff(row, title: "My wording", bumpLimit: .unlimited, deadlineDayKey: nil, todayKey: today, context: context))

        try reconcile([task("a", "From Now.md")])
        XCTAssertEqual(row.title, "My wording", "the file didn't change: the edit stays")
        XCTAssertEqual(row.bumpLimit, .unlimited)

        try reconcile([task("a", "Now.md reworded")])
        XCTAssertEqual(row.title, "Now.md reworded", "the file changed: it wins")
    }

    // MARK: - Past days are history

    func testAnOpenRowOnAPastDayStaysAsThatDaysMissAndTodayGetsANewRow() throws {
        let yesterday = TestCalendars.date("2026-10-13", 9)
        try reconcile([task("a", "Chase", day: "2026-10-13", limit: .cantBump)], at: yesterday)
        let past = try XCTUnwrap(row("a", on: "2026-10-13"))

        let result = try reconcile([task("a", "Chase (reworded)", day: "2026-10-13", limit: .cantBump)])

        XCTAssertEqual(result.added, ["a"])
        XCTAssertEqual(past.dayKey, "2026-10-13", "never moved")
        XCTAssertEqual(past.title, "Chase", "never retitled")
        XCTAssertEqual(past.firstAddedDayKey, "2026-10-13")
        XCTAssertEqual(past.state, .open, "still yesterday's miss")
        let fresh = try XCTUnwrap(row("a"))
        XCTAssertEqual(fresh.title, "Chase (reworded)")
        XCTAssertEqual(fresh.bumpLimit, .cantBump)
        let looks = try ListService.dayLooks(
            from: "2026-10-13", through: "2026-10-13", todayKey: today,
            history: DayRulesHistory(), context: context, calendar: munich
        ).looks
        XCTAssertEqual(looks[.day]?["2026-10-13"]?.status, .missed)
    }

    func testRemovalNeverDeletesPastRows() throws {
        try reconcile([task("a", day: "2026-10-13")], at: TestCalendars.date("2026-10-13", 9))
        let result = try reconcile([])
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertNotNil(try row("a", on: "2026-10-13"), "yesterday's open row stays")
    }

    func testAPastDoneTaskIsNotAddedAgain() throws {
        try reconcile([task("a", day: "2026-10-13")], at: TestCalendars.date("2026-10-13", 9))
        try ListService.complete(try XCTUnwrap(row("a", on: "2026-10-13")), at: TestCalendars.date("2026-10-13", 18), context: context)

        // The routine hasn't removed it yet: still dated the 13th.
        let result = try reconcile([task("a", day: "2026-10-13")])
        XCTAssertEqual(result.untouched, ["a"])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(try allRows().count, 1)
    }

    func testAReusedIDForALaterDayGetsANewRow() throws {
        try reconcile([task("water-plants")])
        try ListService.complete(try XCTUnwrap(row("water-plants")), at: now, context: context)

        // Back in Now.md for next week.
        let result = try reconcile([task("water-plants", day: "2026-10-21")])
        XCTAssertEqual(result.added, ["water-plants"])
        XCTAssertEqual(try row("water-plants")?.state, .done, "the tick stays")
        XCTAssertEqual(try row("water-plants", on: "2026-10-21")?.state, .open)
    }

    func testAReusedIDComesBackEvenAfterThePrune() throws {
        try reconcile([task("a", day: "2026-08-01")], at: TestCalendars.date("2026-08-01", 9))
        try ListService.complete(try XCTUnwrap(row("a", on: "2026-08-01")), at: TestCalendars.date("2026-08-01", 10), context: context)
        try reconcile([], at: TestCalendars.date("2026-08-02", 9))
        try reconcile([])
        XCTAssertNil(manifest?.entries["a"], "pruned after 62 days")

        try reconcile([task("a")])
        XCTAssertEqual(try row("a")?.state, .open)
    }

    // MARK: - Ticks and bumps win

    func testDoneAndSkippedRowsAreNeverTouched() throws {
        try reconcile([task("done", "Done"), task("skipped", "Skipped")])
        let done = try XCTUnwrap(row("done"))
        try ListService.complete(done, at: now, context: context)
        let skipped = try XCTUnwrap(row("skipped"))
        skipped.state = .skipped
        try context.save()

        let changed = try reconcile([task("done", "Renamed"), task("skipped", "Renamed")])
        XCTAssertEqual(Set(changed.untouched), ["done", "skipped"])
        XCTAssertEqual(done.title, "Done")
        XCTAssertEqual(done.state, .done)
        XCTAssertEqual(skipped.title, "Skipped")
        XCTAssertEqual(skipped.state, .skipped)

        let gone = try reconcile([])
        XCTAssertTrue(gone.removed.isEmpty, "gone from the file but ticked: kept")
        XCTAssertEqual(try allRows().count, 2)
    }

    func testABumpedTaskOwnsItsFuture() throws {
        try reconcile([task("a", "Original")])
        let original = try XCTUnwrap(row("a"))
        let copy = try XCTUnwrap(try ListService.bump(original, newTitle: "Retyped", now: now, calendar: munich, context: context))

        let result = try reconcile([task("a", "Renamed in Now.md")])
        XCTAssertEqual(result.untouched, ["a"])
        XCTAssertEqual(original.state, .bumped)
        XCTAssertEqual(original.title, "Original")
        XCTAssertEqual(copy.title, "Retyped")

        // Tomorrow the file still says the 14th: no new row next to the bumped copy.
        let tomorrow = try reconcile([task("a", "Renamed in Now.md")], at: TestCalendars.date("2026-10-15", 9))
        XCTAssertTrue(tomorrow.added.isEmpty)
        XCTAssertEqual(try allRows().count, 2)

        // Gone from Now.md: the bumped row and its open copy both stay.
        let removal = try reconcile([])
        XCTAssertTrue(removal.removed.isEmpty)
        XCTAssertEqual(try allRows().count, 2)
    }

    // MARK: - Remove

    func testAnOpenTaskGoneFromTheFileIsRemoved() throws {
        try reconcile([task("keep"), task("drop", day: "2026-10-16")])
        let result = try reconcile([task("keep")])
        XCTAssertEqual(result.removed, ["drop"])
        XCTAssertNil(try row("drop", on: "2026-10-16"))
        XCTAssertNotNil(try row("keep"))
        XCTAssertNil(manifest?.entries["drop"])
    }

    func testATaskDeletedInTheAppStaysDeleted() throws {
        try reconcile([task("a")])
        XCTAssertTrue(try ListService.deleteOneOff(try XCTUnwrap(row("a")), todayKey: today, context: context))

        let result = try reconcile([task("a")])
        XCTAssertEqual(result.deletedInApp, ["a"])
        XCTAssertTrue(result.added.isEmpty)
        let tomorrow = try reconcile([task("a")], at: TestCalendars.date("2026-10-15", 9))
        XCTAssertEqual(tomorrow.deletedInApp, ["a"], "still deleted the next day")
        XCTAssertEqual(try allRows().count, 0)
    }

    func testOtherOneOffsAreNeverTouched() throws {
        let mine = try XCTUnwrap(try ListService.addOneOff(list: .day, dayKey: today, title: "Typed in the app", now: now, context: context))
        try reconcile([task("a")])
        try reconcile([])
        XCTAssertEqual(try allRows().map(\.id), [mine.id])
    }

    func testImportedTasksSortAfterExistingOneOffs() throws {
        let mine = try XCTUnwrap(try ListService.addOneOff(list: .day, dayKey: today, title: "Mine", now: now, context: context))
        try reconcile([task("a"), task("b")])
        let order = try ListService.occurrences(on: today, list: .day, context: context)
        XCTAssertEqual(order.first?.id, mine.id)
        XCTAssertEqual(Set(order.map(\.sortOrder)).count, 3, "each gets its own place")
    }

    // MARK: - The routines carry still-listed actions forward

    private var yesterdayMorning: Date { TestCalendars.date("2026-10-13", 9) }

    func testATaskTickedYesterdayAndCarriedToTodayIsNotAddedAgain() throws {
        try reconcile([task("a", day: "2026-10-13")], at: yesterdayMorning)
        try ListService.complete(try XCTUnwrap(row("a", on: "2026-10-13")), at: TestCalendars.date("2026-10-13", 18), context: context)

        // Now.md still lists it (done means deleted, later): the routine re-dates it to today.
        let result = try reconcile([task("a", day: today)])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(result.untouched, ["a"])
        XCTAssertNil(try row("a"))
        XCTAssertEqual(VaultManifest.load(from: defaults)?.entries["a"]?.settledOn, "2026-10-13")
    }

    func testATaskDeletedInTheAppAndCarriedForwardStaysDeleted() throws {
        try reconcile([task("a", day: "2026-10-13")], at: yesterdayMorning)
        XCTAssertTrue(try ListService.deleteOneOff(try XCTUnwrap(row("a", on: "2026-10-13")), todayKey: "2026-10-13", context: context))

        let result = try reconcile([task("a", day: today)])
        XCTAssertEqual(result.deletedInApp, ["a"])
        XCTAssertEqual(try allRows().count, 0)
    }

    func testABumpedTaskCarriedForwardHasOnlyItsBumpedCopyToday() throws {
        try reconcile([task("a", day: "2026-10-13")], at: yesterdayMorning)
        let original = try XCTUnwrap(row("a", on: "2026-10-13"))
        let copy = try XCTUnwrap(try ListService.bump(original, now: yesterdayMorning, calendar: munich, context: context))
        XCTAssertEqual(copy.dayKey, today)

        let result = try reconcile([task("a", day: today)])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertNil(try row("a"), "no second row next to the bumped copy")
        XCTAssertEqual(try ListService.occurrences(on: today, list: .day, context: context).map(\.id), [copy.id])

        try ListService.complete(copy, at: now, context: context)
        let done = try ListService.vaultTasksDone(from: today, through: today, context: context, defaults: defaults)
        XCTAssertEqual(done[today]?.map(\.id), ["a"], "counted once")
    }

    func testASettledTaskGivenAnExplicitFutureDayGetsANewRow() throws {
        try reconcile([task("a", day: "2026-10-13")], at: yesterdayMorning)
        try ListService.complete(try XCTUnwrap(row("a", on: "2026-10-13")), at: TestCalendars.date("2026-10-13", 18), context: context)
        try reconcile([task("a", day: today)])

        let result = try reconcile([task("a", day: "2026-10-20")])
        XCTAssertEqual(result.added, ["a"])
        XCTAssertEqual(try row("a", on: "2026-10-20")?.state, .open)

        // On the day it comes due, and carried past it while open, it's a normal open task again.
        let onTheDay = try reconcile([task("a", day: "2026-10-20")], at: TestCalendars.date("2026-10-20", 9))
        XCTAssertTrue(onTheDay.added.isEmpty)
        let carried = try reconcile([task("a", day: "2026-10-21")], at: TestCalendars.date("2026-10-21", 9))
        XCTAssertEqual(carried.added, ["a"], "the 20th was missed, not settled")
    }

    func testATaskThatLeftTheFileAndCameBackIsScheduledAgain() throws {
        try reconcile([task("a")])
        try ListService.complete(try XCTUnwrap(row("a")), at: now, context: context)
        try reconcile([], at: TestCalendars.date("2026-10-15", 9))
        let back = try reconcile([task("a", day: "2026-10-16")], at: TestCalendars.date("2026-10-16", 9))
        XCTAssertEqual(back.added, ["a"])
    }

    func testDoneTasksCountOncePerDayEvenWithTwoRows() throws {
        try reconcile([task("a")])
        try ListService.complete(try XCTUnwrap(row("a")), at: now, context: context)
        // A second row of the same task, done the same day (as an older build could leave).
        let extraID = VaultTaskID.occurrenceID(for: "a", dayKey: "2026-10-13")
        context.insert(Occurrence(id: extraID, list: .day, dayKey: today, title: "a", state: .done, completedAt: now))
        try context.save()
        var stored = try XCTUnwrap(VaultManifest.load(from: defaults))
        stored.entries["a"]?.rows["2026-10-13"] = extraID
        stored.save(to: defaults)

        let done = try ListService.vaultTasksDone(from: today, through: today, context: context, defaults: defaults)
        XCTAssertEqual(done[today]?.count, 1)
    }

    func testAListedTaskIsNeverPruned() throws {
        try reconcile([task("a", day: "2026-08-01")], at: TestCalendars.date("2026-08-01", 9))
        try ListService.complete(try XCTUnwrap(row("a", on: "2026-08-01")), at: TestCalendars.date("2026-08-01", 10), context: context)
        let result = try reconcile([task("a", day: today)])
        XCTAssertTrue(result.added.isEmpty, "still settled 74 days later")
        XCTAssertNotNil(VaultManifest.load(from: defaults)?.entries["a"]?.rows["2026-08-01"])
    }

    // MARK: - An unreadable manifest

    func testAnUnreadableManifestIsRebuiltFromTheStore() throws {
        try reconcile([task("c", day: "2026-10-13")], at: yesterdayMorning)
        try reconcile([task("a"), task("b", day: "2026-10-16"), task("c", day: today)])
        try ListService.complete(try XCTUnwrap(row("a")), at: now, context: context)
        defaults.set(Data("not json".utf8), forKey: VaultManifest.storageKey)

        let result = try reconcile([task("a", "Renamed"), task("b", day: "2026-10-16"), task("c", day: today)])

        XCTAssertTrue(result.manifestRebuilt)
        XCTAssertTrue(result.added.isEmpty, "every row was found again")
        XCTAssertEqual(try row("a")?.state, .done)
        XCTAssertEqual(try row("a")?.title, "a", "a ticked row is never retitled")
        XCTAssertNotNil(try row("c", on: "2026-10-13"))
        XCTAssertEqual(try allRows().count, 4)
        let rebuilt = try XCTUnwrap(VaultManifest.load(from: defaults))
        XCTAssertEqual(rebuilt.entries["c"]?.rows.keys.sorted(), ["2026-10-13", today])
        XCTAssertEqual(rebuilt.entries["a"]?.settledOn, today)

        // Back to normal: a task gone from the file is removed again.
        let next = try reconcile([task("a"), task("c", day: today)])
        XCTAssertFalse(next.manifestRebuilt)
        XCTAssertEqual(next.removed, ["b"])
    }

    // MARK: - Vault rows

    func testVaultOccurrenceIDsFollowBumpChains() throws {
        try reconcile([task("a")])
        let original = try XCTUnwrap(row("a"))
        let copy = try XCTUnwrap(try ListService.bump(original, now: now, calendar: munich, context: context))
        XCTAssertEqual(try ListService.vaultOccurrenceIDs(context: context, defaults: defaults), [original.id, copy.id])
    }

    // MARK: - The lock

    func testTheLockIsExclusiveAcrossHandlesAndReleases() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vault-lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = VaultFileLock(url: url)
        let second = VaultFileLock(url: url)

        let held = try XCTUnwrap(first.tryLock().held)
        guard case .busy = second.tryLock() else { return XCTFail("a second holder is refused at once") }
        let waited = await second.lock(waitingUpTo: 0.3)
        guard case .busy = waited else { return XCTFail("and after waiting, while it's still held") }
        held.release()
        XCTAssertNotNil(second.tryLock().held)
    }

    func testALockFileThatCantBeOpenedIsUnavailable() {
        let lock = VaultFileLock(url: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/vault.lock"))
        guard case .unavailable = lock.tryLock() else { return XCTFail("should be unavailable") }
    }
}
