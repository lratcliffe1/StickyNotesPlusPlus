import Foundation
import SwiftData
import os

/// Widget-facing task store. Every read and write goes through `ListService`, the same path the
/// app uses, so the widget and the app follow the same rules.
enum WidgetContextualList: String, Codable {
    case morning
    case daily
    case evening

    init(_ list: HomeModel.ContextualList) {
        switch list {
        case .morning: self = .morning
        case .daily: self = .daily
        case .evening: self = .evening
        }
    }

    var displayTitle: String {
        switch self {
        case .morning:
            return "Morning Routine"
        case .daily:
            return "Daily Tasks"
        case .evening:
            return "Evening Routine"
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
    /// Retype to bump is on: the bump button opens the app's bump sheet instead of bumping.
    var retypeToBump: Bool = AppSettings.defaultRetypeToBump
}

enum WidgetTaskStore {
    static let widgetKind = "TopTasksWidget"
    private static let container: ModelContainer? = try? SharedPersistence.makeContainer()
    static var makeContext: () throws -> ModelContext = {
        if let container = Self.container {
            return ModelContext(container)
        }
        return ModelContext(try SharedPersistence.makeContainer())
    }
    private static var defaults: UserDefaults { SharedPersistence.sharedDefaults }

    /// The top 3 open items of the list Home would show now (`HomeModel.automaticList`, by
    /// today's stored rules). Repeating items can be completed but not bumped here; one-offs can
    /// be bumped when their limit allows. Skipping stays in the app.
    static func snapshot(now: Date = Date()) -> WidgetTaskSnapshot {
        let calendar = Calendar.current
        let today = HomeModel.normalizedDay(now, calendar: calendar)
        let todayKey = HomeModel.dayKey(for: today, calendar: calendar)
        let store = defaults
        // Stores today's rules if the app hasn't yet (first read of the day wins).
        ListService.recordTodaysRules(now: now, calendar: calendar, defaults: store)
        let rules = DayRulesStore.resolvedHistory(in: store, todayKey: todayKey).rules(for: todayKey)
        let fallbackDate = rules.nextBoundary(after: now, calendar: calendar)

        do {
            let context = try makeContext()
            try ListService.prepare(context: context, now: now, calendar: calendar, defaults: store)

            let morning = try ListService.occurrences(on: todayKey, list: .morning, context: context)
            // Without bonus rows (added after the morning's cutoff), as on Home.
            let countedMorning = try ListService.countedRows(
                morning, history: DayRulesStore.resolvedHistory(in: store, todayKey: todayKey),
                context: context, calendar: calendar
            )
            // The evening is only read once it could show.
            let eveningStarted = rules.eveningStart(on: now, calendar: calendar).map { now >= $0 } ?? false
            let evening = try eveningStarted
                ? ListService.occurrences(on: todayKey, list: .evening, context: context)
                : []
            let list = WidgetContextualList(HomeModel.automaticList(
                for: today,
                now: now,
                rules: rules,
                morning: ListRules.completion(countedMorning),
                eveningIsEmpty: evening.isEmpty,
                calendar: calendar
            ))
            let rows: [Occurrence]
            switch list {
            case .morning: rows = morning
            case .evening: rows = evening
            case .daily: rows = try ListService.occurrences(on: todayKey, list: .day, context: context)
            }

            let items = rows
                .filter { $0.state == .open }
                .prefix(3)
                .map {
                    WidgetTaskItem(
                        id: $0.id,
                        title: $0.title,
                        list: list,
                        canBump: !$0.isRepeating && ListService.canBump($0, calendar: calendar)
                    )
                }

            return WidgetTaskSnapshot(
                date: now,
                list: list,
                items: Array(items),
                nextRefreshDate: fallbackDate,
                retypeToBump: AppSettings.retypeToBump(in: SharedPersistence.sharedDefaults)
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

    /// Completes one of today's open occurrences. `list` is kept for the intent's signature.
    static func completeTask(id: UUID, list: WidgetContextualList, now: Date = Date()) throws -> Bool {
        let calendar = Calendar.current
        let context = try makeContext()
        try ListService.prepare(context: context, now: now, calendar: calendar)

        guard let occurrence = try ListService.occurrence(id: id, context: context) else { return false }
        guard occurrence.dayKey == HomeModel.dayKey(for: now, calendar: calendar) else { return false }
        guard occurrence.state == .open else { return false }
        return try ListService.complete(occurrence, at: now, context: context)
    }

    /// Bumps one of today's one-offs to tomorrow, if its bump limit allows. Only with Retype to bump
    /// off: with it on, the widget opens the app's bump sheet instead (`BumpDeepLink`).
    static func bumpTask(id: UUID, list: WidgetContextualList, now: Date = Date()) throws -> Bool {
        guard !AppSettings.retypeToBump(in: SharedPersistence.sharedDefaults) else { return false }
        let calendar = Calendar.current
        let context = try makeContext()
        try ListService.prepare(context: context, now: now, calendar: calendar)

        guard let occurrence = try ListService.occurrence(id: id, context: context) else { return false }
        guard occurrence.dayKey == HomeModel.dayKey(for: now, calendar: calendar) else { return false }
        guard !occurrence.isRepeating else { return false }
        return try ListService.bump(occurrence, now: now, calendar: calendar, context: context) != nil
    }
}
