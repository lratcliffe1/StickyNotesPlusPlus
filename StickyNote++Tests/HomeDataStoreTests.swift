import Foundation
import SwiftData
import XCTest

/// The legacy (V1) day-key fill-in that runs before the V2 backfill.
final class HomeDataStoreTests: XCTestCase {
    func testMigrationPopulatesMissingDayKeysAndSetsFlags() throws {
        let context = try makeInMemoryContext()
        let suite = "HomeDataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let day = Date(timeIntervalSince1970: 1_702_500_000)
        context.insert(MorningRoutineEntry(date: day, dayKey: "", titleSnapshot: "Entry"))
        context.insert(DailyTask(date: day, dayKey: "", title: "Task"))
        context.insert(DayRecord(date: day, dayKey: "", morningCompletion: 0, dailyCompletion: 0))
        try context.save()

        try HomeDataStore.migrateLegacyDayKeysIfNeeded(context: context, defaults: defaults)

        let entries = try context.fetch(FetchDescriptor<MorningRoutineEntry>())
        let tasks = try context.fetch(FetchDescriptor<DailyTask>())
        let records = try context.fetch(FetchDescriptor<DayRecord>())

        XCTAssertFalse(entries.first?.dayKey.isEmpty ?? true)
        XCTAssertFalse(tasks.first?.dayKey.isEmpty ?? true)
        XCTAssertFalse(records.first?.dayKey.isEmpty ?? true)
        XCTAssertTrue(defaults.bool(forKey: HomeDataStore.dayKeyMigrationCompletedDefaultsKey))
        XCTAssertTrue(defaults.bool(forKey: HomeDataStore.dailyTaskSortOrderMigrationCompletedDefaultsKey))
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = SharedPersistence.appSchema()
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
