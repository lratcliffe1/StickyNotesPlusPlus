import Foundation
import SwiftData

extension HomeViewModel {
    // MARK: - Fetching

    func fetchMorningEntries(for day: Date, context: ModelContext) -> [MorningRoutineEntry] {
        let dayKey = dayKey(for: day)
        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDailyTasks(for day: Date, context: ModelContext) -> [DailyTask] {
        let dayKey = dayKey(for: day)

        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.dayKey == dayKey }
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
        let dayKey = dayKey(for: day)
        let descriptor = FetchDescriptor<DayRecord>(
            predicate: #Predicate { $0.dayKey == dayKey }
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
        let startKey = dayKey(for: startDay)
        let endKey = dayKey(for: endDay)

        let descriptor = FetchDescriptor<MorningRoutineEntry>(
            predicate: #Predicate {
                $0.dayKey >= startKey && $0.dayKey <= endKey
            },
            sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.sortOrderSnapshot), SortDescriptor(\.titleSnapshot)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDailyTasks(
        from startDay: Date,
        through endDay: Date,
        context: ModelContext
    ) -> [DailyTask] {
        let startKey = dayKey(for: startDay)
        let endKey = dayKey(for: endDay)

        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate {
                $0.dayKey >= startKey && $0.dayKey <= endKey
            }
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    func migrateLegacyDayKeysIfNeeded(context: ModelContext) {
        let defaults = SharedPersistence.sharedDefaults
        guard !defaults.bool(forKey: dayKeyMigrationCompletedDefaultsKey) else { return }

        do {
            var didChange = false

            let morningEntries = try context.fetch(FetchDescriptor<MorningRoutineEntry>())
            for entry in morningEntries where entry.dayKey.isEmpty {
                entry.dayKey = HomeModel.dayKey(for: entry.date)
                didChange = true
            }

            let dailyTasks = try context.fetch(FetchDescriptor<DailyTask>())
            for task in dailyTasks where task.dayKey.isEmpty {
                task.dayKey = HomeModel.dayKey(for: task.date)
                didChange = true
            }

            let dayRecords = try context.fetch(FetchDescriptor<DayRecord>())
            for record in dayRecords where record.dayKey.isEmpty {
                record.dayKey = HomeModel.dayKey(for: record.date)
                didChange = true
            }

            if didChange {
                try context.save()
            }

            defaults.set(true, forKey: dayKeyMigrationCompletedDefaultsKey)
        } catch {
            print("Day key migration error:", error)
        }
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

    private func dayKey(for day: Date) -> String {
        HomeModel.dayKey(for: HomeModel.normalizedDay(day))
    }

    private var dayKeyMigrationCompletedDefaultsKey: String {
        "stable_day_key_migration_completed_v1"
    }
}
