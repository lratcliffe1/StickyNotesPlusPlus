import Foundation
import XCTest

/// Step 2b's pure rules (DECISIONS.md, 2b): the flip order, Retype to bump, the add menu's options,
/// the bump sheet's cost lines and the bump marks.
/// 14.10.2026 is a Wednesday; 18.10.2026 the Sunday that ends its Monday-first week.
final class ControlRuleTests: XCTestCase {
    // MARK: - Flip

    func testFlipCyclesMorningDayEvening() {
        XCTAssertEqual(HomeModel.ContextualList.morning.next, .daily)
        XCTAssertEqual(HomeModel.ContextualList.daily.next, .evening)
        XCTAssertEqual(HomeModel.ContextualList.evening.next, .morning)
        XCTAssertEqual(HomeModel.ContextualList.allCases.map(\.listKind), [.morning, .day, .evening])
    }

    // MARK: - Retype to bump

    func testRetypeToBumpIsOnByDefault() {
        let (defaults, name) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(AppSettings.retypeToBump(in: defaults))
        defaults.set(false, forKey: AppSettings.retypeToBumpKey)
        XCTAssertFalse(AppSettings.retypeToBump(in: defaults))
    }

    func testRetypeToBumpNeedsSomethingTypedAndKeepsTheTypedTitle() {
        XCTAssertNil(BumpRules.bumpedTitle(typed: "", original: "Post", retypeRequired: true))
        XCTAssertNil(BumpRules.bumpedTitle(typed: "   ", original: "Post", retypeRequired: true))
        XCTAssertEqual(BumpRules.bumpedTitle(typed: " Post the forms ", original: "Post", retypeRequired: true), "Post the forms")
        XCTAssertEqual(BumpRules.bumpedTitle(typed: "", original: "Post", retypeRequired: false), "Post",
                       "with retype off, an empty field keeps the old title")
        XCTAssertEqual(BumpRules.bumpedTitle(typed: "Post today", original: "Post", retypeRequired: false), "Post today")
    }

    // MARK: - Add options

    func testOneOffOptionsResolveTheirBumpLimit() {
        var options = OneOffOptions()
        XCTAssertTrue(options.isDefault)
        XCTAssertEqual(options.bumpLimit, .upToDays(3), "a plain add keeps the default")

        options.limitChoice = .untilDeadline
        XCTAssertEqual(options.bumpLimit, .upToDays(3), "until deadline without a deadline falls back to the default")
        options.deadlineDayKey = "2026-10-20"
        XCTAssertEqual(options.bumpLimit, .untilDeadline(dayKey: "2026-10-20"))
        XCTAssertFalse(options.isDefault)

        options.limitChoice = .endOfWeek
        XCTAssertEqual(options.bumpLimit, .endOfWeek)
        options.limitChoice = .unlimited
        XCTAssertEqual(options.bumpLimit, .unlimited)
        options.limitChoice = .upToDays
        options.days = 0
        XCTAssertEqual(options.bumpLimit, .upToDays(1), "at least one bump")

        options.mustHappenToday = true
        XCTAssertEqual(options.bumpLimit, .cantBump, "must happen today wins")
    }

    func testBumpLimitChoiceRoundTrips() {
        let limits: [BumpLimit] = [.cantBump, .upToDays(5), .endOfWeek, .untilDeadline(dayKey: "2026-10-20"), .unlimited]
        for limit in limits {
            let choice = BumpLimitChoice(limit)
            XCTAssertEqual(choice.limit(days: limit.storedDays, deadlineDayKey: limit.storedDeadlineDayKey), limit)
        }
        XCTAssertNil(BumpLimitChoice.untilDeadline.limit(days: 3, deadlineDayKey: nil))
    }

    // MARK: - What a bump costs

    private func costs(
        dayKey: String = "2026-10-14",
        repeating: Bool = false,
        scheduled: String? = nil,
        periodEnd: String? = nil,
        repeatInfo: (rule: RepeatRule, startDayKey: String)? = nil,
        limit: BumpLimit,
        bumpCount: Int = 0,
        firstAdded: String = "2026-10-14"
    ) -> [BumpCost] {
        BumpRules.costs(
            dayKey: dayKey, isRepeating: repeating, scheduledDayKey: scheduled, periodEndDayKey: periodEnd,
            repeatInfo: repeatInfo, limit: limit, bumpCount: bumpCount, firstAddedDayKey: firstAdded,
            calendar: TestCalendars.munich
        )
    }

    func testBumpCostLinesForOneOffs() {
        XCTAssertEqual(costs(limit: .upToDays(3), bumpCount: 2), [.bumpsUsed(used: 2, limit: 3)])
        XCTAssertEqual(costs(limit: .untilDeadline(dayKey: "2026-10-17")), [.deadline(dayKey: "2026-10-17")])
        XCTAssertEqual(costs(limit: .endOfWeek), [.endOfWeek(dayKey: "2026-10-18", isThisWeek: true)])
        XCTAssertEqual(costs(dayKey: "2026-10-19", limit: .endOfWeek), [.endOfWeek(dayKey: "2026-10-18", isThisWeek: false)])
        XCTAssertEqual(costs(limit: .unlimited), [.unlimited])
        XCTAssertEqual(costs(limit: .cantBump), [])
    }

    func testBumpCostLinesForRepeats() {
        let monthly = RepeatRule.monthly
        XCTAssertEqual(
            costs(repeating: true, scheduled: "2026-10-14", periodEnd: "2026-10-31",
                  repeatInfo: (monthly, "2026-09-14"), limit: .unlimited),
            [.periodEnd(dayKey: "2026-10-31", period: "month", beforeNextDue: false)]
        )
        XCTAssertEqual(
            costs(repeating: true, scheduled: "2026-10-12", periodEnd: "2026-10-14",
                  repeatInfo: (RepeatRule.weekly(on: [2, 5]), "2026-10-12"), limit: .upToDays(1), bumpCount: 1),
            [.periodEnd(dayKey: "2026-10-14", period: "week", beforeNextDue: true), .bumpsUsed(used: 1, limit: 1)]
        )
    }

    func testBumpCostText() {
        let munich = TestCalendars.munich
        XCTAssertEqual(BumpCost.bumpsUsed(used: 2, limit: 3).text(calendar: munich), "2 of 3 bumps used")
        XCTAssertEqual(BumpCost.bumpsUsed(used: 0, limit: 1).text(calendar: munich), "0 of 1 bump used")
        XCTAssertEqual(BumpCost.endOfWeek(dayKey: "2026-10-18", isThisWeek: true).text(calendar: munich), "Until the end of this week")
        XCTAssertEqual(BumpCost.unlimited.text(calendar: munich), "No bump limit")
        XCTAssertTrue(BumpCost.deadline(dayKey: "2026-10-17").text(calendar: munich).hasPrefix("Can bump until "))
        XCTAssertTrue(BumpCost.periodEnd(dayKey: "2026-10-31", period: "month", beforeNextDue: false)
            .text(calendar: munich).hasPrefix("Until the end of its month ("))
    }

    func testPeriodNames() {
        XCTAssertEqual(RepeatRule.daily.periodName, "day")
        XCTAssertEqual(RepeatRule.weekdays.periodName, "week")
        XCTAssertEqual(RepeatRule.weekly(on: [2]).periodName, "week")
        XCTAssertEqual(RepeatRule.everyTwoWeeks.periodName, "2 weeks")
        XCTAssertEqual(RepeatRule.everyNWeeks(3, on: [2]).periodName, "3 weeks")
        XCTAssertEqual(RepeatRule.monthly.periodName, "month")
        XCTAssertEqual(RepeatRule.everyNMonths(6).periodName, "6 months")
        XCTAssertEqual(RepeatRule.everyNDays(4).periodName, "4 days")
        XCTAssertEqual(RepeatRule.yearly.periodName, "year")
    }

    // MARK: - Widget bump link

    func testBumpDeepLinkRoundTrips() throws {
        let id = UUID()
        let url = BumpDeepLink.url(for: id)
        XCTAssertEqual(url.scheme, "stickynotes")
        XCTAssertEqual(BumpDeepLink.occurrenceID(from: url), id)
        XCTAssertNil(BumpDeepLink.occurrenceID(from: try XCTUnwrap(URL(string: "stickynotes://add-daily-task"))))
        XCTAssertNil(BumpDeepLink.occurrenceID(from: try XCTUnwrap(URL(string: "stickynotes://bump?id=nonsense"))))
        XCTAssertNil(BumpDeepLink.occurrenceID(from: try XCTUnwrap(URL(string: "https://bump?id=\(id.uuidString)"))))
    }

    // MARK: - Bump marks

    func testBumpedDaysAndBumpCount() {
        let rows = [
            FactRow(dayKey: "2026-10-11", state: .bumped),
            FactRow(dayKey: "2026-10-12", state: .bumped),
            FactRow(dayKey: "2026-10-12", state: .bumped),
            FactRow(dayKey: "2026-10-13", state: .done),
            FactRow(dayKey: "2026-10-14", state: .open),
            FactRow(dayKey: "2026-10-16", state: .bumped),
        ]
        XCTAssertEqual(ListRules.bumpedDays(rows), ["2026-10-11", "2026-10-12", "2026-10-16"])
        XCTAssertEqual(ListRules.bumpCount(rows, from: "2026-10-12", through: "2026-10-14"), 2, "two bumps on one day are two")
        XCTAssertEqual(ListRules.bumpCount(rows, from: "2026-10-13", through: "2026-10-14"), 0)
    }
}
