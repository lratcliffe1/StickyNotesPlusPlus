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

    /// 09:00 set time, evening Off: the boundaries are the cutoff and midnight.
    private let nineOClock = DayRules(morningEnd: .setTime, morningEndMinutes: 9 * 60, eveningStartMinutes: nil)

    // MARK: - Next clock boundary

    func testBoundaryIsTodaysCutoffWhenStillAhead() {
        let now = date(2026, 10, 12, 8, 15)
        XCTAssertEqual(nineOClock.nextBoundary(after: now, calendar: berlin), date(2026, 10, 12, 9, 0))
    }

    func testBoundaryIsNextMidnightOnceCutoffHasPassed() {
        let now = date(2026, 10, 12, 14, 0)
        XCTAssertEqual(nineOClock.nextBoundary(after: now, calendar: berlin), date(2026, 10, 13))
    }

    func testBoundaryAtExactCutoffMovesToMidnight() {
        let now = date(2026, 10, 12, 9, 0)
        XCTAssertEqual(nineOClock.nextBoundary(after: now, calendar: berlin), date(2026, 10, 13))
    }

    /// 25.10.2026 is 25 hours long in Munich (clocks go back at 03:00).
    func testBoundaryAcrossClocksGoingBackIsLocalMidnight() {
        let now = date(2026, 10, 25, 14, 0)
        let boundary = nineOClock.nextBoundary(after: now, calendar: berlin)
        XCTAssertEqual(boundary, date(2026, 10, 26))
        XCTAssertEqual(berlin.component(.hour, from: boundary), 0)
        XCTAssertEqual(boundary.timeIntervalSince(date(2026, 10, 25)), 25 * 3_600)
    }

    /// 29.03.2026 is 23 hours long (clocks go forward at 02:00).
    func testBoundaryAcrossClocksGoingForwardIsLocalMidnight() {
        let now = date(2026, 3, 29, 14, 0)
        let boundary = nineOClock.nextBoundary(after: now, calendar: berlin)
        XCTAssertEqual(boundary.timeIntervalSince(date(2026, 3, 29)), 23 * 3_600)
    }

    /// With no set time, the morning's boundary is 12:00; then the evening's start; then midnight.
    func testBoundariesInDoneOrSkippedModeWithEvening() {
        let rules = DayRules(morningEnd: .doneOrSkipped, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)
        XCTAssertEqual(rules.nextBoundary(after: date(2026, 10, 12, 8, 15), calendar: berlin), date(2026, 10, 12, 12, 0))
        XCTAssertEqual(rules.nextBoundary(after: date(2026, 10, 12, 12, 0), calendar: berlin), date(2026, 10, 12, 21, 0))
        XCTAssertEqual(rules.nextBoundary(after: date(2026, 10, 12, 21, 0), calendar: berlin), date(2026, 10, 13))
    }

    /// A set time, then the evening's start, then midnight.
    func testBoundariesWithSetTimeAndEvening() {
        let rules = DayRules(morningEnd: .setTime, morningEndMinutes: 8 * 60 + 30, eveningStartMinutes: 20 * 60)
        XCTAssertEqual(rules.nextBoundary(after: date(2026, 10, 12, 0, 0), calendar: berlin), date(2026, 10, 12, 8, 30))
        XCTAssertEqual(rules.nextBoundary(after: date(2026, 10, 12, 8, 30), calendar: berlin), date(2026, 10, 12, 20, 0))
        XCTAssertEqual(rules.nextBoundary(after: date(2026, 10, 12, 20, 30), calendar: berlin), date(2026, 10, 13))
    }

    // MARK: - Following today

    func testFollowingTodayMovesToNewDayAfterMidnightAndDropsManualFlip() {
        let follow = HomeModel.followClock(
            selectedDay: date(2026, 10, 11), followingToday: true, now: date(2026, 10, 12, 7, 5), calendar: berlin
        )
        XCTAssertEqual(follow, HomeModel.ClockFollow(day: date(2026, 10, 12), followingToday: true, clearsManualList: true))
    }

    func testFollowingTodaySameDayKeepsManualFlip() {
        let follow = HomeModel.followClock(
            selectedDay: date(2026, 10, 12), followingToday: true, now: date(2026, 10, 12, 9, 1), calendar: berlin
        )
        XCTAssertEqual(follow, HomeModel.ClockFollow(day: date(2026, 10, 12), followingToday: true, clearsManualList: false))
    }

    func testChosenPastDayStaysPutAndKeepsNotFollowing() {
        let follow = HomeModel.followClock(
            selectedDay: date(2026, 10, 3), followingToday: false, now: date(2026, 10, 12, 7, 5), calendar: berlin
        )
        XCTAssertEqual(follow, HomeModel.ClockFollow(day: date(2026, 10, 3), followingToday: false, clearsManualList: false))
    }

    /// Monday picked on Sunday evening: at midnight it becomes today, so following resumes,
    /// and on Tuesday Home moves on instead of sticking on Monday.
    func testChosenDayThatBecomesTodayResumesFollowing() {
        let mondayMidnight = HomeModel.followClock(
            selectedDay: date(2026, 10, 12), followingToday: false, now: date(2026, 10, 12, 0, 0), calendar: berlin
        )
        XCTAssertEqual(mondayMidnight, HomeModel.ClockFollow(day: date(2026, 10, 12), followingToday: true, clearsManualList: false))

        let tuesday = HomeModel.followClock(
            selectedDay: mondayMidnight.day, followingToday: mondayMidnight.followingToday,
            now: date(2026, 10, 13, 7, 0), calendar: berlin
        )
        XCTAssertEqual(tuesday.day, date(2026, 10, 13))
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
