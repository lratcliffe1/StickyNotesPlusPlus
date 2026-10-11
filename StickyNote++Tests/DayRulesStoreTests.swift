import Foundation
import SwiftData
import XCTest

/// Each day keeps the rules it had (DECISIONS.md, "streak rules" and "3: flip times and
/// settings"): storing them, judging past days by them, and migrating the old wake-up window.
final class DayRulesStoreTests: XCTestCase {
    private let munich = TestCalendars.munich
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let setNine = DayRules(morningEnd: .setTime, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)
    private let setEight = DayRules(morningEnd: .setTime, morningEndMinutes: 8 * 60, eveningStartMinutes: 21 * 60)
    private let doneOrSkipped = DayRules(morningEnd: .doneOrSkipped, morningEndMinutes: 9 * 60, eveningStartMinutes: nil)

    override func setUp() {
        let made = StoreTestSupport.makeDefaults()
        defaults = made.defaults
        suiteName = made.name
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Which rules a day is judged by

    func testPastDaysUseTheirOwnStoredRules() {
        let history = DayRulesHistory(stored: ["2026-10-10": setEight, "2026-10-11": doneOrSkipped, "2026-10-12": setNine])
        XCTAssertEqual(history.rules(for: "2026-10-10"), setEight)
        XCTAssertEqual(history.rules(for: "2026-10-11"), doneOrSkipped)
        XCTAssertEqual(history.rules(for: "2026-10-12"), setNine)
    }

    func testDaysBeforeTheFirstRecordUseTheOldNineOClockCutoff() {
        let history = DayRulesHistory(stored: ["2026-10-12": doneOrSkipped])
        XCTAssertEqual(history.rules(for: "2026-10-11"), .legacy)
        XCTAssertEqual(history.rules(for: "2025-01-01"), .legacy)
        XCTAssertEqual(DayRules.legacy.morningEnd, .setTime)
        XCTAssertEqual(DayRules.legacy.morningDeadlineMinutes, 9 * 60)
        XCTAssertEqual(DayRulesHistory().rules(for: "2026-10-12"), .legacy, "nothing stored at all")
    }

    func testUnopenedDaysInheritTheNearestEarlierRecord() {
        let history = DayRulesHistory(stored: ["2026-10-01": setEight, "2026-10-05": doneOrSkipped, "2026-10-09": setNine])
        XCTAssertEqual(history.rules(for: "2026-10-03"), setEight)
        XCTAssertEqual(history.rules(for: "2026-10-06"), doneOrSkipped)
        XCTAssertEqual(history.rules(for: "2026-10-08"), doneOrSkipped)
        XCTAssertEqual(history.rules(for: "2026-10-20"), setNine)
        // Day keys compare as dates across months and years.
        let acrossYear = DayRulesHistory(stored: ["2025-12-31": doneOrSkipped, "2026-02-01": setEight])
        XCTAssertEqual(acrossYear.rules(for: "2026-01-15"), doneOrSkipped)
    }

    // MARK: - Writing

    func testFirstWriteWins() {
        XCTAssertTrue(DayRulesStore.record(setEight, for: "2026-10-12", in: defaults))
        XCTAssertFalse(DayRulesStore.record(doneOrSkipped, for: "2026-10-12", in: defaults), "the day already has rules")
        XCTAssertEqual(DayRulesStore.history(in: defaults).stored, ["2026-10-12": setEight])
    }

    func testSettingsChangeRewritesTodayOnly() {
        DayRulesStore.record(setEight, for: "2026-10-11", in: defaults)
        DayRulesStore.record(setEight, for: "2026-10-12", in: defaults)
        defaults.set(DayRules.MorningEnd.doneOrSkipped.rawValue, forKey: AppSettings.morningEndKey)
        defaults.set(false, forKey: AppSettings.eveningEnabledKey)

        ListService.applySettingsToToday(now: TestCalendars.date("2026-10-12", 7), calendar: munich, defaults: defaults)

        let stored = DayRulesStore.history(in: defaults).stored
        XCTAssertEqual(stored["2026-10-11"], setEight, "past days never change")
        XCTAssertEqual(stored["2026-10-12"], doneOrSkipped, "today takes the new settings")
    }

    func testPrepareStoresTodaysRulesFromTheSettingsOnce() throws {
        let context = try StoreTestSupport.makeContext()
        defaults.set(8 * 60, forKey: AppSettings.morningCutoffMinutesKey)
        try ListService.prepare(context: context, now: TestCalendars.date("2026-10-12", 7), calendar: munich, defaults: defaults)
        XCTAssertEqual(DayRulesStore.history(in: defaults).stored["2026-10-12"], setEight)

        // A later read the same day (the widget, say) after the setting moved doesn't rewrite it.
        defaults.set(10 * 60, forKey: AppSettings.morningCutoffMinutesKey)
        try ListService.prepare(context: context, now: TestCalendars.date("2026-10-12", 9), calendar: munich, defaults: defaults)
        XCTAssertEqual(DayRulesStore.history(in: defaults).stored["2026-10-12"], setEight)
    }

    func testDefaultsOnUpgradeAreSetNineWithEveningAtNine() {
        let rules = AppSettings.currentRules(in: defaults)
        XCTAssertEqual(rules, DayRules(morningEnd: .setTime, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60))
    }

    func testUnreadableRecordsAreNeverOverwritten() {
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: DayRulesStore.storageKey)
        XCTAssertFalse(DayRulesStore.record(setNine, for: "2026-10-12", in: defaults))
        XCTAssertEqual(defaults.data(forKey: DayRulesStore.storageKey), junk)
        XCTAssertEqual(DayRulesStore.history(in: defaults).rules(for: "2026-10-12"), .legacy)
    }

    // MARK: - The wake-up window migration

    func testSavedWakeUpWindowBecomesASetTime() {
        defaults.set("sinceWakeUp", forKey: AppSettings.legacyMorningModeKey)
        defaults.set(6 * 60 + 30, forKey: AppSettings.legacyWakeUpMinutesKey)
        defaults.set(120, forKey: AppSettings.legacyWindowDurationMinutesKey)

        let rules = AppSettings.currentRules(in: defaults)
        XCTAssertEqual(rules.morningEnd, .setTime)
        XCTAssertEqual(rules.morningEndMinutes, 8 * 60 + 30, "wake-up + duration")
        XCTAssertNil(defaults.object(forKey: AppSettings.legacyMorningModeKey), "read once, then removed")
        XCTAssertNil(defaults.object(forKey: AppSettings.legacyWakeUpMinutesKey))
        XCTAssertNil(defaults.object(forKey: AppSettings.legacyWindowDurationMinutesKey))

        // Once migrated, a later change to the time sticks.
        defaults.set(7 * 60, forKey: AppSettings.morningCutoffMinutesKey)
        XCTAssertEqual(AppSettings.currentRules(in: defaults).morningEndMinutes, 7 * 60)
    }

    func testWakeUpWindowDurationIsClampedAsBefore() {
        defaults.set("sinceWakeUp", forKey: AppSettings.legacyMorningModeKey)
        defaults.set(1_000, forKey: AppSettings.legacyWindowDurationMinutesKey)
        // Wake-up defaults to 07:00; the duration is clamped to 240 minutes.
        XCTAssertEqual(AppSettings.currentRules(in: defaults).morningEndMinutes, 11 * 60)
    }

    func testSavedCutoffModeKeepsItsTime() {
        defaults.set("cutoff", forKey: AppSettings.legacyMorningModeKey)
        defaults.set(8 * 60 + 15, forKey: AppSettings.morningCutoffMinutesKey)
        let rules = AppSettings.currentRules(in: defaults)
        XCTAssertEqual(rules.morningEnd, .setTime)
        XCTAssertEqual(rules.morningEndMinutes, 8 * 60 + 15)
        XCTAssertNil(defaults.object(forKey: AppSettings.legacyMorningModeKey))
    }

    // MARK: - Streaks judge each day by its own rules

    /// 10.10 is from before this build (09:00); 11.10 had no set time (12:00); 12.10 nobody opened,
    /// so it inherits 11.10's rules. Each morning finished at 10:30.
    func testMorningStreakJudgesEachDayByItsOwnRules() throws {
        let context = try StoreTestSupport.makeContext()
        for key in ["2026-10-10", "2026-10-11", "2026-10-12"] {
            context.insert(Occurrence(list: .morning, dayKey: key, title: "Water", state: .done, completedAt: TestCalendars.date(key, 10, 30)))
        }
        try context.save()
        let history = DayRulesHistory(stored: ["2026-10-11": doneOrSkipped])

        let looks = try ListService.dayLooks(
            for: .morning, through: "2026-10-12", todayKey: "2026-10-13", history: history, context: context, calendar: munich
        )
        XCTAssertEqual(looks["2026-10-10"]?.status, .missed, "pre-feature day: 10:30 is after 09:00")
        XCTAssertEqual(looks["2026-10-11"]?.status, .complete, "its own rules: before 12:00")
        XCTAssertEqual(looks["2026-10-12"]?.status, .complete, "inherits 11.10's 12:00")

        let streak = try ListService.streakState(for: .morning, through: "2026-10-13", history: history, context: context, calendar: munich)
        XCTAssertEqual(streak, HomeModel.StreakState(count: 2, isFrozen: false))

        // Changing today's (13.10's) settings doesn't recount the past.
        var later = history
        later.stored["2026-10-13"] = setEight
        XCTAssertEqual(
            try ListService.streakState(for: .morning, through: "2026-10-13", history: later, context: context, calendar: munich),
            streak
        )
    }
}
