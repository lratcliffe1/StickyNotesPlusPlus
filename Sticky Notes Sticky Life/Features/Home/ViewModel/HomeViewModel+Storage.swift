import Foundation
import SwiftData

extension HomeViewModel {
    // MARK: - Fetching

    func fetchMorningEntries(for day: Date, context: ModelContext) -> [MorningRoutineEntry] {
        let day = HomeModel.normalizedDay(day)
        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.titleSnapshot)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDailyTasks(for day: Date, context: ModelContext) -> [DailyTask] {
        let day = HomeModel.normalizedDay(day)

        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.title)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDayRecord(for day: Date, context: ModelContext) -> DayRecord? {
        let day = HomeModel.normalizedDay(day)
        let descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.date == day }
        )
        return (try? context.fetch(descriptor))?.first
    }

    func fetchTemplates(context: ModelContext) -> [MorningRoutineTemplateItem] {
        let descriptor = FetchDescriptor<MorningRoutineTemplateItem>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchMorningEntries(
        from startDay: Date,
        through endDay: Date,
        context: ModelContext
    ) -> [MorningRoutineEntry] {
        let startDay = HomeModel.normalizedDay(startDay)
        let endDay = HomeModel.normalizedDay(endDay)

        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.date >= startDay && $0.date <= endDay },
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.titleSnapshot)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDailyTasks(
        from startDay: Date,
        through endDay: Date,
        context: ModelContext
    ) -> [DailyTask] {
        let startDay = HomeModel.normalizedDay(startDay)
        let endDay = HomeModel.normalizedDay(endDay)

        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.date >= startDay && $0.date <= endDay },
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.title)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Ensure / Upsert logic

    func ensureMorningEntriesExist(for day: Date, context: ModelContext) {
        let existing = fetchMorningEntries(for: day, context: context)
        if !existing.isEmpty { return }

        let templates = fetchTemplates(context: context)
        guard !templates.isEmpty else { return }

        for template in templates {
            let entry = MorningRoutineEntry(
                date: day,
                titleSnapshot: template.title,
                targetTimeSnapshot: template.targetTime
            )
            context.insert(entry)
        }
        save(context: context)
    }

    func upsertDayRecord(for day: Date, context: ModelContext) {
        let day = HomeModel.normalizedDay(day)
        let morning = HomeModel.morningCompletion(entries: morningEntries).value
        let daily = HomeModel.dailyCompletion(tasks: dailyTasks).value

        if let record = fetchDayRecord(for: day, context: context) {
            record.morningCompletion = morning
            record.dailyCompletion = daily
            dayRecord = record
        } else {
            let record = DayRecord(date: day, morningCompletion: morning, dailyCompletion: daily)
            context.insert(record)
            dayRecord = record
        }
        save(context: context)
    }

    func save(context: ModelContext) {
        do { try context.save() }
        catch { print("SwiftData save error:", error) }
    }
}
