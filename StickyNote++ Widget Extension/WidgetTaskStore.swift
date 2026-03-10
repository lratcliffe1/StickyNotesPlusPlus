import Foundation
import SwiftData
import os

/// Widget-facing task store that reuses shared repository logic.
/// This keeps app/widget day-key, migration, and selection behavior in sync.
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
    let canBump: Bool
}

struct WidgetTaskSnapshot {
    let date: Date
    let list: WidgetContextualList
    let items: [WidgetTaskItem]
    let nextRefreshDate: Date
}

enum WidgetTaskStore {
    static let widgetKind = "TopTasksWidget"
    private static let container: ModelContainer? = try? SharedPersistence.makeContainer()
    private static var repository: HomeRepository = SwiftDataHomeRepository()
    static var makeContext: () throws -> ModelContext = {
        if let container = Self.container {
            return ModelContext(container)
        }
        return ModelContext(try SharedPersistence.makeContainer())
    }
    static var loadMorningMode: () -> HomeModel.MorningMode = {
        MorningModeProvider.load(from: SharedPersistence.sharedDefaults).mode
    }

    static func snapshot(now: Date = Date()) -> WidgetTaskSnapshot {
        let calendar = Calendar.current
        let today = HomeModel.normalizedDay(now, calendar: calendar)
        let mode = currentMorningMode()
        let fallbackDate = nextRefreshDate(now: now, mode: mode, calendar: calendar)

        do {
            let context = try makeContext()
            try repository.migrateLegacyDayKeysIfNeeded(context: context)
            try repository.reconcileMorningEntries(for: today, context: context)

            let morningEntries = try repository.fetchMorningEntries(for: today, context: context)
            let dailyTasks = try repository.fetchDailyTasks(for: today, context: context)

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
                    .map { WidgetTaskItem(id: $0.id, title: $0.titleSnapshot, list: .morning, canBump: false) }

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
                .map {
                    WidgetTaskItem(
                        id: $0.id,
                        title: $0.title,
                        list: .daily,
                        canBump: $0.isBumpable && $0.bumpedTaskID == nil
                    )
                }

            return WidgetTaskSnapshot(
                date: now,
                list: .daily,
                items: Array(items),
                nextRefreshDate: fallbackDate
            )
        } catch {
            AppLogger.widget.error("Widget snapshot failed: \(error.localizedDescription, privacy: .public)")
            return WidgetTaskSnapshot(
                date: now,
                list: .daily,
                items: [],
                nextRefreshDate: fallbackDate
            )
        }
    }

    static func completeTask(id: UUID, list: WidgetContextualList, now: Date = Date()) throws -> Bool {
        let context = try makeContext()
        try repository.migrateLegacyDayKeysIfNeeded(context: context)
        let day = HomeModel.normalizedDay(now)
        let currentDayKey = HomeDataStore.dayKey(for: day)

        let didUpdate: Bool

        switch list {
        case .morning:
            let descriptor = FetchDescriptor<MorningRoutineEntry>(
                predicate: #Predicate { $0.id == id }
            )

            guard let entry = try context.fetch(descriptor).first else { return false }
            guard entry.dayKey == currentDayKey else { return false }
            guard !entry.isCompleted else { return false }

            entry.isCompleted = true
            entry.completedAt = now
            didUpdate = true

        case .daily:
            let descriptor = FetchDescriptor<DailyTask>(
                predicate: #Predicate { $0.id == id }
            )

            guard let task = try context.fetch(descriptor).first else { return false }
            guard task.dayKey == currentDayKey else { return false }
            guard !task.isCompleted else { return false }

            task.isCompleted = true
            task.completedAt = now
            didUpdate = true
        }

        guard didUpdate else { return false }

        _ = try repository.upsertDayRecord(
            for: day,
            morningCompletion: HomeModel.morningCompletion(entries: try repository.fetchMorningEntries(for: day, context: context)).value,
            dailyCompletion: HomeModel.dailyCompletion(tasks: try repository.fetchDailyTasks(for: day, context: context)).value,
            context: context
        )
        try context.save()
        return true
    }

    static func bumpTask(id: UUID, list: WidgetContextualList, now: Date = Date()) throws -> Bool {
        guard list == .daily else { return false }

        let context = try makeContext()
        try repository.migrateLegacyDayKeysIfNeeded(context: context)
        let day = HomeModel.normalizedDay(now)
        let currentDayKey = HomeDataStore.dayKey(for: day)

        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.id == id }
        )

        guard let task = try context.fetch(descriptor).first else { return false }
        guard task.dayKey == currentDayKey else { return false }
        guard task.isBumpable, !task.isCompleted else { return false }
        guard task.bumpedTaskID == nil else { return false }

        let calendar = Calendar.current
        let taskDay = HomeModel.date(fromDayKey: task.dayKey, calendar: calendar)
            ?? HomeModel.normalizedDay(task.date, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: taskDay) ?? taskDay
        let tomorrowNormalized = HomeModel.normalizedDay(tomorrow, calendar: calendar)

        let bumpedTask = DailyTask(
            date: tomorrowNormalized,
            title: task.title,
            isCompleted: false,
            completedAt: nil,
            sortOrder: try repository.nextSortOrder(for: tomorrowNormalized, insertAtTop: false, context: context),
            bumpCount: task.bumpCount + 1,
            isBumpable: task.isBumpable
        )

        context.insert(bumpedTask)
        task.isCompleted = true
        task.completedAt = now
        task.bumpedTaskID = bumpedTask.id

        _ = try repository.upsertDayRecord(
            for: day,
            morningCompletion: HomeModel.morningCompletion(entries: try repository.fetchMorningEntries(for: day, context: context)).value,
            dailyCompletion: HomeModel.dailyCompletion(tasks: try repository.fetchDailyTasks(for: day, context: context)).value,
            context: context
        )
        try context.save()
        return true
    }

    private static func currentMorningMode() -> HomeModel.MorningMode {
        loadMorningMode()
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

    // Shared storage/migration logic is intentionally delegated to HomeDataStore.
}
