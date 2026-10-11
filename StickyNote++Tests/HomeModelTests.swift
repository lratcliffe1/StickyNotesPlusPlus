import Foundation
import XCTest

/// High-signal tests for stable HomeModel domain rules.
final class HomeModelTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    func testDayKeyRoundTrip() {
        let day = HomeModel.normalizedDay(Date(timeIntervalSince1970: 1_700_000_000))
        let key = HomeModel.dayKey(for: day)
        let parsed = HomeModel.date(fromDayKey: key)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(HomeModel.normalizedDay(parsed ?? Date()), day)
    }

    func testDayFromStoredFallsBackToDateWhenKeyIsInvalid() {
        let fallback = Date(timeIntervalSince1970: 1_701_000_000)
        let resolved = HomeDataStore.dayFromStored(dayKey: "invalid", fallbackDate: fallback)

        XCTAssertEqual(resolved, HomeModel.normalizedDay(fallback))
    }

    /// Changed in step 2a (DECISIONS.md): an empty list is neutral, not 100%.
    func testEmptyListIsNeutralNotComplete() {
        let state = ListRules.completion([FactRow]())
        XCTAssertEqual(state.value, 0)
        XCTAssertTrue(state.isNeutral)
        XCTAssertFalse(state.isComplete)
    }

    func testCompletionPartial() {
        let rows = [FactRow(dayKey: "2026-03-10", state: .done), FactRow(dayKey: "2026-03-10", state: .open)]
        let state = ListRules.completion(rows)
        XCTAssertEqual(state.value, 0.5, accuracy: 0.0001)
        XCTAssertFalse(state.isNeutral)
    }

    func testShouldShowMorningListBeforeDeadlineWhenIncomplete() {
        let calendar = utcCalendar
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8, minute: 30)) ?? Date()

        let shouldShow = HomeModel.automaticList(
            for: selectedDay,
            now: now,
            rules: .legacy,
            morning: ListRules.completion([FactRow(dayKey: "2026-03-10", state: .open)]),
            eveningIsEmpty: true,
            calendar: calendar
        ) == .morning

        XCTAssertTrue(shouldShow)
    }

    func testShouldNotShowMorningListAfterDeadline() {
        let calendar = utcCalendar
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9, minute: 1)) ?? Date()

        let shouldShow = HomeModel.automaticList(
            for: selectedDay,
            now: now,
            rules: .legacy,
            morning: ListRules.completion([FactRow(dayKey: "2026-03-10", state: .open)]),
            eveningIsEmpty: true,
            calendar: calendar
        ) == .morning

        XCTAssertFalse(shouldShow)
    }

    /// An empty or all-skipped morning list lets Home flip straight to the day list.
    func testNeutralMorningListDoesNotShow() {
        let calendar = utcCalendar
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8, minute: 30)) ?? Date()

        for rows in [[], [FactRow(dayKey: "2026-03-10", state: .skipped)]] {
            XCTAssertEqual(
                HomeModel.automaticList(
                    for: selectedDay,
                    now: now,
                    rules: .legacy,
                    morning: ListRules.completion(rows),
                    eveningIsEmpty: true,
                    calendar: calendar
                ),
                .daily
            )
        }
    }

    func testDailyStreakFreezeAfterSingleMiss() {
        let rows = [
            FactRow(dayKey: "2026-03-08", state: .done),
            FactRow(dayKey: "2026-03-09", state: .open),
        ]
        let streak = ListRules.streakState(through: "2026-03-10", occurrences: rows) { _ in nil }

        XCTAssertEqual(streak.count, 1)
        XCTAssertTrue(streak.isFrozen)
    }
}
