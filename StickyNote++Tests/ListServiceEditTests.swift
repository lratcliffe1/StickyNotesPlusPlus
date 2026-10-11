import Foundation
import SwiftData
import XCTest

/// Step 2b's service operations (DECISIONS.md, 2b): undo skip, the item editor's repeat split and
/// bump-limit edit, one-off edits, adding with options, and the bump marks.
/// Monday-first Munich calendar: 12.10.2026 is a Monday, 14.10.2026 a Wednesday.
final class ListServiceEditTests: XCTestCase {
    private let munich = TestCalendars.munich
    private var context: ModelContext!

    override func setUpWithError() throws {
        context = try StoreTestSupport.makeContext()
    }

    override func tearDown() {
        context = nil
    }

    private func noon(_ key: String) -> Date {
        TestCalendars.date(key, 12)
    }

    @discardableResult
    private func insertItem(
        _ title: String,
        list: ListKind = .morning,
        rule: RepeatRule = .daily,
        start: String = "2026-10-01",
        limit: BumpLimit = .unlimited,
        sortOrder: Int = 0
    ) throws -> Item {
        let item = Item(list: list, title: title, sortOrder: sortOrder, repeatRule: rule, startDayKey: start, defaultBumpLimit: limit)
        context.insert(item)
        try context.save()
        return item
    }

    private func ensure(_ key: String) throws {
        _ = try ListService.ensureOccurrences(on: key, context: context, now: noon(key), calendar: munich)
    }

    private func rows(on key: String, list: ListKind = .morning) throws -> [Occurrence] {
        try ListService.occurrences(on: key, list: list, context: context)
    }

    // MARK: - Skip and undo skip

    func testUnskipReopensASkippedOccurrenceAndItCountsAgain() throws {
        try insertItem("Water", sortOrder: 0)
        try insertItem("Outside", sortOrder: 1)
        try ensure("2026-10-14")
        let day = try rows(on: "2026-10-14")
        try ListService.complete(day[0], at: noon("2026-10-14"), context: context)

        XCTAssertFalse(try ListService.unskip(day[1], todayKey: "2026-10-14", context: context), "an open row has no skip to undo")
        XCTAssertTrue(try ListService.skip(day[1], todayKey: "2026-10-14", context: context))
        XCTAssertEqual(ListRules.completion(try rows(on: "2026-10-14")).value, 1, "skipped drops out of the count")

        XCTAssertTrue(try ListService.unskip(day[1], todayKey: "2026-10-14", context: context))
        XCTAssertEqual(day[1].state, .open)
        XCTAssertNil(day[1].completedAt)
        XCTAssertEqual(ListRules.completion(try rows(on: "2026-10-14")).value, 0.5, "it counts again")
        XCTAssertFalse(try ListService.unskip(day[0], todayKey: "2026-10-14", context: context), "a done row isn't touched")
        XCTAssertEqual(day[0].state, .done)
    }

    // MARK: - Editing an item

    func testUpdateItemTitleOnlyRenamesWithoutASplit() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try ensure("2026-10-11")
        try ensure("2026-10-12")

        let result = try XCTUnwrap(ListService.updateItem(water, title: " Big water ", rule: .daily, bumpLimit: .unlimited,
                                                now: noon("2026-10-12"), calendar: munich, context: context))

        XCTAssertEqual(result.id, water.id)
        XCTAssertNil(water.endDayKey)
        XCTAssertEqual(water.title, "Big water")
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.title), ["Water"])
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.title), ["Big water"])
    }

    /// Today's occurrence still open: the split is today. The old item ends today, the new one
    /// starts today, and today's row belongs to the new item.
    func testUpdateItemRepeatSplitsFromTodayWhenTodayIsOpen() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try ensure("2026-10-11")
        try ensure("2026-10-12")
        try ListService.complete(try rows(on: "2026-10-11")[0], at: noon("2026-10-11"), context: context)

        let mondays = RepeatRule.weekly(on: [2])
        let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Water", rule: mondays, bumpLimit: .unlimited,
                                                     now: noon("2026-10-12"), calendar: munich, context: context))

        XCTAssertNotEqual(replacement.id, water.id)
        XCTAssertEqual(water.endDayKey, "2026-10-12")
        XCTAssertEqual(water.repeatRule, .daily, "the old item keeps its rule for the days it covered")
        XCTAssertEqual(replacement.startDayKey, "2026-10-12")
        XCTAssertEqual(replacement.repeatRule, mondays)
        XCTAssertEqual(replacement.sortOrder, water.sortOrder)

        let today = try rows(on: "2026-10-12")
        XCTAssertEqual(today.map(\.itemID), [replacement.id], "one row today, the new item's")
        XCTAssertEqual(today.first?.id, OccurrenceID.forItem(replacement.id, scheduledDayKey: "2026-10-12"))
        XCTAssertEqual(today.first?.periodEndDayKey, "2026-10-18")
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.itemID), [water.id], "past days keep the old item")
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.state), [.done])
        XCTAssertEqual(try ListService.currentItems(in: .morning, context: context).map(\.id), [replacement.id])

        try ensure("2026-10-13")
        XCTAssertTrue(try rows(on: "2026-10-13").isEmpty, "Tuesday isn't due under the new rule")
    }

    /// Today's occurrence already done: the split is tomorrow, and today keeps its done row.
    func testUpdateItemRepeatSplitsFromTomorrowWhenTodayIsDone() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try ensure("2026-10-12")
        let monday = try XCTUnwrap(rows(on: "2026-10-12").first)
        try ListService.complete(monday, at: noon("2026-10-12"), context: context)

        let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Water", rule: .weekdays, bumpLimit: .unlimited,
                                                     now: noon("2026-10-12"), calendar: munich, context: context))

        XCTAssertEqual(water.endDayKey, "2026-10-13")
        XCTAssertEqual(replacement.startDayKey, "2026-10-13")
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.itemID), [water.id])
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.state), [.done], "today's tick is untouched")

        try ensure("2026-10-12")
        XCTAssertEqual(try rows(on: "2026-10-12").count, 1, "the new item doesn't add a second row today")
        try ensure("2026-10-13")
        XCTAssertEqual(try rows(on: "2026-10-13").map(\.itemID), [replacement.id])
    }

    func testUpdateItemRepeatSplitsFromTomorrowWhenTodayIsSkipped() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try ensure("2026-10-12")
        try ListService.skip(try XCTUnwrap(rows(on: "2026-10-12").first), todayKey: "2026-10-12", context: context)

        let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Water", rule: .weekly(on: [2]), bumpLimit: .unlimited,
                                                     now: noon("2026-10-12"), calendar: munich, context: context))
        XCTAssertEqual(replacement.startDayKey, "2026-10-13")
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.state), [.skipped])
    }

    /// The streak through yesterday is the same before and after a repeat change.
    func testUpdateItemRepeatNeverRecountsPastDays() throws {
        let water = try insertItem("Water", start: "2026-10-09")
        for key in ["2026-10-09", "2026-10-10", "2026-10-11"] {
            try ensure(key)
            try ListService.complete(try rows(on: key)[0], at: TestCalendars.date(key, 8), context: context)
        }
        try ensure("2026-10-12")
        let cutoff = HomeModel.MorningMode.cutoff(time: DateComponents(hour: 9, minute: 0))
        func streak() throws -> HomeModel.StreakState {
            try ListService.streakState(for: .morning, through: "2026-10-12", morningMode: cutoff, context: context, calendar: munich)
        }
        let before = try streak()

        _ = try ListService.updateItem(water, title: "Water", rule: .everyNDays(2), bumpLimit: .unlimited,
                                       now: noon("2026-10-12"), calendar: munich, context: context)

        XCTAssertEqual(before, HomeModel.StreakState(count: 3, isFrozen: false))
        XCTAssertEqual(try streak(), before)
    }

    /// A copy bumped into today stays with the old item; the source day stays bumped.
    func testUpdateItemRepeatKeepsACopyBumpedIntoToday() throws {
        let gym = try insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        try ensure("2026-10-12")
        let monday = try XCTUnwrap(rows(on: "2026-10-12", list: .day).first)
        let tuesday = try XCTUnwrap(ListService.bump(monday, now: noon("2026-10-12"), calendar: munich, context: context))

        let replacement = try XCTUnwrap(ListService.updateItem(gym, title: "Gym", rule: .weekly(on: [5]), bumpLimit: .unlimited,
                                                     now: noon("2026-10-13"), calendar: munich, context: context))

        XCTAssertEqual(replacement.startDayKey, "2026-10-13")
        XCTAssertEqual(try rows(on: "2026-10-13", list: .day).map(\.id), [tuesday.id])
        XCTAssertEqual(tuesday.itemID, gym.id)
        XCTAssertEqual(monday.state, .bumped)
        XCTAssertEqual(monday.bumpedToID, tuesday.id)
    }

    /// Bump limit only: the item and today's open occurrence change; earlier days keep theirs.
    func testUpdateItemBumpLimitChangesTheItemAndTodaysOpenOccurrenceOnly() throws {
        let gym = try insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-05")
        try ensure("2026-10-05")
        try ensure("2026-10-12")

        let result = try XCTUnwrap(ListService.updateItem(gym, title: "Gym", rule: gym.repeatRule, bumpLimit: .upToDays(1),
                                                now: noon("2026-10-12"), calendar: munich, context: context))

        XCTAssertEqual(result.id, gym.id)
        XCTAssertNil(gym.endDayKey)
        XCTAssertEqual(gym.defaultBumpLimit, .upToDays(1))
        XCTAssertEqual(try rows(on: "2026-10-12", list: .day).first?.bumpLimit, .upToDays(1))
        XCTAssertEqual(try rows(on: "2026-10-05", list: .day).first?.bumpLimit, .unlimited)

        XCTAssertFalse(try ListService.updateItemBumpLimit(gym, to: .untilDeadline(dayKey: "2026-10-20"), todayKey: "2026-10-12", context: context),
                       "items carry no deadline")
        XCTAssertEqual(gym.defaultBumpLimit, .upToDays(1))
    }

    func testUpdateItemBumpLimitLeavesADoneOccurrenceAlone() throws {
        let gym = try insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        try ensure("2026-10-12")
        let row = try XCTUnwrap(rows(on: "2026-10-12", list: .day).first)
        try ListService.complete(row, at: noon("2026-10-12"), context: context)

        try ListService.updateItemBumpLimit(gym, to: .cantBump, todayKey: "2026-10-12", context: context)
        XCTAssertEqual(gym.defaultBumpLimit, .cantBump)
        XCTAssertEqual(row.bumpLimit, .unlimited)
    }

    func testItemLookupAndCurrentItems() throws {
        let water = try insertItem("Water", sortOrder: 0)
        let teeth = try insertItem("Teeth", sortOrder: 1)
        try ListService.deleteItem(teeth, todayKey: "2026-10-12", context: context)
        XCTAssertEqual(try ListService.item(id: water.id, context: context)?.title, "Water")
        XCTAssertNil(try ListService.item(id: UUID(), context: context))
        XCTAssertEqual(try ListService.currentItems(in: .morning, context: context).map(\.id), [water.id])
    }

    // MARK: - Ended items (review fixes)

    /// After a split, the old item has ended: editing, re-limiting or deleting it is refused and
    /// changes nothing (no second replacement, no later end day).
    func testEditingOrDeletingAnEndedItemIsRefused() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try ensure("2026-10-12")
        let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Water", rule: .weekly(on: [2]), bumpLimit: .unlimited,
                                                               now: noon("2026-10-12"), calendar: munich, context: context))
        XCTAssertEqual(water.endDayKey, "2026-10-12")

        XCTAssertNil(try ListService.updateItem(water, title: "Water", rule: .weekdays, bumpLimit: .unlimited,
                                                now: noon("2026-10-13"), calendar: munich, context: context))
        XCTAssertFalse(try ListService.updateItemBumpLimit(water, to: .cantBump, todayKey: "2026-10-13", context: context))
        XCTAssertFalse(try ListService.deleteItem(water, todayKey: "2026-10-14", context: context))

        XCTAssertEqual(water.endDayKey, "2026-10-12", "the end day never moves")
        XCTAssertEqual(water.repeatRule, .daily)
        XCTAssertEqual(water.defaultBumpLimit, .unlimited)
        XCTAssertEqual(try ListService.currentItems(in: .morning, context: context).map(\.id), [replacement.id], "no second replacement")
    }

    func testDeleteItemNeverExtendsAnEndDay() throws {
        let water = try insertItem("Water", start: "2026-10-01")
        XCTAssertTrue(try ListService.deleteItem(water, todayKey: "2026-10-12", context: context))
        XCTAssertEqual(water.endDayKey, "2026-10-12")
        XCTAssertFalse(try ListService.deleteItem(water, todayKey: "2026-10-20", context: context))
        XCTAssertEqual(water.endDayKey, "2026-10-12")

        let ended = Item(list: .morning, title: "Old", sortOrder: 1, repeatRule: .daily, startDayKey: "2026-09-01", endDayKey: "2026-09-10")
        context.insert(ended)
        try context.save()
        XCTAssertFalse(try ListService.deleteItem(ended, todayKey: "2026-10-12", context: context))
        XCTAssertEqual(ended.endDayKey, "2026-09-10", "deleting again would recount the days in between")
    }

    /// Home hides Edit… and Delete on rows whose item has ended.
    func testEndedItemIDsAmongRows() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try insertItem("Teeth", start: "2026-10-10", sortOrder: 1)
        try ensure("2026-10-12")
        try ListService.complete(try rows(on: "2026-10-12")[0], at: noon("2026-10-12"), context: context)
        let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Water", rule: .weekdays, bumpLimit: .unlimited,
                                                               now: noon("2026-10-12"), calendar: munich, context: context))
        let today = try rows(on: "2026-10-12")
        XCTAssertEqual(today.count, 2)
        XCTAssertEqual(try ListService.endedItemIDs(among: today, context: context), [water.id], "today's done row is the old item's")
        try ensure("2026-10-13")
        XCTAssertTrue(try ListService.endedItemIDs(among: try rows(on: "2026-10-13"), context: context).isEmpty)
        XCTAssertEqual(try rows(on: "2026-10-13").first?.itemID, replacement.id)
        XCTAssertTrue(try ListService.endedItemIDs(among: [], context: context).isEmpty)
    }

    /// A repeat change with today already done splits from tomorrow; the new title still applies
    /// from today, so today's done row takes it.
    func testRepeatChangeWithRenameRenamesTodaysDoneRow() throws {
        let water = try insertItem("Water", start: "2026-10-10")
        try ensure("2026-10-11")
        try ensure("2026-10-12")
        let monday = try XCTUnwrap(rows(on: "2026-10-12").first)
        try ListService.complete(monday, at: noon("2026-10-12"), context: context)

        let replacement = try XCTUnwrap(ListService.updateItem(water, title: "Big water", rule: .weekdays, bumpLimit: .unlimited,
                                                               now: noon("2026-10-12"), calendar: munich, context: context))
        XCTAssertEqual(replacement.startDayKey, "2026-10-13")
        XCTAssertEqual(replacement.title, "Big water")
        XCTAssertEqual(monday.title, "Big water")
        XCTAssertEqual(monday.state, .done)
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.title), ["Water"], "earlier days keep their title")
    }

    // MARK: - Rows on a past day (review fixes)

    /// A sheet or dialog left open past midnight can't change yesterday's row.
    func testPastRowsAreRefused() throws {
        try insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        try ensure("2026-10-12")
        let gym = try XCTUnwrap(rows(on: "2026-10-12", list: .day).first)
        let post = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-12", title: "Post", context: context))

        XCTAssertNil(try ListService.bump(gym, now: noon("2026-10-13"), calendar: munich, context: context))
        XCTAssertNil(try ListService.bump(post, now: noon("2026-10-13"), calendar: munich, context: context))
        XCTAssertFalse(try ListService.skip(gym, todayKey: "2026-10-13", context: context))
        XCTAssertEqual(gym.state, .open)
        XCTAssertFalse(try ListService.editOneOff(post, title: "Other", bumpLimit: .unlimited, deadlineDayKey: nil,
                                                  todayKey: "2026-10-13", context: context))
        XCTAssertEqual(post.title, "Post")
        XCTAssertEqual(post.bumpLimit, .upToDays(3))
        XCTAssertFalse(try ListService.deleteOneOff(post, todayKey: "2026-10-13", context: context))
        XCTAssertNotNil(try ListService.occurrence(id: post.id, context: context))

        XCTAssertTrue(try ListService.skip(gym, todayKey: "2026-10-12", context: context))
        XCTAssertFalse(try ListService.unskip(gym, todayKey: "2026-10-13", context: context))
        XCTAssertEqual(gym.state, .skipped)

        XCTAssertTrue(try ListService.deleteOneOff(post, todayKey: "2026-10-12", context: context), "on its own day it still works")
    }

    // MARK: - One-offs

    func testAddOneOffWithOptions() throws {
        var options = OneOffOptions()
        let plain = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Plain", options: options, context: context))
        XCTAssertEqual(plain.bumpLimit, .upToDays(3))
        XCTAssertNil(plain.deadlineDayKey)

        options.deadlineDayKey = "2026-10-20"
        let withDeadline = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Tax", options: options, context: context))
        XCTAssertEqual(withDeadline.bumpLimit, .upToDays(3), "a deadline alone keeps the default limit")
        XCTAssertEqual(withDeadline.deadlineDayKey, "2026-10-20")

        options.limitChoice = .untilDeadline
        let untilDeadline = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Visa", options: options, context: context))
        XCTAssertEqual(untilDeadline.bumpLimit, .untilDeadline(dayKey: "2026-10-20"))
        XCTAssertTrue(ListService.canBump(untilDeadline, calendar: munich))

        options.mustHappenToday = true
        let must = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Pay rent", options: options, context: context))
        XCTAssertEqual(must.bumpLimit, .cantBump)
        XCTAssertFalse(ListService.canBump(must, calendar: munich))

        XCTAssertNil(try ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: " ", options: OneOffOptions(), context: context))
    }

    /// Edit… on a one-off changes that row only, not the rows earlier in its bump chain.
    func testEditOneOffChangesThisRowOnly() throws {
        let first = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Call the bank", context: context))
        let moved = try XCTUnwrap(ListService.bump(first, now: noon("2026-10-14"), calendar: munich, context: context))

        XCTAssertTrue(try ListService.editOneOff(moved, title: " Call the bank re: card ", bumpLimit: .untilDeadline(dayKey: "2026-10-20"),
                                                 deadlineDayKey: nil, todayKey: "2026-10-15", context: context))
        XCTAssertEqual(moved.title, "Call the bank re: card")
        XCTAssertEqual(moved.bumpLimit, .untilDeadline(dayKey: "2026-10-20"))
        XCTAssertEqual(moved.deadlineDayKey, "2026-10-20")
        XCTAssertEqual(moved.bumpedFromID, first.id, "still linked")
        XCTAssertEqual(first.title, "Call the bank")
        XCTAssertEqual(first.bumpLimit, .upToDays(3))

        XCTAssertTrue(try ListService.editOneOff(moved, title: "", bumpLimit: .unlimited, deadlineDayKey: nil, todayKey: "2026-10-15", context: context))
        XCTAssertEqual(moved.title, "Call the bank re: card", "an empty title keeps the old one")
        XCTAssertEqual(moved.bumpLimit, .unlimited)
        XCTAssertNil(moved.deadlineDayKey, "no deadline clears it")

        XCTAssertTrue(try ListService.editOneOff(moved, title: "Bank", bumpLimit: .upToDays(3), deadlineDayKey: "2026-10-22", todayKey: "2026-10-15", context: context))
        XCTAssertEqual(moved.deadlineDayKey, "2026-10-22")
        XCTAssertEqual(moved.bumpLimit, .upToDays(3))
    }

    func testEditOneOffRefusesARepeatingRow() throws {
        try insertItem("Water")
        try ensure("2026-10-14")
        let water = try XCTUnwrap(rows(on: "2026-10-14").first)
        XCTAssertFalse(try ListService.editOneOff(water, title: "Other", bumpLimit: .cantBump, deadlineDayKey: nil, todayKey: "2026-10-14", context: context))
        XCTAssertEqual(water.title, "Water")
    }

    // MARK: - Bump marks

    /// The count covers exactly the days asked for (Home asks for the ring's seven), on all lists.
    func testBumpCountCoversExactlyTheGivenDaysAcrossLists() throws {
        func bumpOneOff(_ list: ListKind, _ key: String) throws {
            let row = try XCTUnwrap(ListService.addOneOff(list: list, dayKey: key, title: "Task \(key)", context: context))
            _ = try XCTUnwrap(ListService.bump(row, now: noon(key), calendar: munich, context: context))
        }
        try bumpOneOff(.day, "2026-10-11")
        try bumpOneOff(.day, "2026-10-12")
        try bumpOneOff(.evening, "2026-10-13")
        try bumpOneOff(.day, "2026-10-16")

        XCTAssertEqual(try ListService.bumpCount(from: "2026-10-08", through: "2026-10-14", context: context), 3,
                       "the ring's seven days to Wednesday: Sunday, Monday (day list), Tuesday (evening)")
        XCTAssertEqual(try ListService.bumpCount(from: "2026-10-12", through: "2026-10-14", context: context), 2)
        XCTAssertEqual(try ListService.bumpCount(from: "2026-10-13", through: "2026-10-19", context: context), 2, "Tuesday and Friday")
        XCTAssertEqual(try ListService.bumpCount(from: "2026-10-17", through: "2026-10-23", context: context), 0)
        XCTAssertEqual(try ListService.bumpedDayKeys(from: "2026-10-12", through: "2026-10-18", context: context),
                       ["2026-10-12", "2026-10-13", "2026-10-16"])
    }

    /// The bumped copy is open, so a chain of two bumps marks the two days it was bumped from.
    func testABumpChainMarksEachDayItWasBumpedFrom() throws {
        let first = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-12", title: "Post", context: context))
        let second = try XCTUnwrap(ListService.bump(first, now: noon("2026-10-12"), calendar: munich, context: context))
        _ = try XCTUnwrap(ListService.bump(second, now: noon("2026-10-13"), calendar: munich, context: context))
        XCTAssertEqual(try ListService.bumpedDayKeys(from: "2026-10-01", through: "2026-10-31", context: context), ["2026-10-12", "2026-10-13"])
        XCTAssertEqual(try ListService.bumpCount(from: "2026-10-08", through: "2026-10-14", context: context), 2)
    }

    func testBumpCostsNameTheRepeatPeriodAndTheLimit() throws {
        let oneOff = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Post", context: context))
        XCTAssertEqual(try ListService.bumpCosts(for: oneOff, calendar: munich, context: context), [.bumpsUsed(used: 0, limit: 3)])

        try insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12", limit: .upToDays(2))
        try insertItem("Swim", list: .day, rule: .weekly(on: [2, 5]), start: "2026-10-12", sortOrder: 1)
        try ensure("2026-10-12")
        let monday = try rows(on: "2026-10-12", list: .day).filter { $0.isRepeating }
        XCTAssertEqual(monday.map(\.title), ["Gym", "Swim"])
        XCTAssertEqual(try ListService.bumpCosts(for: monday[0], calendar: munich, context: context), [
            .periodEnd(dayKey: "2026-10-18", period: "week", beforeNextDue: false),
            .bumpsUsed(used: 0, limit: 2),
        ])
        XCTAssertEqual(try ListService.bumpCosts(for: monday[1], calendar: munich, context: context), [
            .periodEnd(dayKey: "2026-10-14", period: "week", beforeNextDue: true),
        ], "Thursday's swim cuts Monday's window short; unlimited adds no line for a repeat")
    }
}
