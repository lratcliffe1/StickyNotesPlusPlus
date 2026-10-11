import Foundation
import SwiftData

/// Legacy (V1) store helpers. Since schema V2 the lists live in `Item` / `Occurrence` and are
/// read and written through `ListService`; the only V1 write left is the day-key fill-in below,
/// which `V2Backfill` runs once, before it copies the V1 rows across.
enum HomeDataStore {
    static let dayKeyMigrationCompletedDefaultsKey = "stable_day_key_migration_completed_v1"
    static let dailyTaskSortOrderMigrationCompletedDefaultsKey = "daily_task_sort_order_migration_completed_v1"

    static func dayFromStored(dayKey: String, fallbackDate: Date, calendar: Calendar = .current) -> Date {
        if !dayKey.isEmpty, let parsed = HomeModel.date(fromDayKey: dayKey, calendar: calendar) {
            return HomeModel.normalizedDay(parsed, calendar: calendar)
        }

        return HomeModel.normalizedDay(fallbackDate, calendar: calendar)
    }

    static func dayKey(for day: Date) -> String {
        HomeModel.dayKey(for: HomeModel.normalizedDay(day))
    }

    static func migrateLegacyDayKeysIfNeeded(context: ModelContext, defaults: UserDefaults = SharedPersistence.sharedDefaults) throws {
        var didChange = false
        // Flags are recorded only after the save succeeds, so a failed save retries next launch.
        var completedMigrationKeys: [String] = []

        if !defaults.bool(forKey: dayKeyMigrationCompletedDefaultsKey) {
            let morningEntries = try context.fetch(FetchDescriptor<MorningRoutineEntry>())
            for entry in morningEntries where entry.dayKey.isEmpty {
                entry.dayKey = HomeModel.dayKey(for: entry.date)
                didChange = true
            }

            let dailyTasks = try context.fetch(FetchDescriptor<DailyTask>())
            for task in dailyTasks where task.dayKey.isEmpty {
                task.dayKey = HomeModel.dayKey(for: task.date)
                didChange = true
            }

            let dayRecords = try context.fetch(FetchDescriptor<DayRecord>())
            for record in dayRecords where record.dayKey.isEmpty {
                record.dayKey = HomeModel.dayKey(for: record.date)
                didChange = true
            }

            completedMigrationKeys.append(dayKeyMigrationCompletedDefaultsKey)
        }

        if !defaults.bool(forKey: dailyTaskSortOrderMigrationCompletedDefaultsKey) {
            let descriptor = FetchDescriptor<DailyTask>(
                sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.date), SortDescriptor(\.title)]
            )
            let allTasks = try context.fetch(descriptor)
            var nextOrderByDay: [String: Int] = [:]

            for task in allTasks {
                let key = task.dayKey.isEmpty ? HomeModel.dayKey(for: task.date) : task.dayKey
                let next = nextOrderByDay[key, default: 0]
                if task.sortOrder != next {
                    task.sortOrder = next
                    didChange = true
                }
                nextOrderByDay[key] = next + 1
            }

            completedMigrationKeys.append(dailyTaskSortOrderMigrationCompletedDefaultsKey)
        }

        if didChange {
            try context.save()
        }
        for key in completedMigrationKeys {
            defaults.set(true, forKey: key)
        }
    }
}
