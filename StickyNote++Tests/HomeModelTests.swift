import Foundation
import XCTest

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

    func testMorningCompletionEmptyIsImplicitlyComplete() {
        let state = HomeModel.morningCompletion(entries: [])
        XCTAssertEqual(state.value, 1.0)
        XCTAssertTrue(state.isImplicitlyComplete)
    }

    func testDailyCompletionPartialTasks() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let tasks = [
            DailyTask(date: day, title: "One", isCompleted: true),
            DailyTask(date: day, title: "Two", isCompleted: false),
        ]

        let state = HomeModel.dailyCompletion(tasks: tasks)
        XCTAssertEqual(state.value, 0.5, accuracy: 0.0001)
        XCTAssertFalse(state.isImplicitlyComplete)
    }

    func testShouldShowMorningListBeforeDeadlineWhenIncomplete() {
        let calendar = utcCalendar
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8, minute: 30)) ?? Date()
        let entries = [MorningRoutineEntry(date: selectedDay, titleSnapshot: "Hydrate", isCompleted: false)]

        let shouldShow = HomeModel.shouldShowMorningList(
            for: selectedDay,
            morningEntries: entries,
            mode: .cutoff(time: DateComponents(hour: 9, minute: 0)),
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(shouldShow)
    }

    func testShouldNotShowMorningListAfterDeadline() {
        let calendar = utcCalendar
        let selectedDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 9, minute: 1)) ?? Date()
        let entries = [MorningRoutineEntry(date: selectedDay, titleSnapshot: "Hydrate", isCompleted: false)]

        let shouldShow = HomeModel.shouldShowMorningList(
            for: selectedDay,
            morningEntries: entries,
            mode: .cutoff(time: DateComponents(hour: 9, minute: 0)),
            now: now,
            calendar: calendar
        )

        XCTAssertFalse(shouldShow)
    }

    func testDailyStreakFreezeAfterSingleMiss() {
        let calendar = utcCalendar
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)) ?? Date()
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)) ?? Date()
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()

        let tasksByDay: [Date: [DailyTask]] = [
            HomeModel.normalizedDay(day1, calendar: calendar): [DailyTask(date: day1, title: "A", isCompleted: true)],
            HomeModel.normalizedDay(day2, calendar: calendar): [],
            HomeModel.normalizedDay(anchor, calendar: calendar): [],
        ]

        let streak = HomeModel.dailyStreakState(
            through: anchor,
            tasksByDay: tasksByDay,
            calendar: calendar
        )

        XCTAssertEqual(streak.count, 1)
        XCTAssertTrue(streak.isFrozen)
    }
}
