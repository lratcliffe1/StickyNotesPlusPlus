import Foundation
import SwiftData

/// One-time copy of the V1 rows into the V2 tables, run by `ListService.prepare` before anything
/// reads. The V1 tables are left exactly as they are, and nothing writes them afterwards.
///
/// - `MorningRoutineTemplateItem` → `Item` (morning, repeats daily, same id), starting on the
///   earliest routine entry's day, or today if there are none.
/// - `MorningRoutineEntry` → `Occurrence` (same id), linked to its item by title one last time,
///   per day, in template order. Unmatched entries become one-offs on the morning list that can't
///   be bumped (V1 routine entries never could be).
/// - `DailyTask` → one-off `Occurrence` on the day list (same id). A task with `bumpedTaskID` is
///   `bumped`, linked both ways to the task it moved to; `isBumpable == false` → can't bump,
///   otherwise unlimited (V1's behaviour). `bumpCount` is kept; the chain's first row gives
///   "first added".
/// - `DayRecord` isn't copied (completion is recomputed from occurrences).
///
/// Idempotent: rows keep their V1 ids and existing ids are skipped, so a second run (or the app and
/// the widget racing) never duplicates anything. The flag is written only after the save succeeds.
enum V2Backfill {
    static let completedDefaultsKey = "v2_backfill_completed_v1"

    static func runIfNeeded(
        context: ModelContext,
        defaults: UserDefaults,
        now: Date = Date(),
        calendar: Calendar = .current,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard !defaults.bool(forKey: completedDefaultsKey) else { return }
        // Old rows may still lack day keys; fill them first (this writes V1 for the last time).
        try HomeDataStore.migrateLegacyDayKeysIfNeeded(context: context, defaults: defaults)
        try copyV1Rows(context: context, now: now, calendar: calendar)
        try save(context)
        defaults.set(true, forKey: completedDefaultsKey)
    }

    static func copyV1Rows(context: ModelContext, now: Date, calendar: Calendar) throws {
        let todayKey = HomeModel.dayKey(for: now, calendar: calendar)
        let templates = try context.fetch(
            FetchDescriptor<MorningRoutineTemplateItem>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let entries = try context.fetch(
            FetchDescriptor<MorningRoutineEntry>(sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.sortOrderSnapshot)])
        )
        let tasks = try context.fetch(FetchDescriptor<DailyTask>(sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.sortOrder)]))
        let existingItemIDs = Set(try context.fetch(FetchDescriptor<Item>()).map(\.id))
        let existingOccurrenceIDs = Set(try context.fetch(FetchDescriptor<Occurrence>()).map(\.id))

        func key(_ dayKey: String, _ date: Date) -> String {
            dayKey.isEmpty ? HomeModel.dayKey(for: date, calendar: calendar) : dayKey
        }

        // Items
        let earliestEntryKey = entries.map { key($0.dayKey, $0.date) }.min()
        let startKey = min(earliestEntryKey ?? todayKey, todayKey)
        var seenTemplateIDs = Set<UUID>()
        for template in templates where !existingItemIDs.contains(template.id) && !seenTemplateIDs.contains(template.id) {
            seenTemplateIDs.insert(template.id)
            context.insert(
                Item(
                    id: template.id,
                    list: .morning,
                    title: template.title,
                    sortOrder: template.sortOrder,
                    repeatRule: .daily,
                    startDayKey: startKey,
                    defaultBumpLimit: .unlimited,
                    createdAt: now
                )
            )
        }

        // Morning entries, matched to templates by title within each day
        let itemByEntryID = matchEntriesToTemplates(entries: entries, templates: templates, dayKey: { key($0.dayKey, $0.date) })
        let sortOrderByTemplateID = Dictionary(templates.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
        for entry in entries where !existingOccurrenceIDs.contains(entry.id) {
            let dayKey = key(entry.dayKey, entry.date)
            let itemID = itemByEntryID[entry.id]
            context.insert(
                Occurrence(
                    id: entry.id,
                    itemID: itemID,
                    list: .morning,
                    dayKey: dayKey,
                    title: entry.titleSnapshot,
                    sortOrder: itemID.flatMap { sortOrderByTemplateID[$0] } ?? entry.sortOrderSnapshot,
                    state: entry.isCompleted ? .done : .open,
                    completedAt: entry.completedAt,
                    createdAt: entry.date,
                    bumpLimit: itemID == nil ? .cantBump : .unlimited,
                    scheduledDayKey: itemID == nil ? nil : dayKey,
                    periodEndDayKey: itemID == nil ? nil : dayKey
                )
            )
        }

        // Daily tasks, with bump chains
        var taskByID: [UUID: DailyTask] = [:]
        for task in tasks { taskByID[task.id] = task }
        var sourceByTargetID: [UUID: UUID] = [:]
        for task in tasks {
            if let targetID = task.bumpedTaskID, taskByID[targetID] != nil {
                sourceByTargetID[targetID] = task.id
            }
        }

        for task in tasks where !existingOccurrenceIDs.contains(task.id) {
            let dayKey = key(task.dayKey, task.date)
            var root = task
            var visited: Set<UUID> = [task.id]
            while let sourceID = sourceByTargetID[root.id], let source = taskByID[sourceID], !visited.contains(sourceID) {
                visited.insert(sourceID)
                root = source
            }

            let state: OccurrenceState = task.bumpedTaskID != nil ? .bumped : (task.isCompleted ? .done : .open)
            context.insert(
                Occurrence(
                    id: task.id,
                    list: .day,
                    dayKey: dayKey,
                    title: task.title,
                    sortOrder: task.sortOrder,
                    state: state,
                    completedAt: task.completedAt,
                    createdAt: task.date,
                    bumpLimit: task.isBumpable ? .unlimited : .cantBump,
                    bumpedFromID: sourceByTargetID[task.id],
                    bumpedToID: task.bumpedTaskID.flatMap { taskByID[$0] == nil ? nil : $0 },
                    bumpCount: task.bumpCount,
                    firstAddedDayKey: key(root.dayKey, root.date),
                    firstAddedTitle: root.title
                )
            )
        }
    }

    /// Entry id → template id. Within each day, each template takes the first unclaimed entry with
    /// its exact title (the V1 reconcile rule); entries nobody claims stay unmatched.
    static func matchEntriesToTemplates(
        entries: [MorningRoutineEntry],
        templates: [MorningRoutineTemplateItem],
        dayKey: (MorningRoutineEntry) -> String
    ) -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        let byDay = Dictionary(grouping: entries, by: dayKey)
        for (_, dayEntries) in byDay {
            var buckets: [String: [MorningRoutineEntry]] = [:]
            for entry in dayEntries.sorted(by: { ($0.sortOrderSnapshot, $0.id.uuidString) < ($1.sortOrderSnapshot, $1.id.uuidString) }) {
                buckets[entry.titleSnapshot, default: []].append(entry)
            }
            for template in templates {
                guard var bucket = buckets[template.title], !bucket.isEmpty else { continue }
                let entry = bucket.removeFirst()
                buckets[template.title] = bucket
                result[entry.id] = template.id
            }
        }
        return result
    }
}
