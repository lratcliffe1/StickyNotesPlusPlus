import Foundation
import SwiftData

/// Repository contract used by app and widget.
/// This isolates callers from concrete SwiftData implementation details.
protocol HomeRepository {
    func fetchMorningEntries(for day: Date, context: ModelContext) throws -> [MorningRoutineEntry]
    func fetchDailyTasks(for day: Date, context: ModelContext) throws -> [DailyTask]
    func fetchDailyTask(id: UUID, context: ModelContext) throws -> DailyTask?
    func fetchDayRecord(for day: Date, context: ModelContext) throws -> DayRecord?
    func fetchTemplates(context: ModelContext) throws -> [MorningRoutineTemplateItem]
    func fetchMorningEntries(from startDay: Date, through endDay: Date, context: ModelContext) throws -> [MorningRoutineEntry]
    func fetchDailyTasks(from startDay: Date, through endDay: Date, context: ModelContext) throws -> [DailyTask]
    func nextSortOrder(for day: Date, insertAtTop: Bool, context: ModelContext) throws -> Int
    func migrateLegacyDayKeysIfNeeded(context: ModelContext) throws
    @discardableResult
    func reconcileMorningEntries(for day: Date, context: ModelContext) throws -> Bool
    @discardableResult
    func upsertDayRecord(
        for day: Date,
        morningCompletion: Double,
        dailyCompletion: Double,
        context: ModelContext
    ) throws -> Bool
}

struct SwiftDataHomeRepository: HomeRepository {
    func fetchMorningEntries(for day: Date, context: ModelContext) throws -> [MorningRoutineEntry] {
        try HomeDataStore.fetchMorningEntries(for: day, context: context)
    }

    func fetchDailyTasks(for day: Date, context: ModelContext) throws -> [DailyTask] {
        try HomeDataStore.fetchDailyTasks(for: day, context: context)
    }

    func fetchDailyTask(id: UUID, context: ModelContext) throws -> DailyTask? {
        try HomeDataStore.fetchDailyTask(id: id, context: context)
    }

    func fetchDayRecord(for day: Date, context: ModelContext) throws -> DayRecord? {
        try HomeDataStore.fetchDayRecord(for: day, context: context)
    }

    func fetchTemplates(context: ModelContext) throws -> [MorningRoutineTemplateItem] {
        try HomeDataStore.fetchTemplates(context: context)
    }

    func fetchMorningEntries(from startDay: Date, through endDay: Date, context: ModelContext) throws -> [MorningRoutineEntry] {
        try HomeDataStore.fetchMorningEntries(from: startDay, through: endDay, context: context)
    }

    func fetchDailyTasks(from startDay: Date, through endDay: Date, context: ModelContext) throws -> [DailyTask] {
        try HomeDataStore.fetchDailyTasks(from: startDay, through: endDay, context: context)
    }

    func nextSortOrder(for day: Date, insertAtTop: Bool, context: ModelContext) throws -> Int {
        try HomeDataStore.nextSortOrder(for: day, insertAtTop: insertAtTop, context: context)
    }

    func migrateLegacyDayKeysIfNeeded(context: ModelContext) throws {
        try HomeDataStore.migrateLegacyDayKeysIfNeeded(context: context)
    }

    @discardableResult
    func reconcileMorningEntries(for day: Date, context: ModelContext) throws -> Bool {
        try HomeDataStore.reconcileMorningEntries(for: day, context: context)
    }

    @discardableResult
    func upsertDayRecord(
        for day: Date,
        morningCompletion: Double,
        dailyCompletion: Double,
        context: ModelContext
    ) throws -> Bool {
        try HomeDataStore.upsertDayRecord(
            for: day,
            morningCompletion: morningCompletion,
            dailyCompletion: dailyCompletion,
            context: context
        )
    }
}
