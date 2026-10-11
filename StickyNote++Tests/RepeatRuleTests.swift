import Foundation
import XCTest

/// Apple Reminders-style repeats and their period ends, on a Monday-first Munich calendar.
/// 12.10.2026 is a Monday.
final class RepeatRuleTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let monday = 2, wednesday = 4, thursday = 5

    private func occurs(_ rule: RepeatRule, _ day: String, start: String) -> Bool {
        rule.occurs(on: day, startDayKey: start, calendar: munich)
    }

    private func periodEnd(_ rule: RepeatRule, _ day: String, start: String, calendar: Calendar? = nil) -> String {
        rule.periodEnd(for: day, startDayKey: start, calendar: calendar ?? munich)
    }

    // MARK: - Occurs

    func testDailyOccursEveryDayFromStart() {
        XCTAssertFalse(occurs(.daily, "2026-10-13", start: "2026-10-14"))
        XCTAssertTrue(occurs(.daily, "2026-10-14", start: "2026-10-14"))
        XCTAssertTrue(occurs(.daily, "2026-10-15", start: "2026-10-14"))
        XCTAssertTrue(occurs(.daily, "2027-03-01", start: "2026-10-14"))
    }

    func testWeekdaysFollowTheCalendarsWeekend() {
        for day in ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"] {
            XCTAssertTrue(occurs(.weekdays, day, start: "2026-10-12"), day)
        }
        XCTAssertFalse(occurs(.weekdays, "2026-10-17", start: "2026-10-12"))
        XCTAssertFalse(occurs(.weekdays, "2026-10-18", start: "2026-10-12"))
    }

    func testWeekendsFollowTheCalendarsWeekend() {
        XCTAssertTrue(occurs(.weekends, "2026-10-17", start: "2026-10-12"))
        XCTAssertTrue(occurs(.weekends, "2026-10-18", start: "2026-10-12"))
        XCTAssertFalse(occurs(.weekends, "2026-10-16", start: "2026-10-12"))
        XCTAssertFalse(occurs(.weekends, "2026-10-19", start: "2026-10-12"))
    }

    func testWeeklyOnChosenWeekdays() {
        let rule = RepeatRule.weekly(on: [monday, thursday])
        XCTAssertTrue(occurs(rule, "2026-10-12", start: "2026-10-12"))
        XCTAssertFalse(occurs(rule, "2026-10-14", start: "2026-10-12"))
        XCTAssertTrue(occurs(rule, "2026-10-15", start: "2026-10-12"))
        XCTAssertTrue(occurs(rule, "2026-10-19", start: "2026-10-12"))
    }

    func testWeeklyWithNoChosenDaysUsesTheStartWeekday() {
        let rule = RepeatRule.weekly(on: [])
        XCTAssertTrue(occurs(rule, "2026-10-21", start: "2026-10-14"))
        XCTAssertFalse(occurs(rule, "2026-10-20", start: "2026-10-14"))
    }

    func testEveryTwoWeeksAnchorsOnTheStartWeek() {
        let rule = RepeatRule.everyTwoWeeks
        XCTAssertFalse(occurs(rule, "2026-10-07", start: "2026-10-14"))
        XCTAssertTrue(occurs(rule, "2026-10-14", start: "2026-10-14"))
        XCTAssertFalse(occurs(rule, "2026-10-21", start: "2026-10-14"))
        XCTAssertTrue(occurs(rule, "2026-10-28", start: "2026-10-14"))
        XCTAssertFalse(occurs(rule, "2026-11-04", start: "2026-10-14"))
        XCTAssertTrue(occurs(rule, "2026-11-11", start: "2026-10-14"))
    }

    /// Started on a Wednesday: that whole Monday-first week is week 0, so Monday of week 2 counts.
    func testEveryNWeeksCountsCalendarWeeksFromTheStartWeek() {
        let rule = RepeatRule.everyNWeeks(2, on: [monday, wednesday])
        XCTAssertFalse(occurs(rule, "2026-10-12", start: "2026-10-14"), "before the start day")
        XCTAssertTrue(occurs(rule, "2026-10-14", start: "2026-10-14"))
        XCTAssertFalse(occurs(rule, "2026-10-19", start: "2026-10-14"))
        XCTAssertTrue(occurs(rule, "2026-10-26", start: "2026-10-14"))
        XCTAssertTrue(occurs(rule, "2026-10-28", start: "2026-10-14"))
    }

    func testMonthlyOnThe31stFallsOnTheLastDayOfShorterMonths() {
        let start = "2026-01-31"
        XCTAssertTrue(occurs(.monthly, "2026-02-28", start: start))
        XCTAssertFalse(occurs(.monthly, "2026-02-27", start: start))
        XCTAssertTrue(occurs(.monthly, "2026-03-31", start: start))
        XCTAssertFalse(occurs(.monthly, "2026-03-30", start: start))
        XCTAssertTrue(occurs(.monthly, "2026-04-30", start: start))
        XCTAssertTrue(occurs(.monthly, "2028-02-29", start: start))
        XCTAssertFalse(occurs(.monthly, "2028-02-28", start: start))
    }

    func testMonthlyOnAnOrdinaryDay() {
        XCTAssertTrue(occurs(.monthly, "2026-11-05", start: "2026-10-05"))
        XCTAssertFalse(occurs(.monthly, "2026-11-06", start: "2026-10-05"))
    }

    func testYearlyOn29FebruaryFallsOn28FebruaryInOtherYears() {
        let start = "2024-02-29"
        XCTAssertTrue(occurs(.yearly, "2025-02-28", start: start))
        XCTAssertFalse(occurs(.yearly, "2025-03-01", start: start))
        XCTAssertTrue(occurs(.yearly, "2026-02-28", start: start))
        XCTAssertTrue(occurs(.yearly, "2028-02-29", start: start))
        XCTAssertFalse(occurs(.yearly, "2028-02-28", start: start))
    }

    func testYearlyOnAnOrdinaryDay() {
        XCTAssertTrue(occurs(.yearly, "2027-10-14", start: "2026-10-14"))
        XCTAssertFalse(occurs(.yearly, "2027-10-15", start: "2026-10-14"))
        XCTAssertFalse(occurs(.yearly, "2026-11-14", start: "2026-10-14"))
    }

    func testEveryNDays() {
        let rule = RepeatRule.everyNDays(3)
        XCTAssertTrue(occurs(rule, "2026-10-12", start: "2026-10-12"))
        XCTAssertFalse(occurs(rule, "2026-10-14", start: "2026-10-12"))
        XCTAssertTrue(occurs(rule, "2026-10-15", start: "2026-10-12"))
        XCTAssertTrue(occurs(rule, "2026-10-18", start: "2026-10-12"))
    }

    /// Across the 25.10.2026 clock change: still whole days.
    func testEveryNDaysAcrossDaylightSavingChange() {
        let rule = RepeatRule.everyNDays(2)
        XCTAssertTrue(occurs(rule, "2026-10-26", start: "2026-10-24"))
        XCTAssertFalse(occurs(rule, "2026-10-25", start: "2026-10-24"))
    }

    func testEveryNMonthsOnThe31st() {
        let rule = RepeatRule.everyNMonths(3)
        XCTAssertTrue(occurs(rule, "2026-04-30", start: "2026-01-31"))
        XCTAssertFalse(occurs(rule, "2026-02-28", start: "2026-01-31"))
        XCTAssertTrue(occurs(rule, "2026-07-31", start: "2026-01-31"))
    }

    func testNoRuleOccursBeforeItsStartDay() {
        let rules: [RepeatRule] = [
            .daily, .weekdays, .weekends, .weekly(on: []), .everyTwoWeeks, .monthly, .yearly,
            .everyNDays(1), .everyNWeeks(1, on: [monday]), .everyNMonths(1),
        ]
        for rule in rules {
            XCTAssertFalse(occurs(rule, "2025-10-12", start: "2026-10-12"), "\(rule.kind)")
        }
    }

    func testStoredPartsRoundTrip() {
        let rule = RepeatRule.everyNWeeks(3, on: [monday, thursday])
        let rebuilt = RepeatRule(kindRaw: rule.kind.rawValue, interval: rule.interval, weekdayMask: rule.weekdayMask)
        XCTAssertEqual(rebuilt, rule)
        XCTAssertEqual(RepeatRule(kindRaw: "nonsense", interval: 0, weekdayMask: 0), .daily)
    }

    // MARK: - Period end

    func testDailyPeriodEndsTheSameDay() {
        XCTAssertEqual(periodEnd(.daily, "2026-10-14", start: "2026-10-01"), "2026-10-14")
    }

    func testWeeklyPeriodEndsOnTheCalendarWeeksLastDay() {
        let rule = RepeatRule.weekly(on: [])
        XCTAssertEqual(periodEnd(rule, "2026-10-14", start: "2026-10-14"), "2026-10-18", "Sunday, Monday-first")
        XCTAssertEqual(
            periodEnd(rule, "2026-10-14", start: "2026-10-14", calendar: TestCalendars.sundayFirst),
            "2026-10-17", "Saturday, Sunday-first"
        )
    }

    func testWeeklyOnTwoDaysEndsBeforeTheNextOccurrence() {
        let rule = RepeatRule.weekly(on: [monday, thursday])
        XCTAssertEqual(periodEnd(rule, "2026-10-12", start: "2026-10-12"), "2026-10-14")
        XCTAssertEqual(periodEnd(rule, "2026-10-15", start: "2026-10-12"), "2026-10-18")
    }

    func testWeekdaysAndWeekendsPeriodEnds() {
        XCTAssertEqual(periodEnd(.weekdays, "2026-10-12", start: "2026-10-12"), "2026-10-12")
        XCTAssertEqual(periodEnd(.weekdays, "2026-10-16", start: "2026-10-12"), "2026-10-18")
        XCTAssertEqual(periodEnd(.weekends, "2026-10-17", start: "2026-10-12"), "2026-10-17")
        XCTAssertEqual(periodEnd(.weekends, "2026-10-18", start: "2026-10-12"), "2026-10-18")
    }

    func testEveryTwoWeeksPeriodEndsWithItsTwoWeekBlock() {
        XCTAssertEqual(periodEnd(.everyTwoWeeks, "2026-10-14", start: "2026-10-14"), "2026-10-25")
        XCTAssertEqual(periodEnd(.everyTwoWeeks, "2026-10-28", start: "2026-10-14"), "2026-11-08")
    }

    func testEveryNWeeksOnTwoDaysEndsBeforeTheNextOccurrenceOrTheBlock() {
        let rule = RepeatRule.everyNWeeks(2, on: [monday, wednesday])
        XCTAssertEqual(periodEnd(rule, "2026-10-12", start: "2026-10-12"), "2026-10-13")
        XCTAssertEqual(periodEnd(rule, "2026-10-14", start: "2026-10-12"), "2026-10-25")
    }

    func testMonthlyPeriodEndsOnTheMonthsLastDay() {
        XCTAssertEqual(periodEnd(.monthly, "2026-10-05", start: "2026-10-05"), "2026-10-31")
        XCTAssertEqual(periodEnd(.monthly, "2026-02-28", start: "2026-01-31"), "2026-02-28")
    }

    func testEveryNMonthsPeriodEndsWithItsBlock() {
        let rule = RepeatRule.everyNMonths(2)
        XCTAssertEqual(periodEnd(rule, "2026-01-15", start: "2026-01-15"), "2026-02-28")
        XCTAssertEqual(periodEnd(rule, "2026-03-15", start: "2026-01-15"), "2026-04-30")
    }

    func testYearlyPeriodEndsOn31December() {
        XCTAssertEqual(periodEnd(.yearly, "2026-10-14", start: "2026-10-14"), "2026-12-31")
    }

    func testEveryNDaysPeriodEndsTheDayBeforeTheNextOne() {
        XCTAssertEqual(periodEnd(.everyNDays(3), "2026-10-12", start: "2026-10-12"), "2026-10-14")
        XCTAssertEqual(periodEnd(.everyNDays(1), "2026-10-12", start: "2026-10-12"), "2026-10-12")
    }
}
