import Foundation
import SwiftData

extension HomeViewModel {
    // MARK: - Fetching

    func fetchMorningEntries(for day: Date, context: ModelContext) -> [MorningRoutineEntry] {
        let day = HomeModel.normalizedDay(day)
        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
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

    func fetchDailyTask(id: UUID, context: ModelContext) -> DailyTask? {
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
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
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
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

    func reconcileMorningEntries(for day: Date, context: ModelContext) {
        let day = HomeModel.normalizedDay(day)
        let templates = fetchTemplates(context: context)
        let existing = fetchMorningEntries(for: day, context: context)
        var didChange = false

        if templates.isEmpty {
            if !existing.isEmpty {
                for entry in existing {
                    context.delete(entry)
                }
                save(context: context)
            }
            return
        }

        var unmatchedByTitle: [String: [MorningRoutineEntry]] = [:]
        for entry in existing {
            unmatchedByTitle[entry.titleSnapshot, default: []].append(entry)
        }

        for (title, entries) in unmatchedByTitle {
            unmatchedByTitle[title] = entries.sorted {
                if $0.sortOrderSnapshot != $1.sortOrderSnapshot {
                    return $0.sortOrderSnapshot < $1.sortOrderSnapshot
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }

        var keptEntryIDs: Set<UUID> = []

        for template in templates {
            if var bucket = unmatchedByTitle[template.title], let entry = bucket.first {
                bucket.removeFirst()
                unmatchedByTitle[template.title] = bucket
                keptEntryIDs.insert(entry.id)

                if entry.sortOrderSnapshot != template.sortOrder {
                    entry.sortOrderSnapshot = template.sortOrder
                    didChange = true
                }

                if entry.targetTimeSnapshot != template.targetTime {
                    entry.targetTimeSnapshot = template.targetTime
                    didChange = true
                }
            } else {
                let entry = MorningRoutineEntry(
                    date: day,
                    titleSnapshot: template.title,
                    sortOrderSnapshot: template.sortOrder,
                    targetTimeSnapshot: template.targetTime
                )
                context.insert(entry)
                didChange = true
            }
        }

        for entry in existing where !keptEntryIDs.contains(entry.id) {
            context.delete(entry)
            didChange = true
        }

        if didChange {
            save(context: context)
        }
    }

    func upsertDayRecord(for day: Date, context: ModelContext) {
        let day = HomeModel.normalizedDay(day)
        let morning = HomeModel.morningCompletion(entries: morningEntries).value
        let daily = HomeModel.dailyCompletion(tasks: dailyTasks).value

        if let record = fetchDayRecord(for: day, context: context) {
            record.morningCompletion = morning
            record.dailyCompletion = daily
        } else {
            let record = DayRecord(date: day, morningCompletion: morning, dailyCompletion: daily)
            context.insert(record)
        }
        save(context: context)
    }

    func save(context: ModelContext) {
        do { try context.save() }
        catch { print("SwiftData save error:", error) }
    }
}
