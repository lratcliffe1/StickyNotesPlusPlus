import Foundation
import SwiftData

enum WidgetContextualList: String, Codable {
    case morning
    case daily

    var displayTitle: String {
        switch self {
        case .morning:
            return "Morning Routine"
        case .daily:
            return "Daily Tasks"
        }
    }
}

struct WidgetTaskItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let list: WidgetContextualList
}

struct WidgetTaskSnapshot {
    let date: Date
    let list: WidgetContextualList
    let items: [WidgetTaskItem]
    let nextRefreshDate: Date
}

enum WidgetTaskStore {
    static let widgetKind = "TopTasksWidget"

    static func snapshot(now: Date = Date()) -> WidgetTaskSnapshot {
        let calendar = Calendar.current
        let today = HomeModel.normalizedDay(now, calendar: calendar)
        let mode = currentMorningMode()
        let fallbackDate = nextRefreshDate(now: now, mode: mode, calendar: calendar)

        do {
            let context = try modelContext()
            try migrateLegacyDayKeysIfNeeded(context: context)
            try reconcileMorningEntries(for: today, context: context)

            let morningEntries = fetchMorningEntries(for: today, context: context)
            let dailyTasks = fetchDailyTasks(for: today, context: context)

            let shouldShowMorning = HomeModel.shouldShowMorningList(
                for: today,
                morningEntries: morningEntries,
                mode: mode,
                now: now,
                calendar: calendar
            )

            if shouldShowMorning {
                let items = morningEntries
                    .filter { !$0.isCompleted }
                    .prefix(3)
                    .map { WidgetTaskItem(id: $0.id, title: $0.titleSnapshot, list: .morning) }

                return WidgetTaskSnapshot(
                    date: now,
                    list: .morning,
                    items: Array(items),
                    nextRefreshDate: fallbackDate
                )
            }

            let items = dailyTasks
                .filter { !$0.isCompleted }
                .prefix(3)
                .map { WidgetTaskItem(id: $0.id, title: $0.title, list: .daily) }

            return WidgetTaskSnapshot(
                date: now,
                list: .daily,
                items: Array(items),
                nextRefreshDate: fallbackDate
            )
        } catch {
            print("WidgetTaskStore snapshot error:", error)
            return WidgetTaskSnapshot(
                date: now,
                list: .daily,
                items: [],
                nextRefreshDate: fallbackDate
            )
        }
    }

    static func completeTask(id: UUID, list: WidgetContextualList, now: Date = Date()) throws -> Bool {
        let context = try modelContext()
        try migrateLegacyDayKeysIfNeeded(context: context)
        let day = HomeModel.normalizedDay(now)
        let dayKey = HomeModel.dayKey(for: day)

        let didUpdate: Bool

        switch list {
        case .morning:
            let descriptor = FetchDescriptor<MorningRoutineEntry>(
                predicate: #Predicate { $0.id == id }
            )

            guard let entry = try context.fetch(descriptor).first else { return false }
            guard entry.dayKey == dayKey else { return false }
            guard !entry.isCompleted else { return false }

            entry.isCompleted = true
            entry.completedAt = now
            didUpdate = true

        case .daily:
            let descriptor = FetchDescriptor<DailyTask>(
                predicate: #Predicate { $0.id == id }
            )

            guard let task = try context.fetch(descriptor).first else { return false }
            guard task.dayKey == dayKey else { return false }
            guard !task.isCompleted else { return false }

            task.isCompleted = true
            task.completedAt = now
            didUpdate = true
        }

        guard didUpdate else { return false }

        updateDayRecord(for: day, context: context)
        try context.save()
        return true
    }

    private static func modelContext() throws -> ModelContext {
        let container = try SharedPersistence.makeContainer()
        return ModelContext(container)
    }

    private static func fetchMorningEntries(for day: Date, context: ModelContext) -> [MorningRoutineEntry] {
        let dayKey = dayKey(for: day)
        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchDailyTasks(for day: Date, context: ModelContext) -> [DailyTask] {
        let dayKey = dayKey(for: day)
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func fetchTemplates(context: ModelContext) -> [MorningRoutineTemplateItem] {
        let descriptor = FetchDescriptor<MorningRoutineTemplateItem>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func currentMorningMode() -> HomeModel.MorningMode {
        let defaults = SharedPersistence.sharedDefaults
        let modeRaw = defaults.string(forKey: AppSettings.morningModeKey) ?? AppSettings.defaultMorningMode.rawValue
        let isSinceWakeUpMode = modeRaw == AppSettings.MorningMode.sinceWakeUp.rawValue

        let cutoffMinutes = defaults.object(forKey: AppSettings.morningCutoffMinutesKey) as? Int ?? AppSettings.defaultMorningCutoffMinutes
        let wakeMinutes = defaults.object(forKey: AppSettings.wakeUpMinutesKey) as? Int ?? AppSettings.defaultWakeUpMinutes
        let duration = defaults.object(forKey: AppSettings.morningWindowDurationMinutesKey) as? Int ?? AppSettings.defaultMorningWindowDurationMinutes

        if isSinceWakeUpMode {
            return .sinceWakeUp(
                wakeUpTime: AppSettings.dateComponents(fromMinutes: wakeMinutes),
                durationMinutes: min(240, max(15, duration))
            )
        }

        return .cutoff(time: AppSettings.dateComponents(fromMinutes: cutoffMinutes))
    }

    private static func nextRefreshDate(now: Date, mode: HomeModel.MorningMode, calendar: Calendar) -> Date {
        let today = HomeModel.normalizedDay(now, calendar: calendar)
        let deadline = HomeModel.morningDeadline(for: today, mode: mode, calendar: calendar)

        if now < deadline {
            return deadline
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return now.addingTimeInterval(60 * 30)
        }

        return tomorrow
    }

    private static func updateDayRecord(for day: Date, context: ModelContext) {
        let morningState = HomeModel.morningCompletion(entries: fetchMorningEntries(for: day, context: context))
        let dailyState = HomeModel.dailyCompletion(tasks: fetchDailyTasks(for: day, context: context))
        let dayKey = dayKey(for: day)

        let descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )

        if let record = (try? context.fetch(descriptor))?.first {
            record.morningCompletion = morningState.value
            record.dailyCompletion = dailyState.value
        } else {
            let record = DayRecord(
                date: day,
                morningCompletion: morningState.value,
                dailyCompletion: dailyState.value
            )
            context.insert(record)
        }
    }

    private static func reconcileMorningEntries(for day: Date, context: ModelContext) throws {
        let templates = fetchTemplates(context: context)
        let existing = fetchMorningEntries(for: day, context: context)
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
            return
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
                    date: day,
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
    }

    private static func migrateLegacyDayKeysIfNeeded(context: ModelContext) throws {
        let defaults = SharedPersistence.sharedDefaults
        var didChange = false

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

            defaults.set(true, forKey: dayKeyMigrationCompletedDefaultsKey)
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

            defaults.set(true, forKey: dailyTaskSortOrderMigrationCompletedDefaultsKey)
        }

        if didChange {
            try context.save()
        }
    }

    private static func dayKey(for day: Date) -> String {
        HomeModel.dayKey(for: HomeModel.normalizedDay(day))
    }

    private static var dayKeyMigrationCompletedDefaultsKey: String {
        "stable_day_key_migration_completed_v1"
    }

    private static var dailyTaskSortOrderMigrationCompletedDefaultsKey: String {
        "daily_task_sort_order_migration_completed_v1"
    }
}
