import Foundation
import XCTest

/// Every bump limit at its boundaries, plus the repeating-item period rule.
/// 14.10.2026 is a Wednesday; 18.10.2026 is the Sunday that ends its Monday-first week.
final class BumpRuleTests: XCTestCase {
    private func canBump(
        on dayKey: String,
        limit: BumpLimit,
        bumpCount: Int = 0,
        firstAdded: String = "2026-10-14",
        state: OccurrenceState = .open,
        repeating: Bool = false,
        periodEnd: String? = nil,
        calendar: Calendar = TestCalendars.munich
    ) -> Bool {
        BumpRules.canBump(
            state: state,
            dayKey: dayKey,
            isRepeating: repeating,
            periodEndDayKey: periodEnd,
            limit: limit,
            bumpCount: bumpCount,
            firstAddedDayKey: firstAdded,
            calendar: calendar
        )
    }

    func testCantBumpIsAlwaysDenied() {
        XCTAssertFalse(canBump(on: "2026-10-14", limit: .cantBump))
    }

    func testUpToThreeDaysCountsBumps() {
        XCTAssertTrue(canBump(on: "2026-10-14", limit: .upToDays(3), bumpCount: 0))
        XCTAssertTrue(canBump(on: "2026-10-16", limit: .upToDays(3), bumpCount: 2))
        XCTAssertFalse(canBump(on: "2026-10-17", limit: .upToDays(3), bumpCount: 3))
    }

    func testDeadlineAllowsMovingOntoTheDeadlineButNotPastIt() {
        let limit = BumpLimit.untilDeadline(dayKey: "2026-10-16")
        XCTAssertTrue(canBump(on: "2026-10-15", limit: limit))
        XCTAssertFalse(canBump(on: "2026-10-16", limit: limit))
    }

    func testEndOfWeekIsTheFirstAddedWeeksLastDay() {
        XCTAssertTrue(canBump(on: "2026-10-17", limit: .endOfWeek, bumpCount: 3))
        XCTAssertFalse(canBump(on: "2026-10-18", limit: .endOfWeek, bumpCount: 4))
    }

    func testEndOfWeekFollowsTheCalendarsFirstWeekday() {
        let calendar = TestCalendars.sundayFirst
        XCTAssertTrue(canBump(on: "2026-10-16", limit: .endOfWeek, calendar: calendar))
        XCTAssertFalse(canBump(on: "2026-10-17", limit: .endOfWeek, calendar: calendar))
    }

    func testUnlimitedAlwaysAllowed() {
        XCTAssertTrue(canBump(on: "2027-01-01", limit: .unlimited, bumpCount: 40))
    }

    func testOnlyOpenOccurrencesMove() {
        for state in [OccurrenceState.done, .skipped, .bumped] {
            XCTAssertFalse(canBump(on: "2026-10-14", limit: .unlimited, state: state), state.rawValue)
        }
    }

    func testDailyRepeatCannotBeBumped() {
        let end = RepeatRule.daily.periodEnd(for: "2026-10-14", startDayKey: "2026-10-01", calendar: TestCalendars.munich)
        XCTAssertFalse(canBump(on: "2026-10-14", limit: .unlimited, repeating: true, periodEnd: end))
    }

    func testWeeklyRepeatMovesDayByDayUntilSunday() {
        let end = RepeatRule.weekly(on: []).periodEnd(for: "2026-10-14", startDayKey: "2026-10-14", calendar: TestCalendars.munich)
        XCTAssertEqual(end, "2026-10-18")
        XCTAssertTrue(canBump(on: "2026-10-14", limit: .unlimited, repeating: true, periodEnd: end))
        XCTAssertTrue(canBump(on: "2026-10-17", limit: .unlimited, bumpCount: 3, repeating: true, periodEnd: end))
        XCTAssertFalse(canBump(on: "2026-10-18", limit: .unlimited, bumpCount: 4, repeating: true, periodEnd: end))
    }

    func testRepeatWithoutAPeriodEndCannotMove() {
        XCTAssertFalse(canBump(on: "2026-10-14", limit: .unlimited, repeating: true, periodEnd: nil))
    }

    func testRepeatAlsoObeysItsBumpLimit() {
        XCTAssertFalse(canBump(on: "2026-10-14", limit: .cantBump, repeating: true, periodEnd: "2026-10-18"))
    }

    func testStoredLimitRoundTrips() {
        let limits: [BumpLimit] = [.cantBump, .upToDays(3), .untilDeadline(dayKey: "2026-10-20"), .endOfWeek, .unlimited]
        for limit in limits {
            let rebuilt = BumpLimit(kindRaw: limit.kind.rawValue, days: limit.storedDays, deadlineDayKey: limit.storedDeadlineDayKey)
            XCTAssertEqual(rebuilt, limit)
        }
        XCTAssertEqual(BumpLimit(kindRaw: "untilDeadline", days: 0, deadlineDayKey: nil), .cantBump)
        XCTAssertEqual(BumpLimit(kindRaw: "???", days: 0, deadlineDayKey: nil), .cantBump)
        XCTAssertEqual(BumpLimit.defaultForNewOneOffs, .upToDays(3))
    }
}
