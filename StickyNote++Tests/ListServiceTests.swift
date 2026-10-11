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

    func testItemOccurrenceIdIsDerivedFromItemAndScheduledDay() throws {
        let water = insertItem("Water")
        _ = try ensure("2026-10-14")
        let row = try XCTUnwrap(rows(on: "2026-10-14").first)
        XCTAssertEqual(row.id, OccurrenceID.forItem(water.id, scheduledDayKey: "2026-10-14"))
        XCTAssertNotEqual(row.id, OccurrenceID.forItem(water.id, scheduledDayKey: "2026-10-15"))
        XCTAssertEqual(OccurrenceID.forItem(water.id, scheduledDayKey: "2026-10-14"), OccurrenceID.forItem(water.id, scheduledDayKey: "2026-10-14"))
    }

    // MARK: - Two processes (two containers on one store file)

    private func onDiskContainers() throws -> (ModelContainer, ModelContainer, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ListServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Shared.store")
        let schema = SharedPersistence.appSchema()
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: StickyNotesMigrationPlan.self,
                               configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        return (try open(), try open(), directory)
    }

    /// The widget materialising today after the app did (and after a tick) changes nothing.
    func testSecondMaterialiseInAnotherProcessKeepsTheTick() throws {
        let (app, widget, directory) = try onDiskContainers()
        defer { try? FileManager.default.removeItem(at: directory) }
        let appContext = ModelContext(app)
        appContext.insert(Item(list: .morning, title: "Water", sortOrder: 0, repeatRule: .daily, startDayKey: "2026-10-01"))
        try appContext.save()
        _ = try ListService.ensureOccurrences(on: "2026-10-14", context: appContext, now: noon("2026-10-14"), calendar: munich)
        let row = try XCTUnwrap(ListService.occurrences(on: "2026-10-14", list: .morning, context: appContext).first)
        try ListService.complete(row, at: noon("2026-10-14"), context: appContext)

        let widgetContext = ModelContext(widget)
        XCTAssertFalse(try ListService.ensureOccurrences(on: "2026-10-14", context: widgetContext, now: noon("2026-10-14"), calendar: munich))

        let rows = try ListService.occurrences(on: "2026-10-14", list: .morning, context: ModelContext(app))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.state, .done)
    }

    /// Both processes create today's row before either has seen the other's: same id, so one row.
    func testSimultaneousCreatesLeaveOneRow() throws {
        let (app, widget, directory) = try onDiskContainers()
        defer { try? FileManager.default.removeItem(at: directory) }
        let setup = ModelContext(app)
        setup.insert(Item(list: .morning, title: "Water", sortOrder: 0, repeatRule: .daily, startDayKey: "2026-10-01"))
        try setup.save()

        let appContext = ModelContext(app)
        let widgetContext = ModelContext(widget)
        for context in [appContext, widgetContext] {
            let item = try XCTUnwrap(context.fetch(FetchDescriptor<Item>()).first)
            context.insert(ListService.makeOccurrence(for: item, scheduledOn: "2026-10-14", on: "2026-10-14", now: noon("2026-10-14"), calendar: munich))
        }
        try appContext.save()
        XCTAssertNoThrow(try widgetContext.save(), "a same-id insert from another process must not throw")

        XCTAssertEqual(try ListService.occurrences(on: "2026-10-14", list: .morning, context: ModelContext(app)).count, 1)
    }

    // MARK: - Less often than daily

    /// A weekly Monday item; the app is first opened on Wednesday.
    private func weeklyMondayOpenedWednesday() throws -> Occurrence {
        insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        _ = try ListService.addOneOff(list: .day, dayKey: "2026-10-11", title: "Post", context: context)
        try ListService.complete(try rows(on: "2026-10-11", list: .day)[0], at: noon("2026-10-11"), context: context)
        XCTAssertTrue(try ensure("2026-10-14"))
        return try XCTUnwrap(rows(on: "2026-10-14", list: .day).first)
    }

    private func dayStreak(through key: String) throws -> HomeModel.StreakState {
        try ListService.streakState(for: .day, through: key, morningMode: .cutoff(time: DateComponents(hour: 9, minute: 0)), context: context, calendar: munich)
    }

    func testUnopenedWeeklyOccurrenceAppearsLaterInItsPeriod() throws {
        let gym = try weeklyMondayOpenedWednesday()
        XCTAssertEqual(gym.title, "Gym")
        XCTAssertEqual(gym.scheduledDayKey, "2026-10-12")
        XCTAssertEqual(gym.periodEndDayKey, "2026-10-18")
        XCTAssertEqual(gym.id, OccurrenceID.forItem(try XCTUnwrap(gym.itemID), scheduledDayKey: "2026-10-12"))
        XCTAssertTrue(ListService.canBump(gym, calendar: munich))
        XCTAssertFalse(try ensure("2026-10-14"))
        XCTAssertFalse(try ensure("2026-10-15"), "not created twice in the same period")
        XCTAssertTrue(try rows(on: "2026-10-15", list: .day).isEmpty)
    }

    func testWeeklyOccurrenceDoneLaterInItsPeriodIsNoMiss() throws {
        let gym = try weeklyMondayOpenedWednesday()
        try ListService.complete(gym, at: noon("2026-10-14"), context: context)
        XCTAssertEqual(try dayStreak(through: "2026-10-19"), HomeModel.StreakState(count: 2, isFrozen: false))
        XCTAssertTrue(try ListService.unopenedMissDays(for: .day, before: "2026-10-19", context: context, calendar: munich).isEmpty)
    }

    func testWeeklyOccurrenceNotDoneBySundayIsAMissOnSundayOnly() throws {
        _ = try weeklyMondayOpenedWednesday()
        XCTAssertEqual(try dayStreak(through: "2026-10-18"), HomeModel.StreakState(count: 1, isFrozen: false))
        XCTAssertEqual(try dayStreak(through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: true))
    }

    func testOpenMondayRowIsAMissOnSundayNotMonday() throws {
        insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        _ = try ListService.addOneOff(list: .day, dayKey: "2026-10-11", title: "Post", context: context)
        try ListService.complete(try rows(on: "2026-10-11", list: .day)[0], at: noon("2026-10-11"), context: context)
        _ = try ensure("2026-10-12")
        XCTAssertFalse(try ensure("2026-10-14"), "Monday's row exists, so nothing is carried to Wednesday")
        XCTAssertEqual(try dayStreak(through: "2026-10-14"), HomeModel.StreakState(count: 1, isFrozen: false))
        XCTAssertEqual(try dayStreak(through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: true))
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

    func testDeadlineIsIndependentOfTheBumpLimit() throws {
        let task = try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: "2026-10-14", title: "Tax return",
                                                       bumpLimit: .upToDays(3), deadlineDayKey: "2026-10-20", context: context))
        XCTAssertEqual(task.bumpLimit, .upToDays(3))
        XCTAssertEqual(task.deadlineDayKey, "2026-10-20")

        task.bumpLimit = .unlimited
        XCTAssertEqual(task.deadlineDayKey, "2026-10-20", "changing the limit keeps the deadline")
        task.bumpLimit = .upToDays(3)

        let moved = try XCTUnwrap(ListService.bump(task, now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(moved.deadlineDayKey, "2026-10-20")
        XCTAssertEqual(moved.bumpLimit, .upToDays(3))

        moved.bumpLimit = .untilDeadline(dayKey: "2026-10-16")
        XCTAssertEqual(moved.deadlineDayKey, "2026-10-16", "the deadline limit sets the deadline")
        XCTAssertEqual(moved.bumpLimit, .untilDeadline(dayKey: "2026-10-16"))
        XCTAssertTrue(ListService.canBump(moved, calendar: munich))
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

    func testDeleteItemUndoesABumpIntoToday() throws {
        let gym = insertItem("Gym", list: .day, rule: .weekly(on: []), start: "2026-10-14")
        _ = try ensure("2026-10-14")
        let wednesday = try XCTUnwrap(rows(on: "2026-10-14", list: .day).first)
        _ = try XCTUnwrap(ListService.bump(wednesday, now: noon("2026-10-14"), calendar: munich, context: context))

        try ListService.deleteItem(gym, todayKey: "2026-10-15", context: context)

        XCTAssertTrue(try rows(on: "2026-10-15", list: .day).isEmpty)
        XCTAssertEqual(wednesday.state, .open, "as with deleteOneOff, the source day goes back to open")
        XCTAssertNil(wednesday.bumpedToID)
        XCTAssertNil(wednesday.completedAt)
    }

    /// Weekly item, Monday's row left open, deleted on Wednesday: no miss on Sunday.
    func testDeletingAWeeklyItemMidPeriodCostsNoMiss() throws {
        let gym = insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        _ = try ListService.addOneOff(list: .day, dayKey: "2026-10-11", title: "Post", context: context)
        try ListService.complete(try rows(on: "2026-10-11", list: .day)[0], at: noon("2026-10-11"), context: context)
        _ = try ensure("2026-10-12")
        XCTAssertEqual(try dayStreak(through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: true), "before the delete: Sunday is a miss")

        try ListService.deleteItem(gym, todayKey: "2026-10-14", context: context)
        XCTAssertEqual(try dayStreak(through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: false))
        let looks = try ListService.dayLooks(for: .day, through: "2026-10-19", todayKey: "2026-10-19",
                                             morningMode: .cutoff(time: DateComponents(hour: 9, minute: 0)), context: context, calendar: munich)
        XCTAssertNil(looks["2026-10-18"])
    }

    /// Same, when deleteItem reopens Monday's row by removing its bumped-in copy.
    func testDeletingAfterABumpReopensTheSourceButCostsNoMiss() throws {
        let gym = insertItem("Gym", list: .day, rule: .weekly(on: [2]), start: "2026-10-12")
        _ = try ListService.addOneOff(list: .day, dayKey: "2026-10-11", title: "Post", context: context)
        try ListService.complete(try rows(on: "2026-10-11", list: .day)[0], at: noon("2026-10-11"), context: context)
        _ = try ensure("2026-10-12")
        let monday = try XCTUnwrap(rows(on: "2026-10-12", list: .day).first { $0.itemID != nil })
        _ = try XCTUnwrap(ListService.bump(monday, now: noon("2026-10-12"), calendar: munich, context: context))

        try ListService.deleteItem(gym, todayKey: "2026-10-13", context: context)
        XCTAssertEqual(monday.state, .open)
        XCTAssertEqual(try dayStreak(through: "2026-10-19"), HomeModel.StreakState(count: 1, isFrozen: false))
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

    /// Not opening the app is a miss when something was due: here the morning on Sunday 11.10.
    func testUnopenedMorningWithItemsDueIsAMiss() throws {
        let cutoff = HomeModel.MorningMode.cutoff(time: DateComponents(hour: 9, minute: 0))
        insertItem("Water", start: "2026-10-10")
        context.insert(Occurrence(list: .morning, dayKey: "2026-10-10", title: "Water", state: .done, completedAt: TestCalendars.date("2026-10-10", 8)))
        try context.save()

        XCTAssertEqual(try ListService.unopenedMissDays(for: .morning, before: "2026-10-12", context: context, calendar: munich), ["2026-10-11"])
        let streak = try ListService.streakState(for: .morning, through: "2026-10-12", morningMode: cutoff, context: context, calendar: munich)
        XCTAssertEqual(streak, HomeModel.StreakState(count: 1, isFrozen: true))
        XCTAssertTrue(try ListService.unopenedMissDays(for: .day, before: "2026-10-12", context: context, calendar: munich).isEmpty,
                      "the day list has no items, so nothing was due on it")
    }

    func testDeletedItemDoesNotCountDaysAfterItsDeletion() throws {
        let cutoff = HomeModel.MorningMode.cutoff(time: DateComponents(hour: 9, minute: 0))
        let water = insertItem("Water", start: "2026-10-09")
        for key in ["2026-10-09", "2026-10-10"] {
            context.insert(Occurrence(itemID: water.id, list: .morning, dayKey: key, title: "Water", state: .done,
                                      completedAt: TestCalendars.date(key, 8), scheduledDayKey: key, periodEndDayKey: key))
        }
        try context.save()
        func streak() throws -> HomeModel.StreakState {
            try ListService.streakState(for: .morning, through: "2026-10-13", morningMode: cutoff, context: context, calendar: munich)
        }
        XCTAssertEqual(try streak(), HomeModel.StreakState(count: 0, isFrozen: false), "11 and 12 unopened with Water due")

        try ListService.deleteItem(water, todayKey: "2026-10-11", context: context)
        XCTAssertEqual(try streak(), HomeModel.StreakState(count: 2, isFrozen: false))
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
