import Foundation
import XCTest

/// Following today across midnight, the next refresh moment, and never-miss-twice wording rules.
final class ClockAndRiskTests: XCTestCase {
    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private let nineOClock = HomeModel.MorningMode.cutoff(time: DateComponents(hour: 9, minute: 0))

    // MARK: - Next clock boundary

    func testBoundaryIsTodaysCutoffWhenStillAhead() {
        let now = date(2026, 10, 12, 8, 15)
        XCTAssertEqual(HomeModel.nextClockBoundary(after: now, mode: nineOClock, calendar: berlin), date(2026, 10, 12, 9, 0))
    }

    func testBoundaryIsNextMidnightOnceCutoffHasPassed() {
        let now = date(2026, 10, 12, 14, 0)
        XCTAssertEqual(HomeModel.nextClockBoundary(after: now, mode: nineOClock, calendar: berlin), date(2026, 10, 13))
    }

    func testBoundaryAtExactCutoffMovesToMidnight() {
        let now = date(2026, 10, 12, 9, 0)
        XCTAssertEqual(HomeModel.nextClockBoundary(after: now, mode: nineOClock, calendar: berlin), date(2026, 10, 13))
    }

    /// 25.10.2026 is 25 hours long in Munich (clocks go back at 03:00).
    func testBoundaryAcrossClocksGoingBackIsLocalMidnight() {
        let now = date(2026, 10, 25, 14, 0)
        let boundary = HomeModel.nextClockBoundary(after: now, mode: nineOClock, calendar: berlin)
        XCTAssertEqual(boundary, date(2026, 10, 26))
        XCTAssertEqual(berlin.component(.hour, from: boundary), 0)
        XCTAssertEqual(boundary.timeIntervalSince(date(2026, 10, 25)), 25 * 3_600)
    }

    /// 29.03.2026 is 23 hours long (clocks go forward at 02:00).
    func testBoundaryAcrossClocksGoingForwardIsLocalMidnight() {
        let now = date(2026, 3, 29, 14, 0)
        let boundary = HomeModel.nextClockBoundary(after: now, mode: nineOClock, calendar: berlin)
        XCTAssertEqual(boundary.timeIntervalSince(date(2026, 3, 29)), 23 * 3_600)
    }

    func testBoundaryUsesWakeUpWindowEnd() {
        let mode = HomeModel.MorningMode.sinceWakeUp(wakeUpTime: DateComponents(hour: 7, minute: 0), durationMinutes: 90)
        let now = date(2026, 10, 12, 7, 10)
        XCTAssertEqual(HomeModel.nextClockBoundary(after: now, mode: mode, calendar: berlin), date(2026, 10, 12, 8, 30))
    }

    // MARK: - Following today

    func testFollowingTodayMovesToNewDayAfterMidnight() {
        let yesterday = date(2026, 10, 11)
        let now = date(2026, 10, 12, 7, 5)
        XCTAssertEqual(
            HomeModel.dayToShow(selectedDay: yesterday, followingToday: true, now: now, calendar: berlin),
            date(2026, 10, 12)
        )
    }

    func testChosenDayStaysPutAfterMidnight() {
        let chosen = date(2026, 10, 3)
        let now = date(2026, 10, 12, 7, 5)
        XCTAssertEqual(
            HomeModel.dayToShow(selectedDay: chosen, followingToday: false, now: now, calendar: berlin),
            chosen
        )
    }

    // MARK: - Never-miss-twice risk

    func testNotFrozenMeansNoRisk() {
        XCTAssertEqual(HomeModel.streakRisk(isFrozen: false, deadline: date(2026, 10, 12, 9), now: date(2026, 10, 12, 14)), .none)
    }

    func testFrozenBeforeCutoffIsSaveable() {
        XCTAssertEqual(HomeModel.streakRisk(isFrozen: true, deadline: date(2026, 10, 12, 9), now: date(2026, 10, 12, 8, 15)), .saveable)
    }

    func testFrozenAfterCutoffIsLost() {
        XCTAssertEqual(HomeModel.streakRisk(isFrozen: true, deadline: date(2026, 10, 12, 9), now: date(2026, 10, 12, 9)), .lost)
    }

    func testFrozenWithoutDeadlineIsSaveableAllDay() {
        XCTAssertEqual(HomeModel.streakRisk(isFrozen: true, deadline: nil, now: date(2026, 10, 12, 23, 59)), .saveable)
    }
}
