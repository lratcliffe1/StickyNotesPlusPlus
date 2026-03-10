import Foundation
import SwiftData
import os

extension HomeViewModel {
    // MARK: - Fetching

    func fetchMorningEntries(for day: Date, context: ModelContext) -> [MorningRoutineEntry] {
        do {
            return try repository.fetchMorningEntries(for: day, context: context)
        } catch {
            AppLogger.persistence.error("Fetch morning entries failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchDailyTasks(for day: Date, context: ModelContext) -> [DailyTask] {
        do {
            return try repository.fetchDailyTasks(for: day, context: context)
        } catch {
            AppLogger.persistence.error("Fetch daily tasks failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchDailyTask(id: UUID, context: ModelContext) -> DailyTask? {
        do {
            return try repository.fetchDailyTask(id: id, context: context)
        } catch {
            AppLogger.persistence.error("Fetch daily task by id failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func fetchDayRecord(for day: Date, context: ModelContext) -> DayRecord? {
        do {
            return try repository.fetchDayRecord(for: day, context: context)
        } catch {
            AppLogger.persistence.error("Fetch day record failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func fetchTemplates(context: ModelContext) -> [MorningRoutineTemplateItem] {
        do {
            return try repository.fetchTemplates(context: context)
        } catch {
            AppLogger.persistence.error("Fetch templates failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchMorningEntries(
        from startDay: Date,
        through endDay: Date,
        context: ModelContext
    ) -> [MorningRoutineEntry] {
        do {
            return try repository.fetchMorningEntries(from: startDay, through: endDay, context: context)
        } catch {
            AppLogger.persistence.error("Fetch morning entries range failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchDailyTasks(
        from startDay: Date,
        through endDay: Date,
        context: ModelContext
    ) -> [DailyTask] {
        do {
            return try repository.fetchDailyTasks(from: startDay, through: endDay, context: context)
        } catch {
            AppLogger.persistence.error("Fetch daily tasks range failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func migrateLegacyDayKeysIfNeeded(context: ModelContext) {
        do {
            try repository.migrateLegacyDayKeysIfNeeded(context: context)
        } catch {
            AppLogger.persistence.error("Day-key migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Ensure / Upsert logic

    func reconcileMorningEntries(for day: Date, context: ModelContext) {
        do {
            _ = try repository.reconcileMorningEntries(for: day, context: context)
        } catch {
            AppLogger.persistence.error("Reconcile morning entries failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func upsertDayRecord(for day: Date, context: ModelContext) {
        let morning = HomeModel.morningCompletion(entries: morningEntries).value
        let daily = HomeModel.dailyCompletion(tasks: dailyTasks).value

        do {
            _ = try repository.upsertDayRecord(
                for: day,
                morningCompletion: morning,
                dailyCompletion: daily,
                context: context
            )
        } catch {
            AppLogger.persistence.error("Upsert day record failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func save(context: ModelContext) {
        do { try context.save() }
        catch {
            AppLogger.persistence.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
