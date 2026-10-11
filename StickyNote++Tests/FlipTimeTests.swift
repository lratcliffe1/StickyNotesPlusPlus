import Foundation
import XCTest

/// Step 3 (DECISIONS.md, "3: flip times and settings"): which list Home and the widget show on
/// their own, each list's streak deadline, and the moments the list can change, in Munich.
/// 12.10.2026 is a Monday; the clocks go forward on 29.03.2026 and back on 25.10.2026.
final class FlipTimeTests: XCTestCase {
    private let munich = TestCalendars.munich

    private let setNine = DayRules(morningEnd: .setTime, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)
    private let doneOrSkipped = DayRules(morningEnd: .doneOrSkipped, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)

    private let unfinished = HomeModel.CompletionState(value: 2.0 / 6.0, isNeutral: false)
    private let finished = HomeModel.CompletionState(value: 1, isNeutral: false)

    /// The automatic list at `hour:minute` on `dayKey`, with that day on screen.
    private func list(
        _ dayKey: String, _ hour: Int, _ minute: Int,
        rules: DayRules,
        morning: HomeModel.CompletionState? = nil,
        eveningIsEmpty: Bool = false
    ) -> HomeModel.ContextualList {
        let now = TestCalendars.date(dayKey, hour, minute)
        return HomeModel.automaticList(
            for: TestCalendars.date(dayKey),
            now: now,
            rules: rules,
            morning: morning ?? unfinished,
            eveningIsEmpty: eveningIsEmpty,
            calendar: munich
        )
    }

    // MARK: - List choice at the boundaries

    func testSetTimeBoundaries() {
        XCTAssertEqual(list("2026-10-12", 8, 59, rules: setNine), .morning)
        XCTAssertEqual(list("2026-10-12", 9, 0, rules: setNine), .daily, "the set time ends the morning")
        XCTAssertEqual(list("2026-10-12", 11, 59, rules: setNine), .daily)
        XCTAssertEqual(list("2026-10-12", 12, 0, rules: setNine), .daily)
        XCTAssertEqual(list("2026-10-12", 20, 59, rules: setNine), .daily)
        XCTAssertEqual(list("2026-10-12", 21, 0, rules: setNine), .evening)
        XCTAssertEqual(list("2026-10-12", 23, 59, rules: setNine), .evening)
        XCTAssertEqual(list("2026-10-13", 0, 0, rules: setNine), .morning, "midnight starts a new morning")
    }

    func testDoneOrSkippedBoundaries() {
        XCTAssertEqual(list("2026-10-12", 8, 59, rules: doneOrSkipped), .morning)
        XCTAssertEqual(list("2026-10-12", 9, 0, rules: doneOrSkipped), .morning, "no set time: 09:00 means nothing")
        XCTAssertEqual(list("2026-10-12", 11, 59, rules: doneOrSkipped), .morning)
        XCTAssertEqual(list("2026-10-12", 12, 0, rules: doneOrSkipped), .morning, "the list flips only when done, not at 12:00")
        XCTAssertEqual(list("2026-10-12", 20, 59, rules: doneOrSkipped), .morning)
        XCTAssertEqual(list("2026-10-12", 21, 0, rules: doneOrSkipped), .evening, "the evening takes over an unfinished morning")
        XCTAssertEqual(list("2026-10-12", 12, 0, rules: doneOrSkipped, morning: finished), .daily)
        XCTAssertEqual(list("2026-10-12", 21, 0, rules: doneOrSkipped, eveningIsEmpty: true), .morning)
        XCTAssertEqual(list("2026-10-12", 23, 59, rules: doneOrSkipped), .evening)
        XCTAssertEqual(list("2026-10-13", 0, 0, rules: doneOrSkipped), .morning)
    }

    func testEveningOffNeverFlipsToEvening() {
        for rules in [setNine, doneOrSkipped] {
            var off = rules
            off.eveningStartMinutes = nil
            XCTAssertEqual(list("2026-10-12", 8, 59, rules: off), .morning)
            for (hour, minute) in [(20, 59), (21, 0), (23, 59)] {
                XCTAssertEqual(list("2026-10-12", hour, minute, rules: off, morning: finished), .daily)
            }
            XCTAssertEqual(list("2026-10-12", 21, 0, rules: off), rules.morningEnd == .setTime ? .daily : .morning)
            XCTAssertEqual(list("2026-10-13", 0, 0, rules: off), .morning)
        }
    }

    func testDoneOrSkippedFlipsAsSoonAsTheMorningIsDone() {
        XCTAssertEqual(list("2026-10-12", 7, 30, rules: doneOrSkipped, morning: finished), .daily)
        XCTAssertEqual(list("2026-10-12", 7, 30, rules: doneOrSkipped, morning: .neutral), .daily, "all skipped (or empty) flips too")
        XCTAssertEqual(list("2026-10-12", 7, 30, rules: setNine, morning: finished), .daily)
    }

    func testCompleteEveningStaysShowingUntilMidnight() {
        // The evening's own completion isn't an input: complete, it still shows until midnight.
        XCTAssertEqual(list("2026-10-12", 21, 30, rules: setNine, morning: finished), .evening)
        XCTAssertEqual(list("2026-10-12", 23, 59, rules: setNine, morning: finished), .evening)
        XCTAssertEqual(list("2026-10-13", 0, 0, rules: setNine, morning: .neutral), .daily, "the next day starts over")
    }

    /// Provisional: with nothing at all on the evening list, the day list stays.
    func testEmptyEveningLeavesTheDayList() {
        XCTAssertEqual(list("2026-10-12", 21, 30, rules: setNine, eveningIsEmpty: true), .daily)
    }

    func testAnotherDayOnScreenIsTheDayList() {
        let otherDay = HomeModel.automaticList(
            for: TestCalendars.date("2026-10-11"), now: TestCalendars.date("2026-10-12", 8), rules: setNine,
            morning: unfinished, eveningIsEmpty: false, calendar: munich
        )
        XCTAssertEqual(otherDay, .daily)
    }

    // MARK: - Manual flips

    /// A flip lasts until the next moment the list would change on its own: a set time, the
    /// evening's start, midnight. With no set time, 12:00 isn't one.
    func testFlipExpiresAtTheNextListBoundary() {
        let atEight = HomeModel.ManualListFlip.today(.daily, at: TestCalendars.date("2026-10-12", 8), rules: setNine, calendar: munich)
        XCTAssertEqual(atEight.expiresAt, TestCalendars.date("2026-10-12", 9))
        let atTen = HomeModel.ManualListFlip.today(.daily, at: TestCalendars.date("2026-10-12", 10), rules: doneOrSkipped, calendar: munich)
        XCTAssertEqual(atTen.expiresAt, TestCalendars.date("2026-10-12", 21), "not 12:00")
        var off = setNine
        off.eveningStartMinutes = nil
        let late = HomeModel.ManualListFlip.today(.morning, at: TestCalendars.date("2026-10-12", 22), rules: off, calendar: munich)
        XCTAssertEqual(late.expiresAt, TestCalendars.date("2026-10-13"))
    }

    /// Flip to the day list at 08:00, put the phone away, open the app at 21:30: whatever refresh
    /// runs first, the expired flip no longer hides the evening.
    func testResumingPastABoundaryDropsTheFlip() {
        let flip = HomeModel.ManualListFlip.today(.daily, at: TestCalendars.date("2026-10-12", 8), rules: doneOrSkipped, calendar: munich)
        XCTAssertEqual(HomeModel.shownList(automatic: .morning, flip: flip, now: TestCalendars.date("2026-10-12", 11)), .daily)
        XCTAssertEqual(HomeModel.shownList(automatic: .evening, flip: flip, now: TestCalendars.date("2026-10-12", 21, 30)), .evening)
        XCTAssertEqual(HomeModel.shownList(automatic: .evening, flip: nil, now: TestCalendars.date("2026-10-12", 21, 30)), .evening)
    }

    func testFlipOnAnotherDayLastsUntilHomeLeavesIt() {
        let flip = HomeModel.ManualListFlip.untilLeft(.evening)
        XCTAssertEqual(HomeModel.shownList(automatic: .daily, flip: flip, now: TestCalendars.date("2026-10-13", 23, 59)), .evening)
    }

    // MARK: - Streak deadlines

    func testStreakDeadlinesPerList() {
        let history = DayRulesHistory(stored: [
            "2026-10-12": DayRules(morningEnd: .setTime, morningEndMinutes: 8 * 60 + 30, eveningStartMinutes: 21 * 60),
            "2026-10-13": doneOrSkipped,
        ])
        let morning = ListService.deadline(for: .morning, history: history, calendar: munich)
        XCTAssertEqual(morning("2026-10-12"), TestCalendars.date("2026-10-12", 8, 30), "its set time")
        XCTAssertEqual(morning("2026-10-13"), TestCalendars.date("2026-10-13", 12), "no set time: 12:00")
        XCTAssertNil(ListService.deadline(for: .day, history: history, calendar: munich)("2026-10-12"), "day: midnight")
        XCTAssertNil(ListService.deadline(for: .evening, history: history, calendar: munich)("2026-10-12"), "evening: midnight")
    }

    // MARK: - DST (Europe/Berlin)

    func testClocksGoingForwardKeepWallClockTimes() {
        // 29.03.2026: 23 hours, 02:00–03:00 doesn't exist.
        XCTAssertEqual(list("2026-03-29", 8, 59, rules: setNine), .morning)
        XCTAssertEqual(list("2026-03-29", 9, 0, rules: setNine), .daily)
        XCTAssertEqual(list("2026-03-29", 11, 59, rules: doneOrSkipped), .morning)
        XCTAssertEqual(list("2026-03-29", 12, 0, rules: doneOrSkipped, morning: finished), .daily)
        XCTAssertEqual(list("2026-03-29", 21, 0, rules: setNine), .evening)

        let day = TestCalendars.date("2026-03-29")
        XCTAssertEqual(munich.component(.hour, from: setNine.morningDeadline(on: day, calendar: munich)), 9)
        XCTAssertEqual(munich.component(.hour, from: doneOrSkipped.morningDeadline(on: day, calendar: munich)), 12)
        let midnight = setNine.nextBoundary(after: TestCalendars.date("2026-03-29", 21, 30), calendar: munich)
        XCTAssertEqual(midnight, TestCalendars.date("2026-03-30"))
        XCTAssertEqual(midnight.timeIntervalSince(day), 23 * 3_600)

        // A time the clocks skip lands later that same day, never on another day.
        let skipped = DayRules.time(2 * 60 + 30, on: day, calendar: munich)
        XCTAssertEqual(HomeModel.dayKey(for: skipped, calendar: munich), "2026-03-29")
        XCTAssertEqual(munich.component(.hour, from: skipped), 3)
    }

    func testClocksGoingBackKeepWallClockTimes() {
        // 25.10.2026: 25 hours, 02:00–03:00 happens twice.
        XCTAssertEqual(list("2026-10-25", 8, 59, rules: setNine), .morning)
        XCTAssertEqual(list("2026-10-25", 9, 0, rules: setNine), .daily)
        XCTAssertEqual(list("2026-10-25", 11, 59, rules: doneOrSkipped), .morning)
        XCTAssertEqual(list("2026-10-25", 12, 0, rules: doneOrSkipped, morning: finished), .daily)
        XCTAssertEqual(list("2026-10-25", 20, 59, rules: setNine), .daily)
        XCTAssertEqual(list("2026-10-25", 21, 0, rules: setNine), .evening)

        let day = TestCalendars.date("2026-10-25")
        XCTAssertEqual(setNine.morningDeadline(on: day, calendar: munich), TestCalendars.date("2026-10-25", 9))
        XCTAssertEqual(setNine.eveningStart(on: day, calendar: munich), TestCalendars.date("2026-10-25", 21))
        XCTAssertEqual(setNine.nextBoundary(after: TestCalendars.date("2026-10-25", 8), calendar: munich), TestCalendars.date("2026-10-25", 9))
        XCTAssertEqual(setNine.nextBoundary(after: TestCalendars.date("2026-10-25", 9), calendar: munich), TestCalendars.date("2026-10-25", 21))
        let midnight = setNine.nextBoundary(after: TestCalendars.date("2026-10-25", 21), calendar: munich)
        XCTAssertEqual(midnight.timeIntervalSince(day), 25 * 3_600)

        let history = DayRulesHistory(stored: ["2026-10-25": doneOrSkipped])
        XCTAssertEqual(
            ListService.deadline(for: .morning, history: history, calendar: munich)("2026-10-25"),
            TestCalendars.date("2026-10-25", 12)
        )
    }
}
