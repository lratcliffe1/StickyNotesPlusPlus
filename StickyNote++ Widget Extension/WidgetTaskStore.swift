import Foundation
import SwiftData
import os

/// Widget-facing task store. Every read and write goes through `ListService`, the same path the
/// app uses, so the widget and the app follow the same rules.
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
    static var makeContext: () throws -> ModelContext = {
        if let container = Self.container {
            return ModelContext(container)
        }
        return ModelContext(try SharedPersistence.makeContainer())
    }
    static var loadMorningMode: () -> HomeModel.MorningMode = {
        MorningModeProvider.load(from: SharedPersistence.sharedDefaults).mode
    }

    /// The top 3 open items of the list Home would show now. Repeating items can be completed
    /// but not bumped here; one-offs can be bumped when their limit allows. Skipping stays in the app.
    static func snapshot(now: Date = Date()) -> WidgetTaskSnapshot {
        let calendar = Calendar.current
        let today = HomeModel.normalizedDay(now, calendar: calendar)
        let todayKey = HomeModel.dayKey(for: today, calendar: calendar)
        let mode = currentMorningMode()
        let fallbackDate = nextRefreshDate(now: now, mode: mode, calendar: calendar)

        do {
            let context = try makeContext()
            try ListService.prepare(context: context, now: now, calendar: calendar)

            let morning = try ListService.occurrences(on: todayKey, list: .morning, context: context)
            let shouldShowMorning = HomeModel.shouldShowMorningList(
                for: today,
                morningCompletion: ListRules.completion(morning),
                mode: mode,
                now: now,
                calendar: calendar
            )
            let list: WidgetContextualList = shouldShowMorning ? .morning : .daily
            let rows = try shouldShowMorning
                ? morning
                : ListService.occurrences(on: todayKey, list: .day, context: context)

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

    /// Bumps one of today's one-offs to tomorrow, if its bump limit allows.
    static func bumpTask(id: UUID, list: WidgetContextualList, now: Date = Date()) throws -> Bool {
        let calendar = Calendar.current
        let context = try makeContext()
        try ListService.prepare(context: context, now: now, calendar: calendar)

        guard let occurrence = try ListService.occurrence(id: id, context: context) else { return false }
        guard occurrence.dayKey == HomeModel.dayKey(for: now, calendar: calendar) else { return false }
        guard !occurrence.isRepeating else { return false }
        return try ListService.bump(occurrence, now: now, calendar: calendar, context: context) != nil
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
}
