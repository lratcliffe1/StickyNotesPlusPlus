import Foundation
import SwiftData
import XCTest

/// The shared write service on an in-memory V2 store, Monday-first Munich calendar.
/// 12.10.2026 is a Monday; 14.10.2026 a Wednesday.
final class ListServiceTests: XCTestCase {
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
        end: String? = nil,
        sortOrder: Int = 0
    ) -> Item {
        let item = Item(list: list, title: title, sortOrder: sortOrder, repeatRule: rule, startDayKey: start, endDayKey: end)
        context.insert(item)
        return item
    }

    private func ensure(_ key: String) throws -> Bool {
        try ListService.ensureOccurrences(on: key, context: context, now: noon(key), calendar: munich)
    }

    private func rows(on key: String, list: ListKind = .morning) throws -> [Occurrence] {
        try ListService.occurrences(on: key, list: list, context: context)
    }

    // MARK: - Ensuring today's occurrences

    func testEnsureCreatesDueOccurrencesOnceAndIsIdempotent() throws {
        let daily = insertItem("Water", sortOrder: 0)
        let weekly = insertItem("Gym", rule: .weekly(on: [4]), sortOrder: 1)

        XCTAssertTrue(try ensure("2026-10-14"))
        XCTAssertFalse(try ensure("2026-10-14"), "a second call changes nothing")
        let wednesday = try rows(on: "2026-10-14")
        XCTAssertEqual(wednesday.map(\.itemID), [daily.id, weekly.id])
        XCTAssertEqual(wednesday.map(\.scheduledDayKey), ["2026-10-14", "2026-10-14"])
        XCTAssertEqual(wednesday.map(\.periodEndDayKey), ["2026-10-14", "2026-10-18"])
        XCTAssertEqual(wednesday.map(\.state), [.open, .open])

        _ = try ensure("2026-10-15")
        XCTAssertEqual(try rows(on: "2026-10-15").map(\.title), ["Water"], "the weekly item isn't due on Thursday")
    }

    func testEnsureDedupesAndKeepsTheDoneRow() throws {
        let item = insertItem("Water")
        let open = Occurrence(itemID: item.id, list: .morning, dayKey: "2026-10-14", title: "Water", createdAt: noon("2026-10-13"),
                              scheduledDayKey: "2026-10-14", periodEndDayKey: "2026-10-14")
        let done = Occurrence(itemID: item.id, list: .morning, dayKey: "2026-10-14", title: "Water", state: .done,
                              completedAt: noon("2026-10-14"), createdAt: noon("2026-10-14"),
                              scheduledDayKey: "2026-10-14", periodEndDayKey: "2026-10-14")
        context.insert(open)
        context.insert(done)
        try context.save()

        XCTAssertTrue(try ensure("2026-10-14"))
        let left = try rows(on: "2026-10-14")
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.id, done.id)
        XCTAssertEqual(left.first?.state, .done)
    }

    func testEnsureSkipsItemsOutsideTheirLife() throws {
        insertItem("Ended", end: "2026-10-14")
        insertItem("Not yet", start: "2026-10-15")
        _ = try ensure("2026-10-14")
        XCTAssertTrue(try rows(on: "2026-10-14").isEmpty)
    }

    // MARK: - Bumping

    func testBumpLinksBothWaysAndKeepsTheChainsFirstAddedDay() throws {
        let first = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Call the bank", now: noon("2026-10-14"), context: context))
        XCTAssertEqual(first.bumpLimit, .upToDays(3))

        let second = try XCTUnwrap(ListService.bump(first, newTitle: "  Call the bank today ", now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(first.state, .bumped)
        XCTAssertEqual(first.bumpedToID, second.id)
        XCTAssertNotNil(first.completedAt)
        XCTAssertEqual(second.bumpedFromID, first.id)
        XCTAssertEqual(second.dayKey, "2026-10-15")
        XCTAssertEqual(second.title, "Call the bank today")
        XCTAssertEqual(second.bumpCount, 1)
        XCTAssertEqual(second.state, .open)
        XCTAssertEqual(second.firstAddedDayKey, "2026-10-14")
        XCTAssertEqual(second.firstAddedTitle, "Call the bank")
        XCTAssertNil(second.itemID)

        let third = try XCTUnwrap(ListService.bump(second, now: noon("2026-10-15"), calendar: munich, context: context))
        let fourth = try XCTUnwrap(ListService.bump(third, now: noon("2026-10-16"), calendar: munich, context: context))
        XCTAssertEqual(fourth.bumpCount, 3)
        XCTAssertEqual(fourth.firstAddedDayKey, "2026-10-14")
        XCTAssertEqual(fourth.title, "Call the bank today", "no new title keeps the current one")
        XCTAssertNil(try ListService.bump(fourth, now: noon("2026-10-17"), calendar: munich, context: context), "up to 3 days")
        XCTAssertEqual(fourth.state, .open)
    }

    func testDailyRepeatCannotBeBumped() throws {
        insertItem("Water")
        _ = try ensure("2026-10-14")
        let water = try XCTUnwrap(rows(on: "2026-10-14").first)
        XCTAssertFalse(ListService.canBump(water, calendar: munich))
        XCTAssertNil(try ListService.bump(water, now: noon("2026-10-14"), calendar: munich, context: context))
    }

    /// A weekly item bumped from Wednesday stays the same item, and next Wednesday's occurrence
    /// still comes as scheduled.
    func testBumpedRepeatKeepsItsItemAndTheNextScheduledOccurrenceIsUnaffected() throws {
        let gym = insertItem("Gym", list: .day, rule: .weekly(on: []), start: "2026-10-14")
        _ = try ensure("2026-10-14")
        let wednesday = try XCTUnwrap(rows(on: "2026-10-14", list: .day).first)
        let thursday = try XCTUnwrap(ListService.bump(wednesday, now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(thursday.itemID, gym.id)
        XCTAssertEqual(thursday.scheduledDayKey, "2026-10-14")
        XCTAssertEqual(thursday.periodEndDayKey, "2026-10-18")

        XCTAssertFalse(try ensure("2026-10-15"), "the bumped-in copy doesn't make Thursday a scheduled day")
        XCTAssertEqual(try rows(on: "2026-10-15", list: .day).count, 1)

        _ = try ensure("2026-10-21")
        let next = try rows(on: "2026-10-21", list: .day)
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next.first?.bumpCount, 0)
        XCTAssertEqual(next.first?.scheduledDayKey, "2026-10-21")
    }

    func testUncompletingABumpRemovesTheNextDaysCopy() throws {
        let task = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Post", context: context))
        let moved = try XCTUnwrap(ListService.bump(task, now: noon("2026-10-14"), calendar: munich, context: context))
        let movedID = moved.id

        XCTAssertTrue(try ListService.uncomplete(task, context: context))
        XCTAssertEqual(task.state, .open)
        XCTAssertNil(task.bumpedToID)
        XCTAssertNil(try ListService.occurrence(id: movedID, context: context))
    }

    // MARK: - One-offs

    func testAddOneOffTrimsDefaultsAndKeepsCreationOrder() throws {
        XCTAssertNil(try ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "   ", context: context))
        let first = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: " First ", context: context))
        let second = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Second", context: context))
        let must = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Must", bumpLimit: .cantBump, context: context))
        let future = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-12-01", title: "Later", context: context))

        XCTAssertEqual(first.title, "First")
        XCTAssertEqual(first.bumpLimit, .upToDays(3))
        XCTAssertEqual(second.sortOrder, first.sortOrder + 1)
        XCTAssertEqual(future.dayKey, "2026-12-01")
        XCTAssertEqual(try rows(on: "2026-10-14", list: .day).map(\.id), [must.id, first.id, second.id])
    }

    func testOrderPutsItemsFirst() throws {
        insertItem("Water", list: .day, sortOrder: 1)
        insertItem("Teeth", list: .day, sortOrder: 0)
        _ = try ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Errand", context: context)
        _ = try ensure("2026-10-14")
        XCTAssertEqual(try rows(on: "2026-10-14", list: .day).map(\.title), ["Teeth", "Water", "Errand"])
    }

    func testSkipDropsOutOfTheCount() throws {
        insertItem("Water", sortOrder: 0)
        insertItem("Outside", sortOrder: 1)
        _ = try ensure("2026-10-14")
        let day = try rows(on: "2026-10-14")
        XCTAssertTrue(try ListService.complete(day[0], at: noon("2026-10-14"), context: context))
        XCTAssertTrue(try ListService.skip(day[1], context: context))
        XCTAssertEqual(ListRules.completion(try rows(on: "2026-10-14")), HomeModel.CompletionState(value: 1, isNeutral: false))
    }

    // MARK: - Items

    func testAddItemExistsFromTodayAndAppearsTodayIfDue() throws {
        let water = try XCTUnwrap(ListService.addItem(list: .morning, title: "Water", rule: .daily, now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(water.startDayKey, "2026-10-14")
        XCTAssertEqual(try rows(on: "2026-10-14").map(\.itemID), [water.id])

        let monday = try XCTUnwrap(ListService.addItem(list: .morning, title: "Plan", rule: .weekly(on: [2]), now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(monday.sortOrder, 1)
        XCTAssertEqual(try rows(on: "2026-10-14").count, 1, "not due on a Wednesday")
    }

    func testRenameAppliesFromToday() throws {
        let item = insertItem("Water", start: "2026-10-10")
        _ = try ensure("2026-10-11")
        _ = try ensure("2026-10-12")

        try ListService.renameItem(item, to: "Big glass of water", todayKey: "2026-10-12", context: context)

        XCTAssertEqual(item.title, "Big glass of water")
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.title), ["Water"], "past days keep their title")
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.title), ["Big glass of water"])
        XCTAssertEqual(try rows(on: "2026-10-12").first?.itemID, item.id, "still the same item: ticks survive a rename")
    }

    func testDeleteStopsTheItemFromToday() throws {
        let water = insertItem("Water", start: "2026-10-10", sortOrder: 0)
        let teeth = insertItem("Teeth", start: "2026-10-10", sortOrder: 1)
        _ = try ensure("2026-10-11")
        _ = try ensure("2026-10-12")
        try ListService.complete(try rows(on: "2026-10-11")[0], at: noon("2026-10-11"), context: context)

        try ListService.deleteItem(water, todayKey: "2026-10-12", context: context)

        XCTAssertEqual(water.endDayKey, "2026-10-12")
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.title), ["Water", "Teeth"], "earlier days keep it")
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.title), ["Teeth"], "today's open occurrence is removed")
        XCTAssertEqual(teeth.sortOrder, 0, "the list closes up")
        _ = try ensure("2026-10-12")
        _ = try ensure("2026-10-13")
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.title), ["Teeth"], "not recreated")
        XCTAssertEqual(try rows(on: "2026-10-13").map(\.title), ["Teeth"])
    }

    func testDeleteKeepsTodaysOccurrenceIfDone() throws {
        let water = insertItem("Water", start: "2026-10-10")
        _ = try ensure("2026-10-12")
        try ListService.complete(try rows(on: "2026-10-12")[0], at: noon("2026-10-12"), context: context)
        try ListService.deleteItem(water, todayKey: "2026-10-12", context: context)
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.state), [.done])
    }

    func testReorderItemsAppliesFromToday() throws {
        let water = insertItem("Water", start: "2026-10-10", sortOrder: 0)
        let teeth = insertItem("Teeth", start: "2026-10-10", sortOrder: 1)
        _ = try ensure("2026-10-11")
        _ = try ensure("2026-10-12")
        try ListService.reorderItems([teeth, water], todayKey: "2026-10-12", context: context)
        XCTAssertEqual(try rows(on: "2026-10-12").map(\.title), ["Teeth", "Water"])
        XCTAssertEqual(try rows(on: "2026-10-11").map(\.title), ["Water", "Teeth"])
    }

    // MARK: - Streaks through the store

    func testEachListHasItsOwnStreak() throws {
        let cutoff = HomeModel.MorningMode.cutoff(time: DateComponents(hour: 9, minute: 0))
        for key in ["2026-10-10", "2026-10-11"] {
            context.insert(Occurrence(list: .morning, dayKey: key, title: "Water", state: .done, completedAt: TestCalendars.date(key, 8)))
        }
        context.insert(Occurrence(list: .evening, dayKey: "2026-10-10", title: "Read", state: .open))
        context.insert(Occurrence(list: .evening, dayKey: "2026-10-11", title: "Read", state: .done, completedAt: TestCalendars.date("2026-10-11", 22)))
        try context.save()

        func streak(_ list: ListKind) throws -> HomeModel.StreakState {
            try ListService.streakState(for: list, through: "2026-10-12", morningMode: cutoff, context: context, calendar: munich)
        }
        XCTAssertEqual(try streak(.morning), HomeModel.StreakState(count: 2, isFrozen: false))
        XCTAssertEqual(try streak(.evening), HomeModel.StreakState(count: 1, isFrozen: false))
        XCTAssertEqual(try streak(.day), HomeModel.StreakState(count: 0, isFrozen: false), "an empty list is neutral")
    }

    func testMorningCutoffAppliesOnlyToTheMorningList() throws {
        let cutoff = HomeModel.MorningMode.cutoff(time: DateComponents(hour: 9, minute: 0))
        context.insert(Occurrence(list: .morning, dayKey: "2026-10-11", title: "Water", state: .done, completedAt: TestCalendars.date("2026-10-11", 10)))
        context.insert(Occurrence(list: .day, dayKey: "2026-10-11", title: "Post", state: .done, completedAt: TestCalendars.date("2026-10-11", 23, 30)))
        try context.save()

        let morning = try ListService.streakState(for: .morning, through: "2026-10-12", morningMode: cutoff, context: context, calendar: munich)
        let day = try ListService.streakState(for: .day, through: "2026-10-12", morningMode: cutoff, context: context, calendar: munich)
        XCTAssertEqual(morning.count, 0)
        XCTAssertEqual(day.count, 1)
    }
}
