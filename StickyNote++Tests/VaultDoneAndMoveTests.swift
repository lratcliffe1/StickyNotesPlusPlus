import Foundation
import SwiftData
import XCTest

/// Fix round 2 (docs/VAULT-API.md, "done" and "Moved to a later day"; DECISIONS.md, 2026-10-12):
/// a task done in a Claude session is ticked, not removed; a task moved from today to a later day
/// leaves today's row skipped as "Moved to <day>"; a rename keeps the row. In-memory V2 store;
/// today is Wednesday 14.10.2026 in Munich.
final class VaultDoneAndMoveTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let today = "2026-10-14"
    private let yesterday = "2026-10-13"
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

    private func task(_ id: String, _ title: String? = nil, list: ListKind = .day, day: String = "2026-10-14") -> VaultTask {
        VaultTask(id: id, title: title ?? id, list: list, dayKey: day, deadlineDayKey: nil, bumpLimit: .upToDays(3))
    }

    private func done(_ id: String, _ day: String = "2026-10-14", _ hour: Int = 10, _ minute: Int = 40) -> VaultDone {
        VaultDone(id: id, dayKey: day, doneAt: TestCalendars.date(day, hour, minute))
    }

    @discardableResult
    private func reconcile(
        _ tasks: [VaultTask], done: [VaultDone] = [], at date: Date? = nil, calendar: Calendar? = nil
    ) throws -> ListService.VaultReconcileResult {
        try ListService.reconcileVaultTasks(
            tasks, done: done, now: date ?? now, calendar: calendar ?? munich, context: context, defaults: defaults
        )
    }

    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }

    private func row(_ id: String, on day: String = "2026-10-14") throws -> Occurrence? {
        try ListService.occurrence(id: VaultTaskID.occurrenceID(for: id, dayKey: day), context: context)
    }

    private func allRows() throws -> [Occurrence] {
        try StoreTestSupport.all(Occurrence.self, in: context)
    }

    private var manifest: VaultManifest? { VaultManifest.load(from: defaults) }

    private func look(_ day: String) throws -> ListRules.DayLook? {
        try ListService.dayLooks(
            from: day, through: day, todayKey: today, history: DayRulesHistory(), context: context, calendar: munich
        ).looks[.day]?[day]
    }

    // MARK: - A. Done in the vault → ticked in the app

    func testADoneEntryTicksTodaysOpenRowAtDoneAt() throws {
        try reconcile([task("niall")])
        let result = try reconcile([], done: [done("niall")])

        XCTAssertEqual(result.ticked, ["niall"])
        XCTAssertTrue(result.removed.isEmpty, "ticked, not removed")
        let row = try XCTUnwrap(row("niall"))
        XCTAssertEqual(row.state, .done)
        XCTAssertEqual(row.completedAt, TestCalendars.date(today, 10, 40))
        XCTAssertEqual(try allRows().count, 1)
    }

    func testADoneEntryForYesterdayTicksYesterdaysOpenRowAndDropsTodaysCarriedRow() throws {
        try reconcile([task("a", day: yesterday)], at: TestCalendars.date(yesterday, 9))
        // This morning the routine carried it to today.
        try reconcile([task("a", day: today)], at: TestCalendars.date(today, 7))
        XCTAssertEqual(try row("a")?.state, .open)

        // A session at 23:50 last night finished it.
        let result = try reconcile([], done: [done("a", yesterday, 23, 50)])

        XCTAssertEqual(result.ticked, ["a"])
        let past = try XCTUnwrap(row("a", on: yesterday))
        XCTAssertEqual(past.state, .done, "the one change a past day gets: a real completion inside it")
        XCTAssertEqual(past.completedAt, TestCalendars.date(yesterday, 23, 50))
        XCTAssertNil(try row("a"), "today's carried row goes: the task is done")
        XCTAssertEqual(try look(yesterday)?.status, .complete)
        XCTAssertEqual(
            try ListService.streakState(for: .day, through: yesterday, history: DayRulesHistory(), context: context, calendar: munich).count,
            1
        )
    }

    func testDoneEarlyRemovesTheFutureRowAndAddsADoneRowOnItsDay() throws {
        try reconcile([task("huts", "Book huts", day: "2026-10-16")])
        let result = try reconcile([], done: [done("huts", today, 11, 0)])

        XCTAssertEqual(result.ticked, ["huts"])
        XCTAssertEqual(result.removed, ["huts"])
        XCTAssertNil(try row("huts", on: "2026-10-16"))
        let doneRow = try XCTUnwrap(row("huts"), "a done row on its day, same id scheme")
        XCTAssertEqual(doneRow.state, .done)
        XCTAssertEqual(doneRow.title, "Book huts")
        XCTAssertEqual(doneRow.completedAt, TestCalendars.date(today, 11, 0))
        XCTAssertEqual(try allRows().count, 1)
        XCTAssertEqual(manifest?.entries["huts"]?.rows, [today: doneRow.id])
        XCTAssertEqual(try look(today)?.status, .complete)
    }

    func testADoneEntryLeavesARowTickedInTheAppAlone() throws {
        try reconcile([task("a")])
        let row = try XCTUnwrap(row("a"))
        try ListService.complete(row, at: TestCalendars.date(today, 9), context: context)

        let result = try reconcile([], done: [done("a", today, 11, 0)])

        XCTAssertEqual(result.untouched, ["a"])
        XCTAssertTrue(result.ticked.isEmpty)
        XCTAssertEqual(row.completedAt, TestCalendars.date(today, 9), "an existing tick is never retimed")
        let proposed = try ListService.vaultTasksDone(from: today, through: today, context: context, defaults: defaults)
        XCTAssertEqual(proposed[today]?.map(\.id), ["a"], "ticked in the app: still proposed")
    }

    func testAVaultTickUntickedInTheAppIsNotTickedAgain() throws {
        try reconcile([task("a")])
        try reconcile([], done: [done("a")])
        let row = try XCTUnwrap(row("a"))
        XCTAssertTrue(try ListService.uncomplete(row, context: context))

        let again = try reconcile([], done: [done("a")])

        XCTAssertTrue(again.ticked.isEmpty)
        XCTAssertTrue(again.removed.isEmpty, "a done task's rows are never removed as gone from the file")
        XCTAssertEqual(row.state, .open, "Liam's un-tick stays")
    }

    func testTheSameDoneEntryOnEveryFetchChangesNothing() throws {
        try reconcile([task("a")])
        try reconcile([], done: [done("a")])
        let stored = manifest

        for date in [now, TestCalendars.date(today, 18), TestCalendars.date("2026-10-15", 9), TestCalendars.date("2026-10-20", 9)] {
            let result = try reconcile([], done: [done("a")], at: date)
            XCTAssertFalse(result.changedStore, "at \(date)")
            XCTAssertTrue(result.ticked.isEmpty)
        }
        XCTAssertEqual(try allRows().count, 1)
        XCTAssertEqual(try row("a")?.completedAt, TestCalendars.date(today, 10, 40))
        XCTAssertEqual(stored?.entries["a"]?.doneApplied, [today])
        let tickedID = try XCTUnwrap(try row("a")).id
        XCTAssertEqual(stored?.entries["a"]?.tickedByVault, [today: tickedID])
    }

    func testADoneTaskIsNeverRemovedByTheGoneFromFileRule() throws {
        try reconcile([task("done-one"), task("dropped")])
        let result = try reconcile([], done: [done("done-one")])

        XCTAssertEqual(result.removed, ["dropped"], "a task gone without a done entry is removed as before")
        XCTAssertEqual(try row("done-one")?.state, .done)
        XCTAssertNil(try row("dropped"))
    }

    func testVaultTickedRowsAreLeftOutOfVaultTasksDoneButCountAsDone() throws {
        try reconcile([task("vault"), task("app")])
        try reconcile([task("app")], done: [done("vault")])
        try ListService.complete(try XCTUnwrap(row("app")), at: now, context: context)

        let proposed = try ListService.vaultTasksDone(from: today, through: today, context: context, defaults: defaults)
        XCTAssertEqual(proposed[today]?.map(\.id), ["app"], "the vault's tick is already deleted from Now.md")

        let todaysLook = try XCTUnwrap(try look(today))
        XCTAssertEqual(todaysLook.status, .complete)
        XCTAssertEqual(todaysLook.completion.value, 1, "both count as done")
        XCTAssertEqual(
            try ListService.streakState(for: .day, through: today, history: DayRulesHistory(), context: context, calendar: munich).count,
            1
        )
    }

    func testADoneEntryForATaskTheAppNeverKnewDoesNothing() throws {
        let result = try reconcile([], done: [done("never-seen")])
        XCTAssertFalse(result.changedStore)
        XCTAssertTrue(try allRows().isEmpty)
        XCTAssertNil(manifest?.entries["never-seen"])
    }

    func testADoneEntryOutsideTheWeekIsIgnored() throws {
        try reconcile([task("a", day: "2026-10-07")], at: TestCalendars.date("2026-10-07", 9))
        let result = try reconcile([], done: [done("a", "2026-10-07", 20, 0)])
        XCTAssertTrue(result.ticked.isEmpty)
        XCTAssertEqual(try row("a", on: "2026-10-07")?.state, .open, "7 days ago: past the contract's window")
    }

    func testADoneEntryTicksTodaysMovedRowAndDropsTheLaterOne() throws {
        try reconcile([task("a")])
        try reconcile([task("a", day: "2026-10-16")])
        XCTAssertEqual(try row("a")?.state, .skipped)

        let result = try reconcile([], done: [done("a", today, 15, 0)])

        XCTAssertEqual(result.ticked, ["a"])
        XCTAssertEqual(try row("a")?.state, .done)
        XCTAssertNil(try row("a", on: "2026-10-16"))
        XCTAssertTrue(manifest?.movedRowDays.isEmpty ?? false, "no longer a moved row")
    }

    // MARK: - A. Review fixes

    func testNoDoneRowIsAddedOnAPastDay() throws {
        try reconcile([task("a", day: "2026-10-16")], at: TestCalendars.date(yesterday, 9))
        let result = try reconcile([], done: [done("a", yesterday, 20, 0)])

        XCTAssertTrue(result.ticked.isEmpty)
        XCTAssertNil(try row("a", on: yesterday), "a row would mark yesterday opened and wipe its misses")
        XCTAssertNil(try row("a", on: "2026-10-16"), "the later row still goes: it's done")
        XCTAssertTrue(try allRows().isEmpty)
        XCTAssertEqual(manifest?.entries["a"]?.doneApplied, [yesterday], "a deliberate no: final")
    }

    func testNoDoneRowIsAddedOnTheMorningList() throws {
        try reconcile([task("m", list: .morning, day: "2026-10-16")])
        let result = try reconcile([], done: [done("m", today, 11, 0)])

        XCTAssertTrue(result.ticked.isEmpty)
        XCTAssertNil(try row("m"), "a late add with a late tick would make the morning a miss")
        XCTAssertNil(try row("m", on: "2026-10-16"))
    }

    func testABumpedRowDoneInASessionLosesItsOpenCopy() throws {
        try reconcile([task("a")])
        let original = try XCTUnwrap(row("a"))
        let copy = try XCTUnwrap(try ListService.bump(original, now: now, calendar: munich, context: context))
        XCTAssertEqual(copy.dayKey, "2026-10-15")
        let copyID = copy.id

        let result = try reconcile([], done: [done("a", today, 15, 0)])

        XCTAssertEqual(result.untouched, ["a"], "the bump wins: it counts as done already")
        XCTAssertEqual(result.removed, ["a"])
        XCTAssertNil(try ListService.occurrence(id: copyID, context: context), "the stale copy goes")
        XCTAssertEqual(original.state, .bumped)
        XCTAssertNil(original.bumpedToID, "unlinked")
        XCTAssertEqual(try allRows().count, 1)
    }

    func testADoneEntryIsJudgedInMunichTimeWhenThePhoneIsInLondon() throws {
        let londonNoon = TestCalendars.date(today, 12, calendar: london)
        try reconcile([task("a")], at: londonNoon, calendar: london)
        // 00:30 in Munich on the 14th is 23:30 on the 13th in London.
        let doneAt = TestCalendars.date(today, 0, 30)
        let result = try reconcile([], done: [VaultDone(id: "a", dayKey: today, doneAt: doneAt)], at: londonNoon, calendar: london)

        XCTAssertEqual(result.ticked, ["a"])
        XCTAssertEqual(try row("a")?.state, .done)
        XCTAssertEqual(try row("a")?.completedAt, doneAt)
    }

    func testARefusedTickIsNotRecordedAsApplied() throws {
        try reconcile([task("a")])
        // An entry whose doneAt (the 13th in Munich) is before its dayKey: the tick is refused.
        let refused = VaultDone(id: "a", dayKey: today, doneAt: TestCalendars.date(yesterday, 20))
        let result = try reconcile([], done: [refused])

        XCTAssertTrue(result.ticked.isEmpty)
        XCTAssertEqual(try row("a")?.state, .open)
        XCTAssertNil(manifest?.entries["a"]?.doneApplied, "tried again next time")

        try reconcile([], done: [done("a")])
        XCTAssertEqual(try row("a")?.state, .done, "a corrected entry still ticks it")
    }

    func testAnIDInBothTasksAndDoneIsATask() throws {
        try reconcile([task("a")])
        let result = try reconcile([task("a")], done: [done("a")])
        XCTAssertTrue(result.ticked.isEmpty)
        XCTAssertEqual(try row("a")?.state, .open, "the file still lists it: not done")
        XCTAssertNil(manifest?.entries["a"]?.doneApplied)
    }

    func testTheGoneRuleAppliesOnceTheDoneEntryLeavesTheWeek() throws {
        try reconcile([task("a", day: "2026-10-25")])
        // As if its done entry for today had been applied with nothing to do.
        var stored = try XCTUnwrap(manifest)
        stored.entries["a"]?.doneApplied = [today]
        stored.save(to: defaults)

        let inTheWeek = try reconcile([], done: [done("a")], at: TestCalendars.date("2026-10-20", 9))
        XCTAssertTrue(inTheWeek.removed.isEmpty, "a done task's rows aren't removed as gone")
        XCTAssertNotNil(try row("a", on: "2026-10-25"))

        let afterTheWeek = try reconcile([], done: [done("a")], at: TestCalendars.date("2026-10-21", 9))
        XCTAssertEqual(afterTheWeek.removed, ["a"], "out of the window: an ordinary task gone from the file")
        XCTAssertNil(try row("a", on: "2026-10-25"))
    }

    // MARK: - B. Moved later in the vault → "Moved to <day>" on today

    func testMovingTodayToFridayLeavesASkippedMovedRowAndAFridayRow() throws {
        try reconcile([task("a")])
        let todays = try XCTUnwrap(row("a"))

        let result = try reconcile([task("a", day: "2026-10-16")])

        XCTAssertEqual(result.moved, ["a"])
        XCTAssertEqual(result.added, ["a"])
        XCTAssertTrue(result.removed.isEmpty, "today's row stays")
        XCTAssertEqual(todays.state, .skipped)
        XCTAssertEqual(try row("a", on: "2026-10-16")?.state, .open)
        XCTAssertEqual(manifest?.movedRowDays, [todays.id: "2026-10-16"])
        // Like a skip: no credit, no miss (a day with only skipped rows has nothing counted).
        let todayStatus = try look(today)?.status
        XCTAssertTrue(todayStatus == nil || todayStatus == .neutral, "got \(String(describing: todayStatus))")
        XCTAssertEqual(try ListService.occurrences(on: today, list: .day, context: context).filter { $0.state != .skipped }.count, 0)

        // The same file again changes nothing.
        let again = try reconcile([task("a", day: "2026-10-16")])
        XCTAssertFalse(again.changedStore)
        XCTAssertEqual(try allRows().count, 2)
    }

    func testMovingBetweenFutureDaysKeepsTheOldBehaviour() throws {
        try reconcile([task("a", day: "2026-10-16")])
        let result = try reconcile([task("a", day: "2026-10-18")])
        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertEqual(result.removed, ["a"])
        XCTAssertNil(try row("a", on: "2026-10-16"))
        XCTAssertEqual(try row("a", on: "2026-10-18")?.state, .open)
        XCTAssertEqual(try allRows().count, 1)
        XCTAssertTrue(manifest?.movedRowDays.isEmpty ?? false)
    }

    func testMovingBackToTodayLeavesExactlyOneRowToday() throws {
        try reconcile([task("a", "Chase")])
        try reconcile([task("a", "Chase", day: "2026-10-16")])
        let result = try reconcile([task("a", "Chase (today after all)")])

        let todays = try ListService.occurrences(on: today, list: .day, context: context)
        XCTAssertEqual(todays.count, 1, "one row per task per day")
        let movedRowID = try row("a")?.id
        XCTAssertEqual(todays.first?.id, movedRowID, "the moved row, un-skipped")
        XCTAssertEqual(todays.first?.state, .open)
        XCTAssertEqual(todays.first?.title, "Chase (today after all)")
        XCTAssertNil(try row("a", on: "2026-10-16"))
        XCTAssertEqual(result.updated, ["a"])
        XCTAssertTrue(manifest?.movedRowDays.isEmpty ?? false)

        // A tick today settles it as usual.
        try ListService.complete(try XCTUnwrap(row("a")), at: now, context: context)
        let tomorrow = try reconcile([task("a", day: "2026-10-15")], at: TestCalendars.date("2026-10-15", 9))
        XCTAssertTrue(tomorrow.added.isEmpty)
    }

    func testAMovedRowFromAnEarlierDayStaysHistory() throws {
        try reconcile([task("a", day: yesterday)], at: TestCalendars.date(yesterday, 9))
        try reconcile([task("a", day: "2026-10-16")], at: TestCalendars.date(yesterday, 12))
        // Today, Now.md brings it back to today: yesterday's moved row is history; today gets a row.
        let result = try reconcile([task("a")])
        XCTAssertEqual(result.added, ["a"])
        XCTAssertEqual(try row("a", on: yesterday)?.state, .skipped)
        XCTAssertEqual(try row("a")?.state, .open)
        XCTAssertNil(try row("a", on: "2026-10-16"))
    }

    func testASecondMoveUpdatesTheMovedRowsDay() throws {
        try reconcile([task("a")])
        let todays = try XCTUnwrap(row("a"))
        try reconcile([task("a", day: "2026-10-16")])
        try reconcile([task("a", day: "2026-10-18")])

        XCTAssertEqual(manifest?.movedRowDays, [todays.id: "2026-10-18"])
        XCTAssertNil(try row("a", on: "2026-10-16"))
        XCTAssertEqual(try row("a", on: "2026-10-18")?.state, .open)
        XCTAssertEqual(todays.state, .skipped)
    }

    func testAMovedTaskThatLeavesTheFileIsNoLongerPlanned() throws {
        try reconcile([task("a")])
        let todays = try XCTUnwrap(row("a"))
        try reconcile([task("a", day: "2026-10-16")])

        let result = try reconcile([])

        XCTAssertEqual(result.removed, ["a"])
        XCTAssertNil(try row("a", on: "2026-10-16"))
        XCTAssertEqual(todays.state, .skipped, "still history, still actionless")
        XCTAssertEqual(manifest?.movedRowDays, [todays.id: ""], "\"No longer planned\"")
    }

    func testAMovedTaskWhoseLaterRowIsDeletedInTheAppIsNoLongerPlanned() throws {
        try reconcile([task("a")])
        let todays = try XCTUnwrap(row("a"))
        try reconcile([task("a", day: "2026-10-16")])
        XCTAssertTrue(try ListService.deleteOneOff(try XCTUnwrap(row("a", on: "2026-10-16")), todayKey: today, context: context))

        try reconcile([task("a", day: "2026-10-16")])

        XCTAssertEqual(manifest?.movedRowDays, [todays.id: ""])
    }

    // MARK: - C. Renames

    func testARenameKeepsTheRow() throws {
        try reconcile([task("a", "Email Niall")])
        let original = try XCTUnwrap(row("a"))

        let result = try reconcile([task("a", "Email Niall: confirm the Entleiher")])

        XCTAssertEqual(result.updated, ["a"])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(try allRows().map(\.id), [original.id], "same id, same row")
        XCTAssertEqual(original.title, "Email Niall: confirm the Entleiher")
        XCTAssertEqual(original.state, .open)
    }

    // MARK: - The manifest

    func testAManifestFromBeforeFixRoundTwoStillReads() throws {
        let id = UUID()
        let old = "{\"entries\":{\"a\":{\"fingerprint\":\"a|day|-|upToDays|3\",\"rows\":{\"2026-10-14\":\"" + id.uuidString
            + "\"},\"settledOn\":\"2026-10-14\"}}}"
        defaults.set(Data(old.utf8), forKey: VaultManifest.storageKey)
        let entry = try XCTUnwrap(manifest?.entries["a"])
        XCTAssertEqual(entry.rows, [today: id])
        XCTAssertNil(entry.doneApplied)
        XCTAssertNil(entry.tickedByVault)
        XCTAssertNil(entry.movedTo)
    }
}
