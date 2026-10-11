import Foundation
import SwiftData

/// What Home reads through. Writes go straight to `ListService`, the one write path.
protocol HomeRepository {
    /// One-time V1 → V2 copy, then today's occurrences. Call before reading.
    func prepare(now: Date, context: ModelContext) throws
    func occurrences(on dayKey: String, list: ListKind, context: ModelContext) throws -> [Occurrence]
    func occurrences(from startKey: String, through endKey: String, list: ListKind, context: ModelContext) throws -> [Occurrence]
    func streakState(
        for list: ListKind,
        through anchorKey: String,
        history: DayRulesHistory,
        context: ModelContext
    ) throws -> HomeModel.StreakState
    /// How each day from `startKey` through `endKey` looks, per list (same rules as the streak),
    /// and the days with a bump, fetching only the rows those days need.
    func dayLooks(
        from startKey: String,
        through endKey: String,
        todayKey: String,
        history: DayRulesHistory,
        context: ModelContext
    ) throws -> (looks: [ListKind: [String: ListRules.DayLook]], bumpedDays: Set<String>)
    /// The lists in use, in order (a day's circle has a segment for each).
    func listsInUse(context: ModelContext) throws -> [ListKind]
    /// The first day with an entry on any list (days before it are plain in the ring).
    func firstEntryDayKey(context: ModelContext) throws -> String?
    /// Days from `startKey` through `endKey` with something planned (the future days' dot).
    func plannedDayKeys(from startKey: String, through endKey: String, context: ModelContext) throws -> Set<String>
    /// A list's recurring items due on `dayKey` with no row there yet (planned, on a future day).
    func dueItemsWithoutRows(on dayKey: String, list: ListKind, context: ModelContext) throws -> [Item]
    /// Bump actions on days from `startKey` through `endKey`, all lists.
    func bumpCount(from startKey: String, through endKey: String, context: ModelContext) throws -> Int
    /// Whether a list has any item or occurrence (the header shows the evening streak only then).
    func isInUse(_ list: ListKind, context: ModelContext) throws -> Bool
}

struct SwiftDataHomeRepository: HomeRepository {
    /// Where the one-off migration flags live. The screenshot harness passes its own suite.
    var defaults: UserDefaults = SharedPersistence.sharedDefaults

    func prepare(now: Date, context: ModelContext) throws {
        try ListService.prepare(context: context, now: now, calendar: .current, defaults: defaults)
    }

    func occurrences(on dayKey: String, list: ListKind, context: ModelContext) throws -> [Occurrence] {
        try ListService.occurrences(on: dayKey, list: list, context: context)
    }

    func occurrences(from startKey: String, through endKey: String, list: ListKind, context: ModelContext) throws -> [Occurrence] {
        try ListService.occurrences(from: startKey, through: endKey, list: list, context: context)
    }

    func streakState(
        for list: ListKind,
        through anchorKey: String,
        history: DayRulesHistory,
        context: ModelContext
    ) throws -> HomeModel.StreakState {
        try ListService.streakState(for: list, through: anchorKey, history: history, context: context, calendar: .current)
    }

    func dayLooks(
        from startKey: String,
        through endKey: String,
        todayKey: String,
        history: DayRulesHistory,
        context: ModelContext
    ) throws -> (looks: [ListKind: [String: ListRules.DayLook]], bumpedDays: Set<String>) {
        try ListService.dayLooks(from: startKey, through: endKey, todayKey: todayKey, history: history, context: context, calendar: .current)
    }

    func listsInUse(context: ModelContext) throws -> [ListKind] {
        try ListService.listsInUse(context: context)
    }

    func firstEntryDayKey(context: ModelContext) throws -> String? {
        try ListService.firstEntryDayKey(context: context)
    }

    func plannedDayKeys(from startKey: String, through endKey: String, context: ModelContext) throws -> Set<String> {
        try ListService.plannedDayKeys(from: startKey, through: endKey, context: context, calendar: .current)
    }

    func dueItemsWithoutRows(on dayKey: String, list: ListKind, context: ModelContext) throws -> [Item] {
        try ListService.dueItemsWithoutRows(on: dayKey, list: list, context: context, calendar: .current)
    }

    func bumpCount(from startKey: String, through endKey: String, context: ModelContext) throws -> Int {
        try ListService.bumpCount(from: startKey, through: endKey, context: context)
    }

    func isInUse(_ list: ListKind, context: ModelContext) throws -> Bool {
        try ListService.isInUse(list, context: context)
    }
}
