import Foundation
import SwiftData
import XCTest

/// The one-time V1 → V2 copy: every V1 row maps correctly, the flag waits for the save, a second
/// run duplicates nothing, the V1 tables are left alone, and a V1 store on disk opens as V2.
final class V2BackfillTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let now = TestCalendars.date("2026-10-12", 12)

    private struct Seed {
        let water: MorningRoutineTemplateItem
        let teeth: MorningRoutineTemplateItem
        let waterEntry: MorningRoutineEntry
        let teethEntry: MorningRoutineEntry
        let oldEntry: MorningRoutineEntry
        let laterWaterEntry: MorningRoutineEntry
        let duplicateWaterEntry: MorningRoutineEntry
        let first: DailyTask
        let second: DailyTask
        let third: DailyTask
        let mustDo: DailyTask
    }

    private func day(_ key: String, _ hour: Int = 0) -> Date {
        TestCalendars.date(key, hour)
    }

    /// Two templates; routine entries on 9 and 10 October, one whose title matches no template and
    /// a second "Water" on the 10th; a task bumped twice (9 → 10 → 11) and a must-do task.
    @discardableResult
    private func seedV1(into context: ModelContext) throws -> Seed {
        let water = MorningRoutineTemplateItem(title: "Water", sortOrder: 0)
        let teeth = MorningRoutineTemplateItem(title: "Teeth", sortOrder: 1)
        let waterEntry = MorningRoutineEntry(date: day("2026-10-09"), dayKey: "2026-10-09", titleSnapshot: "Water",
                                             sortOrderSnapshot: 0, isCompleted: true, completedAt: day("2026-10-09", 7))
        let teethEntry = MorningRoutineEntry(date: day("2026-10-09"), dayKey: "2026-10-09", titleSnapshot: "Teeth",
                                             sortOrderSnapshot: 1, isCompleted: false)
        let oldEntry = MorningRoutineEntry(date: day("2026-10-09"), dayKey: "2026-10-09", titleSnapshot: "Cold shower",
                                           sortOrderSnapshot: 2, isCompleted: true, completedAt: day("2026-10-09", 8))
        let laterWaterEntry = MorningRoutineEntry(date: day("2026-10-10"), dayKey: "2026-10-10", titleSnapshot: "Water",
                                                  sortOrderSnapshot: 0, isCompleted: true, completedAt: day("2026-10-10", 7))
        let duplicateWaterEntry = MorningRoutineEntry(date: day("2026-10-10"), dayKey: "2026-10-10", titleSnapshot: "Water",
                                                      sortOrderSnapshot: 5, isCompleted: false)

        let third = DailyTask(date: day("2026-10-11"), dayKey: "2026-10-11", title: "Call the bank (again)", sortOrder: 0, bumpCount: 2)
        let second = DailyTask(date: day("2026-10-10"), dayKey: "2026-10-10", title: "Call the bank", isCompleted: true,
                               completedAt: day("2026-10-10", 20), sortOrder: 0, bumpCount: 1, bumpedTaskID: third.id)
        let first = DailyTask(date: day("2026-10-09"), dayKey: "2026-10-09", title: "Call bank", isCompleted: true,
                              completedAt: day("2026-10-09", 20), sortOrder: 0, bumpCount: 0, bumpedTaskID: second.id)
        let mustDo = DailyTask(date: day("2026-10-09"), dayKey: "2026-10-09", title: "Pay rent", isCompleted: true,
                               completedAt: day("2026-10-09", 9), sortOrder: 1, isBumpable: false)

        for model in [water, teeth] { context.insert(model) }
        for model in [waterEntry, teethEntry, oldEntry, laterWaterEntry, duplicateWaterEntry] { context.insert(model) }
        for model in [first, second, third, mustDo] { context.insert(model) }
        context.insert(DayRecord(date: day("2026-10-09"), dayKey: "2026-10-09", morningCompletion: 0.5, dailyCompletion: 1))
        try context.save()

        return Seed(water: water, teeth: teeth, waterEntry: waterEntry, teethEntry: teethEntry, oldEntry: oldEntry,
                    laterWaterEntry: laterWaterEntry, duplicateWaterEntry: duplicateWaterEntry,
                    first: first, second: second, third: third, mustDo: mustDo)
    }

    private func occurrence(_ id: UUID, in context: ModelContext) throws -> Occurrence {
        try XCTUnwrap(ListService.occurrence(id: id, context: context))
    }

    // MARK: - Mapping

    func testTemplatesBecomeDailyMorningItemsFromTheEarliestEntry() throws {
        let context = try StoreTestSupport.makeContext()
        let seed = try seedV1(into: context)
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        try context.save()

        let items = try StoreTestSupport.all(Item.self, in: context).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(items.map(\.id), [seed.water.id, seed.teeth.id])
        XCTAssertEqual(items.map(\.title), ["Water", "Teeth"])
        for item in items {
            XCTAssertEqual(item.list, .morning)
            XCTAssertEqual(item.repeatRule, .daily)
            XCTAssertEqual(item.startDayKey, "2026-10-09")
            XCTAssertNil(item.endDayKey)
        }
    }

    func testTemplatesWithoutEntriesStartToday() throws {
        let context = try StoreTestSupport.makeContext()
        context.insert(MorningRoutineTemplateItem(title: "Water", sortOrder: 0))
        try context.save()
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        XCTAssertEqual(try StoreTestSupport.all(Item.self, in: context).map(\.startDayKey), ["2026-10-12"])
    }

    func testRoutineEntriesLinkToTheirItemByTitleAndTheRestBecomeOneOffs() throws {
        let context = try StoreTestSupport.makeContext()
        let seed = try seedV1(into: context)
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        try context.save()

        let water = try occurrence(seed.waterEntry.id, in: context)
        XCTAssertEqual(water.itemID, seed.water.id)
        XCTAssertEqual(water.list, .morning)
        XCTAssertEqual(water.dayKey, "2026-10-09")
        XCTAssertEqual(water.state, .done)
        XCTAssertEqual(water.completedAt, seed.waterEntry.completedAt)
        XCTAssertEqual(water.scheduledDayKey, "2026-10-09")
        XCTAssertFalse(ListService.canBump(water, calendar: munich))

        let teeth = try occurrence(seed.teethEntry.id, in: context)
        XCTAssertEqual(teeth.itemID, seed.teeth.id)
        XCTAssertEqual(teeth.state, .open)
        XCTAssertNil(teeth.completedAt)

        let old = try occurrence(seed.oldEntry.id, in: context)
        XCTAssertNil(old.itemID, "no template has that title")
        XCTAssertEqual(old.list, .morning)
        XCTAssertEqual(old.state, .done)
        XCTAssertEqual(old.bumpLimit, .cantBump)

        XCTAssertEqual(try occurrence(seed.laterWaterEntry.id, in: context).itemID, seed.water.id)
        XCTAssertNil(try occurrence(seed.duplicateWaterEntry.id, in: context).itemID, "one entry per template per day")
    }

    func testDailyTasksBecomeOneOffsWithTheirBumpChains() throws {
        let context = try StoreTestSupport.makeContext()
        let seed = try seedV1(into: context)
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        try context.save()

        let first = try occurrence(seed.first.id, in: context)
        let second = try occurrence(seed.second.id, in: context)
        let third = try occurrence(seed.third.id, in: context)

        XCTAssertEqual([first.state, second.state, third.state], [.bumped, .bumped, .open])
        XCTAssertEqual(first.bumpedToID, second.id)
        XCTAssertEqual(second.bumpedFromID, first.id)
        XCTAssertEqual(second.bumpedToID, third.id)
        XCTAssertEqual(third.bumpedFromID, second.id)
        XCTAssertNil(first.bumpedFromID)
        XCTAssertNil(third.bumpedToID)
        XCTAssertEqual([first.bumpCount, second.bumpCount, third.bumpCount], [0, 1, 2])
        for task in [first, second, third] {
            XCTAssertEqual(task.list, .day)
            XCTAssertNil(task.itemID)
            XCTAssertEqual(task.bumpLimit, .unlimited, "V1 tasks keep their old behaviour")
            XCTAssertEqual(task.firstAddedDayKey, "2026-10-09")
            XCTAssertEqual(task.firstAddedTitle, "Call bank")
        }
        XCTAssertEqual(third.dayKey, "2026-10-11")
        XCTAssertEqual(third.title, "Call the bank (again)")
        XCTAssertEqual(first.completedAt, seed.first.completedAt)

        let mustDo = try occurrence(seed.mustDo.id, in: context)
        XCTAssertEqual(mustDo.bumpLimit, .cantBump)
        XCTAssertEqual(mustDo.state, .done)
        XCTAssertEqual(mustDo.sortOrder, 1)
    }

    /// The V1 meaning survives: 9 October's day list was complete (bumped counts as done).
    func testBackfilledHistoryKeepsItsStreak() throws {
        let context = try StoreTestSupport.makeContext()
        try seedV1(into: context)
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        try context.save()
        let streak = try ListService.streakState(
            for: .day, through: "2026-10-11",
            history: DayRulesHistory(), context: context, calendar: munich
        )
        XCTAssertEqual(streak, HomeModel.StreakState(count: 2, isFrozen: false))
    }

    // MARK: - Safety

    func testDayRecordsAndV1RowsAreLeftUntouched() throws {
        let context = try StoreTestSupport.makeContext()
        let seed = try seedV1(into: context)
        let (defaults, name) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: munich)

        XCTAssertEqual(try StoreTestSupport.all(MorningRoutineTemplateItem.self, in: context).count, 2)
        XCTAssertEqual(try StoreTestSupport.all(MorningRoutineEntry.self, in: context).count, 5)
        XCTAssertEqual(try StoreTestSupport.all(DailyTask.self, in: context).count, 4)
        XCTAssertEqual(try StoreTestSupport.all(DayRecord.self, in: context).count, 1)
        XCTAssertTrue(seed.first.isCompleted)
        XCTAssertEqual(seed.first.bumpedTaskID, seed.second.id)
        XCTAssertEqual(seed.teethEntry.isCompleted, false)
        XCTAssertEqual(try StoreTestSupport.all(Occurrence.self, in: context).count, 9, "5 entries + 4 tasks, no day records")
    }

    func testFlagIsSetOnlyAfterTheSaveSucceeds() throws {
        struct SaveFailed: Error {}
        let context = try StoreTestSupport.makeContext()
        try seedV1(into: context)
        let (defaults, name) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertThrowsError(
            try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: munich, save: { _ in throw SaveFailed() })
        )
        XCTAssertFalse(defaults.bool(forKey: V2Backfill.completedDefaultsKey))
        context.rollback()

        try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: munich)
        XCTAssertTrue(defaults.bool(forKey: V2Backfill.completedDefaultsKey))
        XCTAssertEqual(try StoreTestSupport.all(Occurrence.self, in: context).count, 9)
        XCTAssertEqual(try StoreTestSupport.all(Item.self, in: context).count, 2)
    }

    func testRunningTwiceCreatesNoDuplicates() throws {
        let context = try StoreTestSupport.makeContext()
        try seedV1(into: context)

        // Even ignoring the flag (the app and the widget racing), a second copy adds nothing.
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        try context.save()
        try V2Backfill.copyV1Rows(context: context, now: now, calendar: munich)
        try context.save()
        XCTAssertEqual(try StoreTestSupport.all(Occurrence.self, in: context).count, 9)
        XCTAssertEqual(try StoreTestSupport.all(Item.self, in: context).count, 2)

        let (defaults, name) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: munich)
        try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: munich)
        XCTAssertEqual(try StoreTestSupport.all(Occurrence.self, in: context).count, 9)
    }

    /// Today's routine entry was copied, so preparing today doesn't add a second row for it.
    func testPrepareAfterBackfillDoesNotDuplicateTodaysRoutine() throws {
        let context = try StoreTestSupport.makeContext()
        let template = MorningRoutineTemplateItem(title: "Water", sortOrder: 0)
        context.insert(template)
        context.insert(MorningRoutineEntry(date: day("2026-10-12"), dayKey: "2026-10-12", titleSnapshot: "Water",
                                           isCompleted: true, completedAt: day("2026-10-12", 7)))
        try context.save()
        let (defaults, name) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        try ListService.prepare(context: context, now: now, calendar: munich, defaults: defaults)
        try ListService.prepare(context: context, now: now, calendar: munich, defaults: defaults)

        let today = try ListService.occurrences(on: "2026-10-12", list: .morning, context: context)
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.state, .done)
        XCTAssertEqual(today.first?.itemID, template.id)
    }

    /// The app backfills and the user ticks a row; then the widget, which hadn't seen the flag yet,
    /// backfills too. Existing rows are never overwritten, so the tick survives.
    func testBackfillTwiceWithATickInBetweenKeepsTheTick() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V2BackfillRace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Shared.store")
        let schema = SharedPersistence.appSchema()
        func open() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: StickyNotesMigrationPlan.self,
                               configurations: [ModelConfiguration(schema: schema, url: url)])
        }

        let app = try open()
        let appContext = ModelContext(app)
        let seed = try seedV1(into: appContext)
        let (appDefaults, appName) = StoreTestSupport.makeDefaults()
        let (widgetDefaults, widgetName) = StoreTestSupport.makeDefaults()
        defer {
            appDefaults.removePersistentDomain(forName: appName)
            widgetDefaults.removePersistentDomain(forName: widgetName)
        }

        try V2Backfill.runIfNeeded(context: appContext, defaults: appDefaults, now: now, calendar: munich)
        let third = try occurrence(seed.third.id, in: appContext)
        XCTAssertTrue(try ListService.complete(third, at: now, context: appContext))

        let widgetContext = ModelContext(try open())
        try V2Backfill.runIfNeeded(context: widgetContext, defaults: widgetDefaults, now: now, calendar: munich)

        let check = ModelContext(try open())
        XCTAssertEqual(try ListService.occurrence(id: seed.third.id, context: check)?.state, .done)
        XCTAssertEqual(try StoreTestSupport.all(Occurrence.self, in: check).count, 9)
        XCTAssertEqual(try StoreTestSupport.all(Item.self, in: check).count, 2)
    }

    // MARK: - On disk

    /// A store written by the V1 app opens through the migration plan as V2 and backfills.
    func testV1StoreOnDiskOpensAsV2AndBackfills() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V2BackfillTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("V1.store")

        let templateID: UUID
        let taskID: UUID
        do {
            let v1 = Schema(versionedSchema: StickyNotesSchemaV1.self)
            let container = try ModelContainer(for: v1, configurations: [ModelConfiguration(schema: v1, url: storeURL)])
            let context = ModelContext(container)
            let template = MorningRoutineTemplateItem(title: "Water", sortOrder: 0)
            let task = DailyTask(date: day("2026-10-11"), dayKey: "2026-10-11", title: "Written by V1", isCompleted: true,
                                 completedAt: day("2026-10-11", 18))
            context.insert(template)
            context.insert(MorningRoutineEntry(date: day("2026-10-11"), dayKey: "2026-10-11", titleSnapshot: "Water",
                                               isCompleted: true, completedAt: day("2026-10-11", 7)))
            context.insert(task)
            try context.save()
            templateID = template.id
            taskID = task.id
        }

        let schema = SharedPersistence.appSchema()
        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: StickyNotesMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = ModelContext(reopened)
        let (defaults, name) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        try ListService.prepare(context: context, now: now, calendar: munich, defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: V2Backfill.completedDefaultsKey))
        XCTAssertEqual(try StoreTestSupport.all(Item.self, in: context).map(\.id), [templateID])
        XCTAssertEqual(try ListService.occurrence(id: taskID, context: context)?.state, .done)
        XCTAssertEqual(try ListService.occurrences(on: "2026-10-11", list: .morning, context: context).map(\.itemID), [templateID])
        XCTAssertEqual(try ListService.occurrences(on: "2026-10-12", list: .morning, context: context).map(\.title), ["Water"],
                       "today's routine is created from the item")
        XCTAssertEqual(try StoreTestSupport.all(DailyTask.self, in: context).map(\.title), ["Written by V1"])
    }
}
