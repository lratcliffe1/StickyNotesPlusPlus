import Foundation
import SwiftData
import XCTest

/// Fix round 3 (DECISIONS.md, 2026-10-16): a forgotten tick on a past day, any list, after
/// retyping the title. The day and evening are stamped 23:59:59; a counted morning row one second
/// before that day's own deadline; a morning bonus row 23:59:59. Munich; 15.10.2026 is a Thursday,
/// 25.10.2026 the day the clocks go back.
final class BackfillRuleTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let yesterday = "2026-10-15"
    private let today = "2026-10-16"

    private let nineOClock = DayRules(morningEnd: .setTime, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)
    private let doneOrSkipped = DayRules(morningEnd: .doneOrSkipped, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)

    private func stamp(_ list: ListKind, on key: String? = nil, rules: DayRules? = nil, isBonus: Bool = false) -> Date? {
        BackfillRules.stamp(list: list, dayKey: key ?? yesterday, rules: rules ?? nineOClock, isBonus: isBonus, calendar: munich)
    }

    private func endOfDay(_ key: String) -> Date {
        TestCalendars.date(key, 23, 59).addingTimeInterval(59)
    }

    // MARK: - The stamp

    func testEveningAndDayAreStampedAtTheEndOfTheirDay() {
        XCTAssertEqual(stamp(.evening), endOfDay(yesterday))
        XCTAssertEqual(stamp(.day), endOfDay(yesterday))
    }

    func testMorningIsStampedJustBeforeThatDaysSetTime() {
        XCTAssertEqual(stamp(.morning), TestCalendars.date(yesterday, 8, 59).addingTimeInterval(59))
    }

    func testMorningWithNoSetTimeIsStampedJustBeforeNoon() {
        XCTAssertEqual(stamp(.morning, rules: doneOrSkipped), TestCalendars.date(yesterday, 11, 59).addingTimeInterval(59))
    }

    func testMorningBonusRowIsStampedAtTheEndOfTheDay() {
        XCTAssertEqual(stamp(.morning, isBonus: true), endOfDay(yesterday))
    }

    /// The clocks go back at 03:00 on 25.10.2026: a 25-hour day, still stamped on itself.
    func testTheDayTheClocksChangeKeepsItsWallClockTimes() throws {
        let dst = "2026-10-25"
        let evening = try XCTUnwrap(stamp(.evening, on: dst))
        let morning = try XCTUnwrap(stamp(.morning, on: dst))
        XCTAssertEqual(HomeModel.dayKey(for: evening, calendar: munich), dst)
        XCTAssertEqual(munich.dateComponents([.hour, .minute, .second], from: evening), DateComponents(hour: 23, minute: 59, second: 59))
        XCTAssertEqual(munich.dateComponents([.hour, .minute, .second], from: morning), DateComponents(hour: 8, minute: 59, second: 59))
    }

    /// The clocks go forward at 02:00 on 29.3.2026: a 23-hour day, still stamped on itself.
    func testTheSpringClockChangeKeepsItsWallClockTimes() throws {
        let dst = "2026-03-29"
        let evening = try XCTUnwrap(stamp(.evening, on: dst))
        let morning = try XCTUnwrap(stamp(.morning, on: dst))
        XCTAssertEqual(HomeModel.dayKey(for: evening, calendar: munich), dst)
        XCTAssertEqual(munich.dateComponents([.hour, .minute, .second], from: evening), DateComponents(hour: 23, minute: 59, second: 59))
        XCTAssertEqual(munich.dateComponents([.hour, .minute, .second], from: morning), DateComponents(hour: 8, minute: 59, second: 59))
    }

    /// A 00:00 set time can't be beaten by a second: the stamp stays on its day, at the deadline.
    func testAMidnightDeadlineStampsTheStartOfTheDay() throws {
        let midnight = DayRules(morningEnd: .setTime, morningEndMinutes: 0, eveningStartMinutes: nil)
        let morning = try XCTUnwrap(stamp(.morning, rules: midnight))
        XCTAssertEqual(morning, TestCalendars.date(yesterday))
        XCTAssertEqual(ListRules.dayStatus([FactRow(dayKey: yesterday, completedAt: morning, state: .done)], deadline: TestCalendars.date(yesterday)), .complete)
    }

    func testAKeyThatIsNotADateHasNoStamp() {
        XCTAssertNil(stamp(.evening, on: "not-a-day"))
    }

    // MARK: - Confirming

    func testConfirmingNeedsTheTitleExactly() {
        XCTAssertTrue(BackfillRules.confirms("Read in bed", title: "Read in bed"))
        XCTAssertTrue(BackfillRules.confirms("Read in bed ", title: "Read in bed"), "the keyboard's trailing space")
        XCTAssertFalse(BackfillRules.confirms("read in bed", title: "Read in bed"))
        XCTAssertFalse(BackfillRules.confirms("Read in", title: "Read in bed"))
        XCTAssertFalse(BackfillRules.confirms("", title: "Read in bed"))
    }

    /// The keyboard's smart punctuation: a curly apostrophe or dash matches a straight one.
    func testConfirmingTreatsCurlyAndStraightPunctuationAlike() {
        XCTAssertTrue(BackfillRules.confirms("Lay out tomorrow\u{2019}s clothes", title: "Lay out tomorrow's clothes"))
        XCTAssertTrue(BackfillRules.confirms("Lay out tomorrow's clothes", title: "Lay out tomorrow\u{2019}s clothes"))
        XCTAssertTrue(BackfillRules.confirms("Call \u{201C}Mum\u{201D} \u{2014} 10 min", title: "Call \"Mum\" - 10 min"))
    }

    // MARK: - What it mends

    /// Liam's case: the evening done two nights running, then one item ticked and two forgotten.
    /// Back-filled this morning, yesterday is complete and the streak is whole again.
    func testBackFilledEveningMendsTheStreak() throws {
        let earlier = ["2026-10-13", "2026-10-14"].flatMap { key in
            (0..<3).map { _ in FactRow(dayKey: key, completedAt: TestCalendars.date(key, 21, 40), state: .done) }
        }
        let tidy = FactRow(dayKey: yesterday, completedAt: TestCalendars.date(yesterday, 21, 40), state: .done)
        let todayRow = FactRow(dayKey: today, state: .open)
        let forgotten = [FactRow(dayKey: yesterday, state: .open), FactRow(dayKey: yesterday, state: .open)]

        let before = ListRules.streakState(through: today, occurrences: earlier + [tidy] + forgotten + [todayRow], deadline: { _ in nil })
        XCTAssertEqual(before, HomeModel.StreakState(count: 2, isFrozen: true))

        let at = try XCTUnwrap(stamp(.evening))
        let ticked = forgotten.map { row -> FactRow in
            var row = row
            row.state = .done
            row.completedAt = at
            return row
        }
        let after = ListRules.streakState(through: today, occurrences: earlier + [tidy] + ticked + [todayRow], deadline: { _ in nil })
        XCTAssertEqual(after, HomeModel.StreakState(count: 3, isFrozen: false))
    }

    func testBackFilledMorningCountsAsOnTime() throws {
        let at = try XCTUnwrap(stamp(.morning))
        let rows = [
            FactRow(dayKey: yesterday, completedAt: TestCalendars.date(yesterday, 7, 30), state: .done),
            FactRow(dayKey: yesterday, completedAt: at, state: .done),
        ]
        XCTAssertEqual(ListRules.dayStatus(rows, deadline: TestCalendars.date(yesterday, 9)), .complete)
    }

    /// Back-filling fills gaps; it never rewrites a real tick. A row ticked at 10:15 that day keeps
    /// its time, so the morning stays a miss.
    func testAMorningWithARealLateTickStaysMissed() throws {
        let at = try XCTUnwrap(stamp(.morning))
        let rows = [
            FactRow(dayKey: yesterday, completedAt: TestCalendars.date(yesterday, 10, 15), state: .done),
            FactRow(dayKey: yesterday, completedAt: at, state: .done),
        ]
        XCTAssertEqual(ListRules.dayStatus(rows, deadline: TestCalendars.date(yesterday, 9)), .missed)
    }

    // MARK: - The write (`ListService.completePast`, as Home calls it)

    /// Yesterday kept a 07:30 set time (stored), though the old 09:00 is the fallback.
    private let history = DayRulesHistory(stored: [
        "2026-10-15": DayRules(morningEnd: .setTime, morningEndMinutes: 7 * 60 + 30, eveningStartMinutes: 21 * 60),
    ])

    private func routineRow(_ title: String, list: ListKind, createdAt: Date, start: String? = nil, context: ModelContext) -> Occurrence {
        let item = Item(list: list, title: title, sortOrder: 0, repeatRule: .daily, startDayKey: start ?? "2026-10-01", createdAt: createdAt)
        context.insert(item)
        let row = ListService.makeOccurrence(for: item, scheduledOn: yesterday, on: yesterday, now: TestCalendars.date(yesterday, 6), calendar: munich)
        context.insert(row)
        return row
    }

    private func completePast(_ row: Occurrence, context: ModelContext) throws -> Bool {
        try ListService.completePast(row, todayKey: today, history: history, calendar: munich, context: context)
    }

    func testAPastEveningRowIsTickedAtTheEndOfItsDay() throws {
        let context = try StoreTestSupport.makeContext()
        let row = routineRow("Read in bed", list: .evening, createdAt: TestCalendars.addedLongBefore(), context: context)
        try context.save()

        XCTAssertTrue(try completePast(row, context: context))
        XCTAssertEqual(row.state, .done)
        XCTAssertEqual(row.completedAt, endOfDay(yesterday))
    }

    /// The day's own stored rules, not today's or the fallback: 07:29:59.
    func testAPastMorningRowIsTickedJustBeforeThatDaysStoredCutoff() throws {
        let context = try StoreTestSupport.makeContext()
        let row = routineRow("Floss", list: .morning, createdAt: TestCalendars.addedLongBefore(), context: context)
        try context.save()

        XCTAssertTrue(try completePast(row, context: context))
        XCTAssertEqual(row.completedAt, TestCalendars.date(yesterday, 7, 29).addingTimeInterval(59))
    }

    /// An item first added yesterday at 10:00, after its cutoff: a bonus row, ticked at 23:59:59.
    func testAPastBonusRowIsTickedAtTheEndOfItsDay() throws {
        let context = try StoreTestSupport.makeContext()
        let row = routineRow("Vitamins", list: .morning, createdAt: TestCalendars.date(yesterday, 10), start: yesterday, context: context)
        try context.save()

        XCTAssertTrue(try completePast(row, context: context))
        XCTAssertEqual(row.completedAt, endOfDay(yesterday))
    }

    func testOnlyOpenRowsBeforeTodayCanBeTicked() throws {
        let context = try StoreTestSupport.makeContext()
        let skipped = Occurrence(list: .evening, dayKey: yesterday, title: "Skipped", state: .skipped)
        let todays = Occurrence(list: .evening, dayKey: today, title: "Today")
        let done = Occurrence(list: .evening, dayKey: yesterday, title: "Done", state: .done, completedAt: TestCalendars.date(yesterday, 21))
        for row in [skipped, todays, done] {
            context.insert(row)
        }
        try context.save()

        XCTAssertFalse(try completePast(skipped, context: context))
        XCTAssertFalse(try completePast(todays, context: context))
        XCTAssertFalse(try completePast(done, context: context))
        XCTAssertEqual(skipped.state, .skipped)
        XCTAssertEqual(todays.state, .open)
        XCTAssertEqual(done.completedAt, TestCalendars.date(yesterday, 21), "a real tick is never retimed")
    }
}
