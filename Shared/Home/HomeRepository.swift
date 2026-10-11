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
        morningMode: HomeModel.MorningMode,
        context: ModelContext
    ) throws -> HomeModel.StreakState
    /// How each day through `endKey` looks for a list (same rules as the streak).
    func dayLooks(
        for list: ListKind,
        through endKey: String,
        todayKey: String,
        morningMode: HomeModel.MorningMode,
        context: ModelContext
    ) throws -> [String: ListRules.DayLook]
    /// Days from `startKey` through `endKey` with a bump on any list (the ↻ mark).
    func bumpedDayKeys(from startKey: String, through endKey: String, context: ModelContext) throws -> Set<String>
    /// Bumps on days in the current week up to `todayKey`, all lists.
    func bumpsThisWeek(todayKey: String, context: ModelContext) throws -> Int
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
        morningMode: HomeModel.MorningMode,
        context: ModelContext
    ) throws -> HomeModel.StreakState {
        try ListService.streakState(for: list, through: anchorKey, morningMode: morningMode, context: context, calendar: .current)
    }

    func dayLooks(
        for list: ListKind,
        through endKey: String,
        todayKey: String,
        morningMode: HomeModel.MorningMode,
        context: ModelContext
    ) throws -> [String: ListRules.DayLook] {
        try ListService.dayLooks(for: list, through: endKey, todayKey: todayKey, morningMode: morningMode, context: context, calendar: .current)
    }

    func bumpedDayKeys(from startKey: String, through endKey: String, context: ModelContext) throws -> Set<String> {
        try ListService.bumpedDayKeys(from: startKey, through: endKey, context: context)
    }

    func bumpsThisWeek(todayKey: String, context: ModelContext) throws -> Int {
        try ListService.bumpsThisWeek(todayKey: todayKey, calendar: .current, context: context)
    }
}
