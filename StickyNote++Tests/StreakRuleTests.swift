import Foundation
import XCTest

/// Streak, completion and order rules from DECISIONS.md, on plain values.
final class StreakRuleTests: XCTestCase {
    private func row(_ day: String, _ state: OccurrenceState, completedAt: Date? = nil) -> FactRow {
        FactRow(dayKey: day, completedAt: completedAt, state: state)
    }

    private func streak(_ rows: [FactRow], through anchor: String, deadline: (String) -> Date? = { _ in nil }) -> HomeModel.StreakState {
        ListRules.streakState(through: anchor, occurrences: rows, deadline: deadline)
    }

    // MARK: - A day's count

    func testBumpedCountsAsDoneForTheDayItWasBumpedFrom() {
        let day = [row("2026-10-12", .done), row("2026-10-12", .bumped)]
        XCTAssertEqual(ListRules.dayStatus(day, deadline: nil), .complete)
        XCTAssertEqual(ListRules.completion(day), HomeModel.CompletionState(value: 1, isNeutral: false))
    }

    func testSkippedDropsOutOfTheCount() {
        let done = [row("2026-10-12", .done), row("2026-10-12", .skipped)]
        XCTAssertEqual(ListRules.dayStatus(done, deadline: nil), .complete)
        XCTAssertEqual(ListRules.completion(done).value, 1)

        let half = [row("2026-10-12", .done), row("2026-10-12", .open), row("2026-10-12", .skipped)]
        XCTAssertEqual(ListRules.completion(half).value, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ListRules.dayStatus(half, deadline: nil), .missed)
    }

    func testAllSkippedIsNeutral() {
        let day = [row("2026-10-12", .skipped), row("2026-10-12", .skipped)]
        XCTAssertEqual(ListRules.dayStatus(day, deadline: nil), .neutral)
        XCTAssertEqual(ListRules.completion(day), .neutral)
    }

    func testEmptyListIsNeutralAndNotAHundredPercent() {
        let empty: [FactRow] = []
        XCTAssertEqual(ListRules.dayStatus(empty, deadline: nil), .neutral)
        XCTAssertEqual(ListRules.completion(empty).value, 0)
        XCTAssertTrue(ListRules.completion(empty).isNeutral)
        XCTAssertFalse(ListRules.completion(empty).isComplete)
    }

    /// A weekly item bumped Mon → Tue → Wed and left open on Wednesday, its period end:
    /// Monday and Tuesday count as done, Wednesday is the miss.
    func testRepeatNotDoneByItsPeriodEndIsAMissOnThatDay() {
        let rows = [row("2026-10-12", .bumped), row("2026-10-13", .bumped), row("2026-10-14", .open)]
        XCTAssertEqual(ListRules.dayStatus([rows[2]], deadline: nil), .missed)
        XCTAssertEqual(streak(rows, through: "2026-10-15"), HomeModel.StreakState(count: 2, isFrozen: true))
    }

    // MARK: - Never miss twice

    func testOneMissFreezes() {
        let rows = [row("2026-10-10", .done), row("2026-10-11", .done), row("2026-10-12", .open)]
        XCTAssertEqual(streak(rows, through: "2026-10-13"), HomeModel.StreakState(count: 2, isFrozen: true))
    }

    func testCompleteDayAfterASingleMissCarriesOn() {
        let rows = [row("2026-10-10", .done), row("2026-10-11", .open), row("2026-10-12", .done)]
        XCTAssertEqual(streak(rows, through: "2026-10-13"), HomeModel.StreakState(count: 2, isFrozen: false))
    }

    func testTwoMissesInARowReset() {
        let rows = [row("2026-10-10", .done), row("2026-10-11", .open), row("2026-10-12", .open)]
        XCTAssertEqual(streak(rows, through: "2026-10-13"), HomeModel.StreakState(count: 0, isFrozen: false))
    }

    func testNeutralDaysAreSkippedWhenWalkingBack() {
        // Miss, then an all-skipped day and an empty day, then a miss: still two misses in a row.
        let reset = [
            row("2026-10-08", .done), row("2026-10-09", .open),
            row("2026-10-10", .skipped), row("2026-10-12", .open),
        ]
        XCTAssertEqual(streak(reset, through: "2026-10-13"), HomeModel.StreakState(count: 0, isFrozen: false))

        // Done, neutral, done: the neutral day neither breaks nor extends the streak.
        let carried = [row("2026-10-08", .done), row("2026-10-09", .skipped), row("2026-10-11", .done)]
        XCTAssertEqual(streak(carried, through: "2026-10-12"), HomeModel.StreakState(count: 2, isFrozen: false))
    }

    func testTodayOnlyAddsAndNeverBreaks() {
        let rows = [row("2026-10-11", .done), row("2026-10-12", .open)]
        XCTAssertEqual(streak(rows, through: "2026-10-12"), HomeModel.StreakState(count: 1, isFrozen: false))
        let done = [row("2026-10-11", .done), row("2026-10-12", .done)]
        XCTAssertEqual(streak(done, through: "2026-10-12"), HomeModel.StreakState(count: 2, isFrozen: false))
    }

    func testNoLookbackCap() {
        var rows: [FactRow] = []
        let math = DayMath(calendar: TestCalendars.munich)
        for offset in 0..<500 {
            rows.append(row(math.adding(days: offset, to: "2025-01-01"), .done))
        }
        let anchor = math.adding(days: 500, to: "2025-01-01")
        XCTAssertEqual(streak(rows, through: anchor).count, 500)
    }

    func testMorningDeadlineStillApplies() {
        let cutoff: (String) -> Date? = { TestCalendars.date($0, 9) }
        let late = [row("2026-10-12", .done, completedAt: TestCalendars.date("2026-10-12", 9, 30))]
        XCTAssertEqual(ListRules.dayStatus(late, deadline: cutoff("2026-10-12")), .missed)
        let early = [row("2026-10-12", .done, completedAt: TestCalendars.date("2026-10-12", 8, 59))]
        XCTAssertEqual(ListRules.dayStatus(early, deadline: cutoff("2026-10-12")), .complete)
        XCTAssertEqual(streak(early, through: "2026-10-13", deadline: cutoff).count, 1)
        XCTAssertEqual(streak(late, through: "2026-10-13", deadline: cutoff).count, 0)
    }

    // MARK: - Days nobody opened

    private func schedule(_ rule: RepeatRule = .daily, start: String, end: String? = nil) -> ListRules.ItemSchedule {
        ListRules.ItemSchedule(itemID: UUID(), rule: rule, startDayKey: start, endDayKey: end)
    }

    private func streak(_ rows: [FactRow], schedules: [ListRules.ItemSchedule], through anchor: String) -> HomeModel.StreakState {
        ListRules.streakState(through: anchor, occurrences: rows, schedules: schedules, calendar: TestCalendars.munich) { _ in nil }
    }

    func testUnopenedDayWithADailyItemDueIsAMiss() {
        let rows = [row("2026-10-10", .done)]
        let daily = [schedule(start: "2026-10-10")]
        XCTAssertEqual(streak(rows, schedules: daily, through: "2026-10-12"), HomeModel.StreakState(count: 1, isFrozen: true))
        XCTAssertEqual(streak(rows, through: "2026-10-12"), HomeModel.StreakState(count: 1, isFrozen: false), "without items it stays neutral")
    }

    /// Sunday 11.10 unopened: one item starts later, one ended the day before, and a Saturday-weekly
    /// item isn't scheduled on Sunday (its Saturday was opened).
    func testUnopenedDayWithNothingDueIsNeutral() {
        let rows = [row("2026-10-10", .done)]
        let schedules = [
            schedule(start: "2026-10-12"),
            schedule(start: "2026-10-10", end: "2026-10-11"),
            schedule(.weekly(on: [7]), start: "2026-10-10"),
        ]
        XCTAssertEqual(
            ListRules.unopenedMisses(schedules: schedules, openedDays: ["2026-10-10"], before: "2026-10-12", calendar: TestCalendars.munich),
            []
        )
        XCTAssertEqual(streak(rows, schedules: schedules, through: "2026-10-12"), HomeModel.StreakState(count: 1, isFrozen: false))
    }

    func testTwoUnopenedDaysInARowReset() {
        let rows = [row("2026-10-08", .done), row("2026-10-09", .done)]
        XCTAssertEqual(streak(rows, schedules: [schedule(start: "2026-10-08")], through: "2026-10-12"), HomeModel.StreakState(count: 0, isFrozen: false))
    }

    func testItemEndedBeforeAnUnopenedDayIsNotCountedAgainstIt() {
        let rows = [row("2026-10-09", .done), row("2026-10-10", .done)]
        let ended = [schedule(start: "2026-10-09", end: "2026-10-11")]
        XCTAssertEqual(streak(rows, schedules: ended, through: "2026-10-13"), HomeModel.StreakState(count: 2, isFrozen: false))
    }

    /// A Wednesday-weekly item due on unopened Wednesday 7.10 is a miss on its period end,
    /// Sunday 11.10, not on the Wednesday; the opened days in between still count.
    func testUnopenedWeeklyOccurrenceIsAMissOnItsPeriodEnd() {
        let weekly = [schedule(.weekly(on: [4]), start: "2026-10-07")]
        let opened: Set<String> = ["2026-10-08", "2026-10-09", "2026-10-10"]
        XCTAssertEqual(
            ListRules.unopenedMisses(schedules: weekly, openedDays: opened, before: "2026-10-13", calendar: TestCalendars.munich),
            ["2026-10-11"]
        )
        let rows = opened.map { row($0, .done) }
        XCTAssertEqual(streak(rows, schedules: weekly, through: "2026-10-13"), HomeModel.StreakState(count: 3, isFrozen: true))
    }

    func testUnopenedMissIsNotCountedBeforeItsPeriodEndHasPassed() {
        let weekly = [schedule(.weekly(on: [4]), start: "2026-10-07")]
        XCTAssertEqual(
            ListRules.unopenedMisses(schedules: weekly, openedDays: [], before: "2026-10-11", calendar: TestCalendars.munich),
            [], "Sunday is the anchor (today): still time"
        )
    }

    // MARK: - How a day looks (shared by streak, ring and calendar)

    private func looks(_ rows: [FactRow], schedules: [ListRules.ItemSchedule], before cutoff: String) -> [String: ListRules.DayLook] {
        ListRules.dayLooks(occurrences: rows, schedules: schedules, missesBefore: cutoff, calendar: TestCalendars.munich) { _ in nil }
    }

    private let missedNothingDone = ListRules.DayLook(status: .missed, completion: HomeModel.CompletionState(value: 0, isNeutral: false))

    /// Weekly Monday item left open on Monday: Monday isn't a miss (absent: neutral), Sunday is,
    /// and an opened Sunday with its own rows done no longer shows 100%.
    func testDayLooksWeeklyOpenMondayIsAMissOnSundayNotMonday() {
        let gym = UUID()
        let monday = FactRow(dayKey: "2026-10-12", itemID: gym, state: .open, scheduledDayKey: "2026-10-12", periodEndDayKey: "2026-10-18")
        let schedules = [ListRules.ItemSchedule(itemID: gym, rule: .weekly(on: [2]), startDayKey: "2026-10-12", endDayKey: nil)]

        let unopenedSunday = looks([monday], schedules: schedules, before: "2026-10-19")
        XCTAssertNil(unopenedSunday["2026-10-12"])
        XCTAssertEqual(unopenedSunday["2026-10-18"], missedNothingDone)

        let openedSunday = looks([monday, row("2026-10-18", .done)], schedules: schedules, before: "2026-10-19")
        XCTAssertEqual(openedSunday["2026-10-18"], ListRules.DayLook(status: .missed, completion: HomeModel.CompletionState(value: 0.5, isNeutral: false)))
        XCTAssertNil(looks([monday], schedules: schedules, before: "2026-10-18")["2026-10-18"], "no miss while Sunday is today")
    }

    func testDayLooksWeeklyCarriedAndDoneWednesdayIsNoMiss() {
        let gym = UUID()
        let wednesday = FactRow(dayKey: "2026-10-14", itemID: gym, completedAt: TestCalendars.date("2026-10-14", 18), state: .done,
                                scheduledDayKey: "2026-10-12", periodEndDayKey: "2026-10-18")
        let schedules = [ListRules.ItemSchedule(itemID: gym, rule: .weekly(on: [2]), startDayKey: "2026-10-12", endDayKey: nil)]
        let result = looks([wednesday], schedules: schedules, before: "2026-10-19")
        XCTAssertEqual(result, ["2026-10-14": ListRules.DayLook(status: .complete, completion: HomeModel.CompletionState(value: 1, isNeutral: false))])
    }

    func testDayLooksUnopenedDailyIsZeroPercent() {
        let water = UUID()
        let saturday = FactRow(dayKey: "2026-10-10", itemID: water, state: .done, scheduledDayKey: "2026-10-10", periodEndDayKey: "2026-10-10")
        let schedules = [ListRules.ItemSchedule(itemID: water, rule: .daily, startDayKey: "2026-10-10", endDayKey: nil)]
        let result = looks([saturday], schedules: schedules, before: "2026-10-12")
        XCTAssertEqual(result["2026-10-11"], missedNothingDone)
        XCTAssertEqual(result["2026-10-10"]?.status, .complete)
    }

    func testDayLooksAllSkippedAndEmptyAreNeutral() {
        XCTAssertTrue(looks([row("2026-10-10", .skipped), row("2026-10-10", .skipped)], schedules: [], before: "2026-10-12").isEmpty)
        XCTAssertTrue(looks([], schedules: [], before: "2026-10-12").isEmpty)
    }

    /// The streak is built from the same looks.
    func testStreakMatchesDayLooks() {
        let gym = UUID()
        let rows = [
            row("2026-10-11", .done),
            FactRow(dayKey: "2026-10-12", itemID: gym, state: .open, scheduledDayKey: "2026-10-12", periodEndDayKey: "2026-10-18"),
            row("2026-10-18", .done),
        ]
        let schedules = [ListRules.ItemSchedule(itemID: gym, rule: .weekly(on: [2]), startDayKey: "2026-10-12", endDayKey: nil)]
        let looks = looks(rows, schedules: schedules, before: "2026-10-19")
        XCTAssertEqual(ListRules.streakState(through: "2026-10-19", statuses: looks.mapValues(\.status)),
                       streak(rows, schedules: schedules, through: "2026-10-19"))
        XCTAssertEqual(streak(rows, schedules: schedules, through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: true))
    }

    /// Deleting an item never costs a streak day after the delete.
    func testEndedItemCostsNoMissOnOrAfterItsEnd() {
        let gym = UUID()
        let monday = FactRow(dayKey: "2026-10-12", itemID: gym, state: .open, scheduledDayKey: "2026-10-12", periodEndDayKey: "2026-10-18")
        let ended = [ListRules.ItemSchedule(itemID: gym, rule: .weekly(on: [2]), startDayKey: "2026-10-12", endDayKey: "2026-10-14")]
        XCTAssertTrue(looks([monday], schedules: ended, before: "2026-10-19").isEmpty)
        // Unopened Monday, item deleted on Wednesday: no miss on Sunday either.
        XCTAssertTrue(looks([], schedules: ended, before: "2026-10-19").isEmpty)
    }

    /// A weekly occurrence left open on its Monday can still be done that week: not a miss on Monday,
    /// a miss on Sunday (its period end) once Sunday has passed.
    func testOpenLessThanDailyOccurrenceIsAMissOnItsPeriodEndNotItsOwnDay() {
        let rows = [
            row("2026-10-11", .done),
            FactRow(dayKey: "2026-10-12", itemID: UUID(), state: .open, scheduledDayKey: "2026-10-12", periodEndDayKey: "2026-10-18"),
        ]
        XCTAssertEqual(streak(rows, through: "2026-10-14"), HomeModel.StreakState(count: 1, isFrozen: false))
        XCTAssertEqual(streak(rows, through: "2026-10-18"), HomeModel.StreakState(count: 1, isFrozen: false), "Sunday is today: still time")
        XCTAssertEqual(streak(rows, through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: true), "one miss, on Sunday")
    }

    // MARK: - Order and duplicates

    func testOrderIsItemsThenCantBumpOneOffsThenOthersByCreation() {
        let item = UUID()
        let rows = [
            FactRow(title: "late one-off", dayKey: "d", sortOrder: 1, createdAt: Date(timeIntervalSince1970: 20), state: .open, bumpLimit: .upToDays(3)),
            FactRow(title: "must", dayKey: "d", sortOrder: 5, state: .open, bumpLimit: .cantBump),
            FactRow(title: "item 2", dayKey: "d", itemID: item, sortOrder: 2, state: .open),
            FactRow(title: "early one-off", dayKey: "d", sortOrder: 0, createdAt: Date(timeIntervalSince1970: 10), state: .open, bumpLimit: .unlimited),
            FactRow(title: "item 1", dayKey: "d", itemID: item, sortOrder: 1, state: .done),
        ]
        XCTAssertEqual(ListRules.ordered(rows).map(\.title), ["item 1", "item 2", "must", "early one-off", "late one-off"])
    }

    func testPreferredDuplicateKeepsTheMostProgressedRow() {
        let rows = [
            FactRow(title: "open", dayKey: "d", createdAt: Date(timeIntervalSince1970: 1), state: .open),
            FactRow(title: "done", dayKey: "d", createdAt: Date(timeIntervalSince1970: 3), state: .done),
            FactRow(title: "skipped", dayKey: "d", createdAt: Date(timeIntervalSince1970: 2), state: .skipped),
        ]
        XCTAssertEqual(ListRules.preferredDuplicate(rows)?.title, "done")
        let opens = [
            FactRow(title: "second", dayKey: "d", createdAt: Date(timeIntervalSince1970: 2), state: .open),
            FactRow(title: "first", dayKey: "d", createdAt: Date(timeIntervalSince1970: 1), state: .open),
        ]
        XCTAssertEqual(ListRules.preferredDuplicate(opens)?.title, "first")
    }
}
