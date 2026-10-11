import Foundation
import XCTest

/// The calendar's pure rules (step 4): its months, the grid, the lists in use, planned days, how far
/// back a range must fetch, and the spoken day.
final class CalendarRulesTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let sundayFirst = TestCalendars.sundayFirst

    private func month(_ year: Int, _ month: Int) -> CalendarRules.Month {
        CalendarRules.Month(year: year, month: month)
    }

    // MARK: - The months shown

    func testRangeStartsAtTheFirstEntrysMonthWhenThatIsEarlier() {
        let months = CalendarRules.months(firstEntryDayKey: "2026-08-20", todayKey: "2026-10-11")
        XCTAssertEqual(months.first, month(2026, 8))
        XCTAssertEqual(months.last, month(2027, 10), "through the next 12 months")
        XCTAssertEqual(months.count, 15)
    }

    func testRangeStartsAtTheCurrentMonthWhenTheFirstEntryIsLater() {
        // A one-off added ahead is the only entry.
        let months = CalendarRules.months(firstEntryDayKey: "2026-12-01", todayKey: "2026-10-11")
        XCTAssertEqual(months.first, month(2026, 10))
        XCTAssertEqual(months.count, 13)
    }

    func testRangeWithNoEntriesIsTheCurrentMonthAndTheNextTwelve() {
        let months = CalendarRules.months(firstEntryDayKey: nil, todayKey: "2026-10-11")
        XCTAssertEqual(months.first, month(2026, 10))
        XCTAssertEqual(months.last, month(2027, 10))
    }

    func testRangeCrossesYearBoundariesInOrder() {
        let months = CalendarRules.months(firstEntryDayKey: "2025-11-30", todayKey: "2026-01-05")
        XCTAssertEqual(months.prefix(3).map(\.id), ["2025-11", "2025-12", "2026-01"])
        XCTAssertEqual(months.last, month(2027, 1))
        XCTAssertEqual(months.count, 15)
        XCTAssertEqual(month(2026, 12).shifted(by: 1), month(2027, 1))
        XCTAssertEqual(month(2026, 1).shifted(by: -1), month(2025, 12))
    }

    // MARK: - The grid

    /// 1 October 2026 is a Thursday.
    func testGridOffsetsFollowTheFirstWeekday() {
        XCTAssertEqual(CalendarRules.leadingBlanks(for: month(2026, 10), calendar: munich), 3, "Mon, Tue, Wed")
        XCTAssertEqual(CalendarRules.leadingBlanks(for: month(2026, 10), calendar: sundayFirst), 4, "Sun … Wed")
        XCTAssertEqual(CalendarRules.weeks(for: month(2026, 10), calendar: munich)[0][3], "2026-10-01")
        XCTAssertEqual(CalendarRules.weeks(for: month(2026, 10), calendar: sundayFirst)[0][4], "2026-10-01")
    }

    /// 1 November 2026 and 1 February 2026 are Sundays.
    func testAMonthStartingOnSunday() {
        let november = month(2026, 11)
        XCTAssertEqual(CalendarRules.leadingBlanks(for: november, calendar: munich), 6)
        let mondayFirst = CalendarRules.weeks(for: november, calendar: munich)
        XCTAssertEqual(mondayFirst[0], [nil, nil, nil, nil, nil, nil, "2026-11-01"])
        XCTAssertEqual(mondayFirst.count, 6)
        XCTAssertEqual(mondayFirst[1][0], "2026-11-02", "the next row starts on Monday")

        XCTAssertEqual(CalendarRules.leadingBlanks(for: november, calendar: sundayFirst), 0)
        XCTAssertEqual(CalendarRules.weeks(for: november, calendar: sundayFirst)[0][0], "2026-11-01")
        XCTAssertEqual(CalendarRules.weeks(for: november, calendar: sundayFirst).count, 5)

        XCTAssertEqual(CalendarRules.weeks(for: month(2026, 2), calendar: sundayFirst).count, 4, "28 days from a Sunday")
        XCTAssertEqual(CalendarRules.weeks(for: month(2026, 2), calendar: munich).count, 5)
    }

    /// The clocks change on 29 March and 25 October 2026 in Munich: every day appears once, in order,
    /// in rows of seven, and each falls in its weekday's column.
    func testGridIsDSTSafe() {
        for (target, days) in [(month(2026, 3), 31), (month(2026, 10), 31)] {
            let weeks = CalendarRules.weeks(for: target, calendar: munich)
            XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
            let keys = weeks.flatMap { $0 }.compactMap { $0 }
            XCTAssertEqual(keys, (1...days).map { DayMath.key(year: target.year, month: target.month, day: $0) })
        }
        let march = CalendarRules.weeks(for: month(2026, 3), calendar: munich)
        XCTAssertTrue(march.contains { $0[6] == "2026-03-29" }, "a Sunday, in the last column")
        let october = CalendarRules.weeks(for: month(2026, 10), calendar: munich)
        XCTAssertTrue(october.contains { $0[6] == "2026-10-25" })
        XCTAssertTrue(october.contains { $0[0] == "2026-10-26" }, "the Monday after the change starts a row")
    }

    func testWeekdaySymbolsStartOnTheFirstWeekday() {
        let symbols = munich.veryShortStandaloneWeekdaySymbols
        let mondayFirst = CalendarRules.weekdaySymbols(calendar: munich)
        XCTAssertEqual(mondayFirst.count, 7)
        XCTAssertEqual(mondayFirst.first, symbols[1], "Monday")
        XCTAssertEqual(mondayFirst.last, symbols[0], "Sunday last")
        XCTAssertEqual(CalendarRules.weekdaySymbols(calendar: sundayFirst), sundayFirst.veryShortStandaloneWeekdaySymbols)
    }

    // MARK: - Lists in use

    func testListsInUseFromEachListsFirstDay() {
        let firstUse: [ListKind: String] = [.evening: "2026-10-09", .morning: "2026-09-29", .day: "2026-10-03"]
        XCTAssertEqual(CalendarRules.listsInUse(on: "2026-09-01", firstUse: firstUse), [])
        XCTAssertEqual(CalendarRules.listsInUse(on: "2026-09-30", firstUse: firstUse), [.morning])
        XCTAssertEqual(CalendarRules.listsInUse(on: "2026-10-03", firstUse: firstUse), [.morning, .day])
        XCTAssertEqual(CalendarRules.listsInUse(on: "2026-10-11", firstUse: firstUse), [.morning, .day, .evening])
        XCTAssertEqual(CalendarRules.firstEntryDayKey(firstUse: firstUse), "2026-09-29")
        XCTAssertNil(CalendarRules.firstEntryDayKey(firstUse: [:]))
    }

    func testSegmentsCarryEachListsLookAndNeutralIsNil() {
        let done = ListRules.DayLook(status: .complete, completion: .init(value: 1, isNeutral: false))
        let segments = CalendarRules.segments(
            on: "2026-10-12",
            firstUse: [.morning: "2026-10-01", .day: "2026-10-01"],
            looks: [.morning: ["2026-10-12": done], .evening: ["2026-10-12": done]]
        )
        XCTAssertEqual(segments, [DaySegment(list: .morning, look: done), DaySegment(list: .day, look: nil)],
                       "evening isn't in use yet, so its look isn't drawn")
    }

    // MARK: - Planned days

    func testAFutureOneOffMakesItsDayPlanned() {
        let planned = CalendarRules.plannedDays(
            rowDayKeys: ["2026-10-14", "2026-11-02"], schedules: [], from: "2026-10-12", through: "2026-10-31", calendar: munich
        )
        XCTAssertEqual(planned, ["2026-10-14"])
    }

    func testARecurringItemMakesItsDueDaysPlannedWhileItExists() {
        let mondays = ListRules.ItemSchedule(itemID: UUID(), rule: .weekly(on: [2]), startDayKey: "2026-10-05", endDayKey: "2026-10-20")
        let fromNovember = ListRules.ItemSchedule(itemID: UUID(), rule: .daily, startDayKey: "2026-11-01", endDayKey: nil)
        let planned = CalendarRules.plannedDays(
            rowDayKeys: [], schedules: [mondays, fromNovember], from: "2026-10-12", through: "2026-10-31", calendar: munich
        )
        XCTAssertEqual(planned, ["2026-10-12", "2026-10-19"], "not after it ended, nor before the other starts")
        XCTAssertTrue(CalendarRules.plannedDays(rowDayKeys: [], schedules: [], from: "2026-10-31", through: "2026-10-01", calendar: munich).isEmpty)
    }

    // MARK: - What a range must fetch

    func testFetchStartLooksBackTheLongestRepeatPeriod() {
        func schedule(_ rule: RepeatRule) -> ListRules.ItemSchedule {
            ListRules.ItemSchedule(itemID: UUID(), rule: rule, startDayKey: "2026-01-01", endDayKey: nil)
        }
        XCTAssertEqual(CalendarRules.fetchStart(for: "2026-10-01", schedules: [], calendar: munich), "2026-10-01")
        XCTAssertEqual(CalendarRules.fetchStart(for: "2026-10-01", schedules: [schedule(.daily)], calendar: munich), "2026-10-01",
                       "only daily items: exactly the month")
        XCTAssertEqual(CalendarRules.fetchStart(for: "2026-10-01", schedules: [schedule(.daily), schedule(.weekly(on: [2]))], calendar: munich),
                       "2026-09-25")
        XCTAssertEqual(CalendarRules.fetchStart(for: "2026-10-01", schedules: [schedule(.monthly), schedule(.weekdays)], calendar: munich),
                       "2026-09-01")
        XCTAssertEqual(CalendarRules.fetchStart(for: "2026-03-01", schedules: [schedule(.yearly)], calendar: munich), "2025-03-01")
    }

    /// No occurrence's period end is further from its day than `longestPeriodDays`.
    func testLongestPeriodBoundsEveryRule() {
        let math = DayMath(calendar: munich)
        let rules: [RepeatRule] = [
            .daily, .weekdays, .weekends, .weekly(on: [2, 5]), .weekly(on: []), .everyTwoWeeks, .monthly, .yearly,
            .everyNDays(3), .everyNWeeks(3, on: [4]), .everyNMonths(2),
        ]
        for rule in rules {
            for start in ["2026-01-31", "2026-02-01", "2026-07-15"] {
                var day = start
                while day < "2027-12-31" {
                    if rule.occurs(on: day, startDayKey: start, math: math) {
                        let end = rule.periodEnd(for: day, startDayKey: start, calendar: munich)
                        XCTAssertLessThanOrEqual(math.daysBetween(day, end), rule.longestPeriodDays, "\(rule) from \(start), on \(day)")
                    }
                    day = math.adding(days: 1, to: day)
                }
            }
        }
    }

    /// A month's looks from its own rows (fetched from `fetchStart`) equal the whole history's, with
    /// weekly and monthly items deferred across the month start, days nobody opened, and late rows.
    func testWindowedDayLooksMatchTheWholeHistory() {
        let math = DayMath(calendar: munich)
        let daily = ListRules.ItemSchedule(itemID: UUID(), rule: .daily, startDayKey: "2026-08-01", endDayKey: nil)
        let weekly = ListRules.ItemSchedule(itemID: UUID(), rule: .weekly(on: [2]), startDayKey: "2026-08-03", endDayKey: nil)
        let monthly = ListRules.ItemSchedule(itemID: UUID(), rule: .monthly, startDayKey: "2026-08-15", endDayKey: nil)
        let schedules = [daily, weekly, monthly]
        let today = "2026-10-20"

        var rows: [FactRow] = []
        var day = "2026-08-01"
        while day <= today {
            let dayOfMonth = DayMath.parse(day)?.day ?? 1
            let opened = dayOfMonth % 5 != 0
            if opened {
                rows.append(FactRow(dayKey: day, itemID: daily.itemID, state: dayOfMonth % 7 == 0 ? .open : .done,
                                    scheduledDayKey: day, periodEndDayKey: day))
                for schedule in [weekly, monthly] where schedule.rule.occurs(on: day, startDayKey: schedule.startDayKey, math: math) {
                    rows.append(FactRow(dayKey: day, itemID: schedule.itemID, state: dayOfMonth % 2 == 0 ? .open : .done,
                                        scheduledDayKey: day,
                                        periodEndDayKey: schedule.rule.periodEnd(for: day, startDayKey: schedule.startDayKey, calendar: munich)))
                }
                if dayOfMonth % 3 == 0 {
                    rows.append(FactRow(dayKey: day, state: .bumped))
                }
            }
            day = math.adding(days: 1, to: day)
        }
        // Nobody opened Monday 10 August: its weekly occurrence got a row on Tuesday, left open.
        rows.append(FactRow(dayKey: "2026-08-11", itemID: weekly.itemID, state: .open,
                            scheduledDayKey: "2026-08-10", periodEndDayKey: "2026-08-16"))

        let whole = ListRules.dayLooks(occurrences: rows, schedules: schedules, missesBefore: today, calendar: munich) { _ in nil }
        for (start, end) in [("2026-09-01", "2026-09-30"), ("2026-10-01", today), ("2026-10-14", today)] {
            let fetchStart = CalendarRules.fetchStart(for: start, schedules: schedules, calendar: munich)
            let fetched = rows.filter { $0.dayKey >= fetchStart && $0.dayKey <= end }
            let windowed = ListRules.dayLooks(
                occurrences: fetched, schedules: schedules, missesBefore: today, calendar: munich, window: fetchStart...end
            ) { _ in nil }.filter { $0.key >= start }
            XCTAssertEqual(windowed, whole.filter { $0.key >= start && $0.key <= end }, "\(start)…\(end)")
            XCTAssertFalse(windowed.isEmpty)
        }
        XCTAssertNotNil(whole["2026-10-04"], "a miss from a September occurrence lands in October")
    }

    // MARK: - Accessibility

    func testAccessibilityLabelSaysEachListsStateInWords() {
        var british = munich
        british.locale = Locale(identifier: "en_GB")
        let done = ListRules.DayLook(status: .complete, completion: .init(value: 1, isNeutral: false))
        let missed = ListRules.DayLook(status: .missed, completion: .init(value: 0.5, isNeutral: false))
        let segments = [DaySegment(list: .morning, look: done), DaySegment(list: .day, look: missed)]

        XCTAssertEqual(
            CalendarRules.accessibilityLabel(dayKey: "2026-10-12", todayKey: "2026-10-14", segments: segments,
                                             hasBump: true, isPlanned: false, calendar: british),
            "Monday 12 October: morning done, day missed, bumped"
        )
        XCTAssertEqual(
            CalendarRules.accessibilityLabel(dayKey: "2026-10-14", todayKey: "2026-10-14",
                                             segments: [DaySegment(list: .day, look: missed), DaySegment(list: .evening, look: nil)],
                                             hasBump: false, isPlanned: false, calendar: british),
            "Today, Wednesday 14 October: day 50 percent done so far, evening nothing due"
        )
        XCTAssertEqual(
            CalendarRules.accessibilityLabel(dayKey: "2026-10-15", todayKey: "2026-10-14", segments: [],
                                             hasBump: false, isPlanned: true, calendar: british),
            "Thursday 15 October: something planned"
        )
    }
}
