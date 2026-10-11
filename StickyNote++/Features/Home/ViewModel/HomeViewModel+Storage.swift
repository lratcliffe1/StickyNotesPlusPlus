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
                morningMode: morningMode,
                context: context
            )
        } catch {
            AppLogger.persistence.error("Streak for \(list.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return HomeModel.StreakState(count: 0, isFrozen: false)
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
