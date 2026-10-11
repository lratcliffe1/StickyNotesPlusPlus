import Foundation
import SwiftData

/// Shared persistence workflows for Home + Widget.
/// Keep all fetch/migrate/reconcile/upsert rules here so behavior stays aligned across targets.
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

    static func fetchMorningEntries(for day: Date, context: ModelContext) throws -> [MorningRoutineEntry] {
        let key = dayKey(for: day)
        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
        )
        return try context.fetch(descriptor)
    }

    static func fetchDailyTasks(for day: Date, context: ModelContext) throws -> [DailyTask] {
        let key = dayKey(for: day)
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor)
    }

    static func fetchDailyTask(id: UUID, context: ModelContext) throws -> DailyTask? {
        let descriptor = FetchDescriptor<DailyTask>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    static func fetchDayRecord(for day: Date, context: ModelContext) throws -> DayRecord? {
        let key = dayKey(for: day)
        let descriptor = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.dayKey == key })
        return try context.fetch(descriptor).first
    }

    static func fetchTemplates(context: ModelContext) throws -> [MorningRoutineTemplateItem] {
        let descriptor = FetchDescriptor<MorningRoutineTemplateItem>(sortBy: [SortDescriptor(\.sortOrder)])
        return try context.fetch(descriptor)
    }

    static func fetchMorningEntries(from startDay: Date, through endDay: Date, context: ModelContext) throws -> [MorningRoutineEntry] {
        let startKey = dayKey(for: startDay)
        let endKey = dayKey(for: endDay)
        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.dayKey >= startKey && $0.dayKey <= endKey },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
        )
        return try context.fetch(descriptor)
    }

    static func fetchDailyTasks(from startDay: Date, through endDay: Date, context: ModelContext) throws -> [DailyTask] {
        let startKey = dayKey(for: startDay)
        let endKey = dayKey(for: endDay)
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.dayKey >= startKey && $0.dayKey <= endKey },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        return try context.fetch(descriptor)
    }

    static func nextSortOrder(for day: Date, insertAtTop: Bool, context: ModelContext) throws -> Int {
        let tasksForDay = try fetchDailyTasks(for: day, context: context)
        if insertAtTop {
            return (tasksForDay.map(\.sortOrder).min() ?? 0) - 1
        }
        return (tasksForDay.map(\.sortOrder).max() ?? -1) + 1
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

    @discardableResult
    static func reconcileMorningEntries(for day: Date, context: ModelContext) throws -> Bool {
        let normalizedDay = HomeModel.normalizedDay(day)
        let templates = try fetchTemplates(context: context)
        let existing = try fetchMorningEntries(for: normalizedDay, context: context)
        var didChange = false

        if templates.isEmpty {
            if !existing.isEmpty {
                for entry in existing {
                    context.delete(entry)
                }
                didChange = true
            }

            if didChange {
                try context.save()
            }
            return didChange
        }

        var unmatchedByTitle: [String: [MorningRoutineEntry]] = [:]
        for entry in existing {
            unmatchedByTitle[entry.titleSnapshot, default: []].append(entry)
        }

        for (title, entries) in unmatchedByTitle {
            unmatchedByTitle[title] = entries.sorted {
                if $0.sortOrderSnapshot != $1.sortOrderSnapshot {
                    return $0.sortOrderSnapshot < $1.sortOrderSnapshot
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }

        var keptEntryIDs: Set<UUID> = []

        for template in templates {
            if var bucket = unmatchedByTitle[template.title], let entry = bucket.first {
                bucket.removeFirst()
                unmatchedByTitle[template.title] = bucket
                keptEntryIDs.insert(entry.id)

                if entry.sortOrderSnapshot != template.sortOrder {
                    entry.sortOrderSnapshot = template.sortOrder
                    didChange = true
                }

                if entry.targetTimeSnapshot != template.targetTime {
                    entry.targetTimeSnapshot = template.targetTime
                    didChange = true
                }
            } else {
                let entry = MorningRoutineEntry(
                    date: normalizedDay,
                    titleSnapshot: template.title,
                    sortOrderSnapshot: template.sortOrder,
                    targetTimeSnapshot: template.targetTime
                )
                context.insert(entry)
                didChange = true
            }
        }

        for entry in existing where !keptEntryIDs.contains(entry.id) {
            context.delete(entry)
            didChange = true
        }

        if didChange {
            try context.save()
        }
        return didChange
    }

    @discardableResult
    static func upsertDayRecord(for day: Date, morningCompletion: Double, dailyCompletion: Double, context: ModelContext) throws -> Bool {
        let normalizedDay = HomeModel.normalizedDay(day)

        if let record = try fetchDayRecord(for: normalizedDay, context: context) {
            guard record.morningCompletion != morningCompletion || record.dailyCompletion != dailyCompletion else {
                return false
            }
            record.morningCompletion = morningCompletion
            record.dailyCompletion = dailyCompletion
        } else {
            let record = DayRecord(date: normalizedDay, morningCompletion: morningCompletion, dailyCompletion: dailyCompletion)
            context.insert(record)
        }

        try context.save()
        return true
    }
}
