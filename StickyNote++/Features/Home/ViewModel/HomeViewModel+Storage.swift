import Foundation
import SwiftData
import os

/// Storage-facing helpers for `HomeViewModel`: reads go through the repository, and every
/// write goes through `ListService`. Errors are logged, never thrown at the UI.
extension HomeViewModel {
    // MARK: - Preparing and fetching

    func prepareStore(context: ModelContext) {
        do {
            try repository.prepare(now: now, context: context)
        } catch {
            AppLogger.persistence.error("Prepare store failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchOccurrences(on dayKey: String, list: ListKind, context: ModelContext) -> [Occurrence] {
        do {
            return try repository.occurrences(on: dayKey, list: list, context: context)
        } catch {
            AppLogger.persistence.error("Fetch occurrences failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchOccurrences(
        from startKey: String,
        through endKey: String,
        list: ListKind,
        context: ModelContext
    ) -> [Occurrence] {
        do {
            return try repository.occurrences(from: startKey, through: endKey, list: list, context: context)
        } catch {
            AppLogger.persistence.error("Fetch occurrence range failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func streakState(for list: ListKind, through day: Date, context: ModelContext) -> HomeModel.StreakState {
        do {
            return try repository.streakState(
                for: list,
                through: HomeModel.dayKey(for: day),
                history: dayRulesHistory,
                context: context
            )
        } catch {
            AppLogger.persistence.error("Streak for \(list.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return HomeModel.StreakState(count: 0, isFrozen: false)
        }
    }

    /// How each day from `startKey` through `endKey` (today or earlier) looks, per list, and the
    /// days with a bump: the same rules as the streak, fetching only those days' rows.
    func dayLooks(
        from startKey: String,
        through endKey: String,
        context: ModelContext
    ) -> (looks: [ListKind: [String: ListRules.DayLook]], bumpedDays: Set<String>) {
        guard startKey <= endKey else { return ([:], []) }
        do {
            return try repository.dayLooks(
                from: startKey, through: endKey, todayKey: HomeModel.dayKey(for: now),
                history: dayRulesHistory, context: context
            )
        } catch {
            AppLogger.persistence.error("Day looks failed: \(error.localizedDescription, privacy: .public)")
            return ([:], [])
        }
    }

    /// The first day each list was in use.
    func firstUseDayKeys(context: ModelContext) -> [ListKind: String] {
        do {
            return try repository.firstUseDayKeys(context: context)
        } catch {
            AppLogger.persistence.error("First use failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    /// Days from `startKey` through `endKey` with something planned.
    func plannedDayKeys(from startKey: String, through endKey: String, context: ModelContext) -> Set<String> {
        guard startKey <= endKey else { return [] }
        do {
            return try repository.plannedDayKeys(from: startKey, through: endKey, context: context)
        } catch {
            AppLogger.persistence.error("Planned days failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The recurring items planned on a future day (due there, no row yet), every list.
    func fetchPlannedItems(on dayKey: String, context: ModelContext) -> [PlannedItem] {
        do {
            return try ListKind.allCases.flatMap { list in
                try repository.dueItemsWithoutRows(on: dayKey, list: list, context: context)
                    .map { PlannedItem(id: $0.id, title: $0.title, list: list) }
            }
        } catch {
            AppLogger.persistence.error("Planned items failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Bump actions on days from `startKey` through `endKey`, all lists.
    func bumpCount(from startKey: String, through endKey: String, context: ModelContext) -> Int {
        do {
            return try repository.bumpCount(from: startKey, through: endKey, context: context)
        } catch {
            AppLogger.persistence.error("Bump count failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: - Writing

    /// Runs one `ListService` write, logging (and rolling back) on failure.
    @discardableResult
    func write<T>(_ label: String, context: ModelContext, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            AppLogger.persistence.error("\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            return nil
        }
    }

    func save(context: ModelContext) {
        do { try context.save() }
        catch {
            AppLogger.persistence.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
