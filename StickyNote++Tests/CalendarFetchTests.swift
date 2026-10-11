import Foundation
import SwiftData
import XCTest

/// What the calendar and the 7-day ring read through `ListService`, one range of days at a time.
final class CalendarFetchTests: XCTestCase {
    private let munich = TestCalendars.munich
    private var context: ModelContext!

    override func setUpWithError() throws {
        context = try StoreTestSupport.makeContext()
    }

    override func tearDown() {
        context = nil
    }

    @discardableResult
    private func insertItem(_ title: String, list: ListKind, rule: RepeatRule, start: String) -> Item {
        let item = Item(list: list, title: title, sortOrder: 0, repeatRule: rule, startDayKey: start)
        context.insert(item)
        return item
    }

    func testFirstUseIsTheEarlierOfAListsItemsAndRows() throws {
        insertItem("Water", list: .morning, rule: .daily, start: "2026-10-05")
        context.insert(Occurrence(list: .morning, dayKey: "2026-10-03", title: "Early one-off"))
        context.insert(Occurrence(list: .day, dayKey: "2026-10-08", title: "Post"))
        insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        try context.save()

        XCTAssertEqual(try ListService.firstUseDayKeys(context: context), [.morning: "2026-10-03", .day: "2026-10-08"],
                       "evening never used")
    }

    /// Nobody opened the week of Monday 28 September: the weekly item's miss lands on its period end,
    /// Sunday 4 October, and October's looks (fetched from October minus a week) include it.
    func testAMonthsLooksIncludeAMissFromAnOccurrenceBeforeTheMonth() throws {
        insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-09-28")
        let bumped = Occurrence(list: .day, dayKey: "2026-10-07", title: "Post", state: .bumped)
        context.insert(bumped)
        context.insert(Occurrence(list: .day, dayKey: "2026-10-08", title: "Post", state: .done, bumpedFromID: bumped.id, bumpCount: 1))
        try context.save()

        let october = try ListService.dayLooks(
            from: "2026-10-01", through: "2026-10-20", todayKey: "2026-10-20",
            history: DayRulesHistory(), context: context, calendar: munich
        )
        let day = try XCTUnwrap(october.looks[.day])
        XCTAssertEqual(day["2026-10-04"]?.status, .missed)
        XCTAssertEqual(day["2026-10-04"]?.completion.value, 0)
        XCTAssertEqual(day["2026-10-07"]?.status, .complete, "bumped counts as done")
        XCTAssertTrue(day.keys.allSatisfy { $0 >= "2026-10-01" && $0 <= "2026-10-20" })
        XCTAssertEqual(october.bumpedDays, ["2026-10-07"])

        let later = try ListService.dayLooks(
            from: "2026-10-08", through: "2026-10-20", todayKey: "2026-10-20",
            history: DayRulesHistory(), context: context, calendar: munich
        )
        XCTAssertNil(later.looks[.day]?["2026-10-04"], "outside the range")
        XCTAssertTrue(later.bumpedDays.isEmpty)
    }

    func testPlannedDaysAreRowsAndDueRecurringItems() throws {
        insertItem("Gym", list: .day, rule: .weekly(on: [3]), start: "2026-10-12")
        context.insert(Occurrence(list: .evening, dayKey: "2026-10-16", title: "Pack"))
        try context.save()

        XCTAssertEqual(
            try ListService.plannedDayKeys(from: "2026-10-13", through: "2026-10-20", context: context, calendar: munich),
            ["2026-10-13", "2026-10-16", "2026-10-20"],
            "two Tuesdays and the one-off"
        )
    }

    /// Home on a future day lists the items due then; once the day's rows exist they are rows instead.
    func testDueItemsWithoutRowsOnAFutureDay() throws {
        let water = insertItem("Water", list: .morning, rule: .daily, start: "2026-10-12")
        insertItem("Gym", list: .morning, rule: .weekly(on: [3]), start: "2026-10-12")
        try context.save()

        XCTAssertEqual(try ListService.dueItemsWithoutRows(on: "2026-10-15", list: .morning, context: context, calendar: munich).map(\.id),
                       [water.id], "Thursday: not Gym's day")
        XCTAssertTrue(try ListService.dueItemsWithoutRows(on: "2026-10-15", list: .day, context: context, calendar: munich).isEmpty)

        try ListService.ensureOccurrences(on: "2026-10-15", context: context, now: TestCalendars.date("2026-10-15", 8), calendar: munich)
        XCTAssertTrue(try ListService.dueItemsWithoutRows(on: "2026-10-15", list: .morning, context: context, calendar: munich).isEmpty)
    }
}
