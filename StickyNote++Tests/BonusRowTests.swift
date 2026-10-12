import Foundation
import SwiftData
import XCTest

/// Fix round 1 (DECISIONS.md, 2026-10-12): a morning row added after that day's deadline is a
/// bonus. It shows and can be ticked, but never counts towards the verdict, the %, the streak, the
/// ring, the calendar or the habits file. "Added" is when the thing was created, never when the
/// day's row was materialised. Munich, 09:00 cutoff; 14.10.2026 is a Wednesday.
final class BonusRowTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let day = "2026-10-14"

    private func at(_ hour: Int, _ minute: Int = 0, on key: String? = nil) -> Date {
        TestCalendars.date(key ?? day, hour, minute)
    }

    private func nine(_ key: String) -> Date? {
        TestCalendars.date(key, 9)
    }

    private func schedule(_ id: UUID, start: String, createdAt: Date?) -> ListRules.ItemSchedule {
        ListRules.ItemSchedule(itemID: id, rule: .daily, startDayKey: start, endDayKey: nil, createdAt: createdAt)
    }

    /// One routine row of `item` on `day`, materialised at `createdAt`.
    private func routineRow(_ item: UUID, _ state: OccurrenceState, doneAt: Date?, createdAt: Date) -> FactRow {
        FactRow(dayKey: day, itemID: item, createdAt: createdAt, completedAt: doneAt, state: state,
                scheduledDayKey: day, periodEndDayKey: day)
    }

    private func look(_ rows: [FactRow], _ schedules: [ListRules.ItemSchedule]) -> ListRules.DayLook? {
        ListRules.dayLooks(occurrences: rows, schedules: schedules, missesBefore: day, calendar: munich, deadline: nine)[day]
    }

    // MARK: - The rule

    /// Liam's case: the routine done on time, then an item added after the cutoff and ticked.
    func testLateAddedItemTickedLateKeepsTheMorningComplete() {
        let routine = [UUID(), UUID(), UUID()]
        let vitamins = UUID()
        let schedules = routine.map { schedule($0, start: "2026-10-01", createdAt: at(7, on: "2026-10-01")) }
            + [schedule(vitamins, start: day, createdAt: at(10))]
        let rows = routine.enumerated().map { index, id in routineRow(id, .done, doneAt: at(7, 20 + index), createdAt: at(6)) }
            + [routineRow(vitamins, .done, doneAt: at(10, 5), createdAt: at(10))]

        XCTAssertEqual(look(rows, schedules), ListRules.DayLook(status: .complete, completion: .init(value: 1, isNeutral: false)))
        XCTAssertEqual(ListRules.countedRows(rows, schedules: schedules, calendar: munich, deadline: nine).count, 3)
        let streak = ListRules.streakState(through: day, occurrences: rows, schedules: schedules, calendar: munich, deadline: nine)
        XCTAssertEqual(streak, HomeModel.StreakState(count: 1, isFrozen: false))
    }

    func testLateAddedOneOffLeftUndoneKeepsTheMorningComplete() {
        let water = UUID()
        let schedules = [schedule(water, start: "2026-10-01", createdAt: at(7, on: "2026-10-01"))]
        let rows = [
            routineRow(water, .done, doneAt: at(8), createdAt: at(6)),
            FactRow(dayKey: day, createdAt: at(11), state: .open),
        ]
        XCTAssertEqual(look(rows, schedules)?.status, .complete)
        XCTAssertEqual(look(rows, schedules)?.completion.value, 1)
    }

    func testOnlyBonusRowsIsNeutral() {
        let vitamins = UUID()
        let schedules = [schedule(vitamins, start: day, createdAt: at(10))]
        let rows = [
            routineRow(vitamins, .done, doneAt: at(10, 5), createdAt: at(10)),
            FactRow(dayKey: day, createdAt: at(11), state: .open),
        ]
        XCTAssertNil(look(rows, schedules), "nothing counted: neutral, absent from the looks")
        XCTAssertTrue(ListRules.completion(ListRules.countedRows(rows, schedules: schedules, calendar: munich, deadline: nine)).isNeutral)
    }

    /// The loophole: rows for an existing routine are created when the app first reads the day.
    /// Opening it at 13:00 and ticking everything is still a late finish.
    func testRoutineFirstOpenedAfterTheCutoffIsStillLate() {
        let routine = [UUID(), UUID()]
        let schedules = routine.map { schedule($0, start: "2026-10-01", createdAt: at(7, on: "2026-10-01")) }
        let rows = routine.map { routineRow($0, .done, doneAt: at(13, 5), createdAt: at(13)) }
        XCTAssertEqual(look(rows, schedules)?.status, .missed)
        XCTAssertEqual(ListRules.countedRows(rows, schedules: schedules, calendar: munich, deadline: nine).count, 2)
    }

    /// An item added the evening before can't be a late add today.
    func testAnItemFromAnEarlierDayIsNeverABonus() {
        let stretch = UUID()
        let schedules = [schedule(stretch, start: "2026-10-13", createdAt: at(22, on: "2026-10-13"))]
        let row = routineRow(stretch, .done, doneAt: at(13), createdAt: at(13))
        XCTAssertFalse(ListRules.isBonus(row, schedules: ListRules.scheduleIndex(schedules), deadline: nine(day), calendar: munich))
        XCTAssertEqual(look([row], schedules)?.status, .missed)
    }

    /// The V2 backfill gives items a start day from the first V1 entry but `createdAt` of the
    /// backfill: created after their start day, so never a bonus.
    func testABackfilledItemIsNeverABonus() {
        let water = UUID()
        let schedules = [schedule(water, start: day, createdAt: at(20, on: "2026-10-20"))]
        let row = routineRow(water, .done, doneAt: at(8), createdAt: at(8))
        XCTAssertFalse(ListRules.isBonus(row, schedules: ListRules.scheduleIndex(schedules), deadline: nine(day), calendar: munich))
    }

    func testABumpedInRowIsNeverABonus() {
        let bumped = FactRow(dayKey: day, createdAt: at(11), state: .open, bumpedFromID: UUID(), bumpCount: 1)
        let unlinked = FactRow(dayKey: day, createdAt: at(11), state: .open, bumpCount: 2)
        for row in [bumped, unlinked] {
            XCTAssertFalse(ListRules.isBonus(row, schedules: [:], deadline: nine(day), calendar: munich))
        }
        XCTAssertEqual(look([bumped], [])?.status, .missed, "an open bumped-in row is still a miss")
    }

    func testNoDeadlineMeansNoBonus() {
        let late = FactRow(dayKey: day, createdAt: at(23), state: .done)
        XCTAssertFalse(ListRules.isBonus(late, schedules: [:], deadline: nil, calendar: munich))
    }

    func testAddedBeforeTheCutoffCounts() {
        let early = FactRow(dayKey: day, createdAt: at(8, 59), state: .open)
        XCTAssertFalse(ListRules.isBonus(early, schedules: [:], deadline: nine(day), calendar: munich))
        XCTAssertEqual(look([early], [])?.status, .missed)
    }

    // MARK: - Through the store

    private var context: ModelContext!

    override func setUpWithError() throws {
        context = try StoreTestSupport.makeContext()
    }

    override func tearDown() {
        context = nil
    }

    private func morningLook(_ key: String? = nil) throws -> ListRules.DayLook? {
        let key = key ?? day
        return try ListService.dayLooks(from: key, through: key, todayKey: key, history: DayRulesHistory(), context: context,
                                        calendar: munich).looks[.morning]?[key]
    }

    private func rows() throws -> [Occurrence] {
        try ListService.occurrences(on: day, list: .morning, context: context)
    }

    /// Liam's case end to end: an item added in Edit Lists at 10:00 and ticked at 10:05.
    func testLiamsCaseThroughTheService() throws {
        let water = Item(list: .morning, title: "Water", sortOrder: 0, repeatRule: .daily, startDayKey: "2026-10-01",
                         createdAt: at(7, on: "2026-10-01"))
        context.insert(water)
        try context.save()
        try ListService.ensureOccurrences(on: day, context: context, now: at(7), calendar: munich)
        try ListService.complete(try XCTUnwrap(try rows().first), at: at(7, 30), calendar: munich, context: context)

        let vitamins = try XCTUnwrap(ListService.addItem(list: .morning, title: "Vitamins", rule: .daily, now: at(10),
                                                         calendar: munich, context: context))
        let late = try XCTUnwrap(try rows().first { $0.itemID == vitamins.id })
        try ListService.complete(late, at: at(10, 5), calendar: munich, context: context)

        XCTAssertEqual(try ListService.bonusRowIDs(among: try rows(), history: DayRulesHistory(), context: context, calendar: munich),
                       [late.id])
        XCTAssertEqual(try morningLook()?.status, .complete)
        let streak = try ListService.streakState(for: .morning, through: day, history: DayRulesHistory(), context: context, calendar: munich)
        XCTAssertEqual(streak.count, 1)

        // The next day the item is part of the routine like any other.
        let thursday = "2026-10-15"
        try ListService.ensureOccurrences(on: thursday, context: context, now: at(13, on: thursday), calendar: munich)
        let thursdayRows = try ListService.occurrences(on: thursday, list: .morning, context: context)
        XCTAssertEqual(thursdayRows.count, 2)
        XCTAssertTrue(try ListService.bonusRowIDs(among: thursdayRows, history: DayRulesHistory(), context: context, calendar: munich).isEmpty)
    }

    /// Editing an undone routine item's repeat after the cutoff makes a replacement item; it keeps
    /// the old item's `createdAt`, so its row isn't a bonus and the morning is still missed.
    func testAnEditedRepeatsReplacementIsNotABonus() throws {
        for created in [at(7), at(7, on: "2026-10-01")] {
            context = try StoreTestSupport.makeContext()
            let water = Item(list: .morning, title: "Water", sortOrder: 0, repeatRule: .daily,
                             startDayKey: ListService.dayKey(for: created, calendar: munich), createdAt: created)
            context.insert(water)
            try context.save()
            try ListService.ensureOccurrences(on: day, context: context, now: at(7), calendar: munich)

            let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Water", rule: .weekdays, bumpLimit: .unlimited,
                                                                   now: at(13), calendar: munich, context: context))
            XCTAssertEqual(replacement.createdAt, created, "the replacement keeps when the thing was added")
            XCTAssertEqual(replacement.startDayKey, day)
            let todays = try rows()
            XCTAssertEqual(todays.map(\.itemID), [replacement.id])
            XCTAssertTrue(try ListService.bonusRowIDs(among: todays, history: DayRulesHistory(), context: context, calendar: munich).isEmpty)
            XCTAssertEqual(try morningLook()?.status, .missed, "still undone after the cutoff")
        }
    }

    /// Settings: a bonus row doesn't decide whether today's morning is complete.
    func testCountedRowsLeaveOtherListsWhole() throws {
        context.insert(Occurrence(list: .day, dayKey: day, title: "Post", createdAt: at(23)))
        context.insert(Occurrence(list: .morning, dayKey: day, title: "Late", createdAt: at(11)))
        try context.save()
        let all = try ListService.occurrences(from: day, through: day, context: context)
        let counted = try ListService.countedRows(all, history: DayRulesHistory(), context: context, calendar: munich)
        XCTAssertEqual(counted.map(\.title), ["Post"])
    }

    /// The habits file counts only the rows that count.
    func testTheHabitsFileLeavesBonusRowsOut() throws {
        let (defaults, suiteName) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let water = Item(list: .morning, title: "Water", sortOrder: 0, repeatRule: .daily, startDayKey: "2026-10-01",
                         createdAt: at(7, on: "2026-10-01"))
        context.insert(water)
        try context.save()
        try ListService.ensureOccurrences(on: day, context: context, now: at(7), calendar: munich)
        try ListService.complete(try XCTUnwrap(try rows().first), at: at(7, 30), calendar: munich, context: context)
        let vitamins = try XCTUnwrap(ListService.addItem(list: .morning, title: "Vitamins", rule: .daily, now: at(10),
                                                         calendar: munich, context: context))
        XCTAssertNotNil(try rows().first { $0.itemID == vitamins.id }, "left undone")

        let document = try ListService.vaultHabitsDocument(through: day, now: at(22), calendar: munich, context: context, defaults: defaults)
        let morning = document["days"]?[day]?["morning"]
        XCTAssertEqual(morning?["status"], .string("complete"))
        XCTAssertEqual(morning?["done"], .int(1))
        XCTAssertEqual(morning?["total"], .int(1))
    }
}
