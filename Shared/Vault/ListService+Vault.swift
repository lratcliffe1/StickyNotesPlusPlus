import Foundation
import SwiftData

/// The vault link's writes and reads, through the one write path (`docs/VAULT-API.md`).
/// Imported tasks are ordinary one-offs; which rows came from the vault is kept in the manifest
/// (App Group defaults), so the store's schema doesn't change.
extension ListService {
    /// What one reconcile did, by `tasks.json` id.
    struct VaultReconcileResult: Equatable {
        /// Got a new row (new, moved to another day, or carried to today from an earlier day).
        var added: [String] = []
        /// An open, never-bumped row took the file's new title, list, deadline or bump limit.
        var updated: [String] = []
        /// An open, never-bumped row on today or later was deleted (gone from the file, or moved).
        var removed: [String] = []
        /// Done, skipped or bumped for this scheduling: ticks and bumps always win.
        var untouched: [String] = []
        /// Imported, then deleted in the app: left deleted.
        var deletedInApp: [String] = []
        /// The manifest couldn't be read: only rows whose ids didn't exist were added.
        var manifestUnreadable = false

        var changedStore: Bool { !(added.isEmpty && updated.isEmpty && removed.isEmpty) }
    }

    /// Brings imported one-offs in line with `tasks.json` (`docs/VAULT-API.md`). One row per task
    /// per day (`VaultTaskID`); rows dated before today are history and never change.
    ///
    /// For each task, with T = its day, or today if that day is past:
    /// - T's row exists: if still open and never bumped, it takes the file's title, list, deadline
    ///   and bump limit when the file's task changed since the last import (so an edit made in the
    ///   app lasts until Now.md changes it). Its day never changes.
    /// - No row at T: one is added, unless the task is settled for this scheduling: a row on or after
    ///   the file's day is done, skipped or bumped (a bumped chain owns its own future), or was
    ///   deleted in the app. An open row left on a past day stays there, as that day's miss.
    /// - Any other open, never-bumped row of the task on today or later is removed (the task moved).
    /// A task gone from the file loses its open, never-bumped rows on today or later; everything
    /// else stays. An existing row is never inserted again, so a tick can't be reset.
    ///
    /// If the manifest can't be read, it fails safe: only rows whose ids don't exist are added;
    /// nothing is updated or removed, and the stored manifest is left as it is.
    /// Saves once, then writes the manifest (never before the save). Callers that may race another
    /// process hold `VaultFileLock` around it.
    @discardableResult
    static func reconcileVaultTasks(
        _ tasks: [VaultTask],
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> VaultReconcileResult {
        let todayKey = dayKey(for: now, calendar: calendar)
        var result = VaultReconcileResult()

        guard var manifest = VaultManifest.load(from: defaults) else {
            result.manifestUnreadable = true
            for task in tasks {
                let target = max(task.dayKey, todayKey)
                let rowID = VaultTaskID.occurrenceID(for: task.id, dayKey: target)
                guard try occurrence(id: rowID, context: context) == nil else { continue }
                try insertVaultRow(for: task, on: target, id: rowID, now: now, context: context)
                result.added.append(task.id)
            }
            try saveVaultChanges(context: context)
            return result
        }
        let before = manifest

        for task in tasks {
            var entry = manifest.entries[task.id] ?? VaultManifest.Entry()
            let target = max(task.dayKey, todayKey)
            let targetID = VaultTaskID.occurrenceID(for: task.id, dayKey: target)
            let fileChanged = entry.fingerprint != task.fingerprint
            // The task's rows the manifest knows, by day (nil: deleted in the app).
            var known: [(day: String, row: Occurrence?)] = []
            for day in entry.rows.keys.sorted() where day != target {
                if let id = entry.rows[day] {
                    known.append((day, try occurrence(id: id, context: context)))
                }
            }

            if let row = try occurrence(id: targetID, context: context) {
                entry.rows[target] = targetID
                if isOpenAndNeverBumped(row) {
                    if fileChanged, try applyVaultFields(of: task, to: row, context: context) {
                        result.updated.append(task.id)
                    }
                } else {
                    result.untouched.append(task.id)
                }
            } else if entry.rows[target] != nil {
                // T's row was imported and then deleted in the app.
                result.deletedInApp.append(task.id)
            } else {
                let settled = known.first { day, row in
                    guard day >= task.dayKey else { return false }
                    guard let row else { return true }
                    return !isOpenAndNeverBumped(row)
                }
                if let settled {
                    if settled.row == nil {
                        result.deletedInApp.append(task.id)
                    } else {
                        result.untouched.append(task.id)
                    }
                } else {
                    try insertVaultRow(for: task, on: target, id: targetID, now: now, context: context)
                    entry.rows[target] = targetID
                    result.added.append(task.id)
                }
            }

            // The task moved: its other open, never-bumped rows on today or later go.
            for (day, row) in known where day >= todayKey {
                guard let row, isOpenAndNeverBumped(row), row.dayKey >= todayKey else { continue }
                context.delete(row)
                entry.rows[day] = nil
                if !result.removed.contains(task.id) { result.removed.append(task.id) }
            }
            entry.fingerprint = task.fingerprint
            manifest.entries[task.id] = entry
        }

        let wanted = Set(tasks.map(\.id))
        let pruneBefore = DayMath(calendar: calendar).adding(days: -62, to: todayKey)
        for (taskID, original) in manifest.entries {
            var entry = original
            for (day, id) in original.rows {
                guard let row = try occurrence(id: id, context: context) else {
                    // Deleted in the app: remembered only while the task is still in the file.
                    if !wanted.contains(taskID) || day < pruneBefore { entry.rows[day] = nil }
                    continue
                }
                if !wanted.contains(taskID), row.dayKey >= todayKey, isOpenAndNeverBumped(row) {
                    context.delete(row)
                    entry.rows[day] = nil
                    if !result.removed.contains(taskID) { result.removed.append(taskID) }
                } else if day < pruneBefore {
                    // Long past: kept in the store, no longer followed (habits are written by then).
                    entry.rows[day] = nil
                }
            }
            if entry.rows.isEmpty && !wanted.contains(taskID) {
                manifest.entries[taskID] = nil
            } else if entry != original {
                manifest.entries[taskID] = entry
            }
        }

        try saveVaultChanges(context: context)
        if manifest != before {
            manifest.save(to: defaults)
        }
        return result
    }

    /// Open, and never bumped from or into: the only state the vault may change.
    static func isOpenAndNeverBumped(_ row: Occurrence) -> Bool {
        row.state == .open && row.bumpedToID == nil && row.bumpedFromID == nil && row.bumpCount == 0
    }

    /// The file's title, list, deadline and bump limit onto an open, never-bumped row (never its
    /// day). Returns whether anything changed.
    private static func applyVaultFields(of task: VaultTask, to row: Occurrence, context: ModelContext) throws -> Bool {
        var changed = false
        if row.list != task.list {
            row.sortOrder = try vaultNextSortOrder(on: row.dayKey, list: task.list, context: context)
            row.listRaw = task.list.rawValue
            changed = true
        }
        if row.title != task.title {
            row.title = task.title
            row.firstAddedTitle = task.title
            changed = true
        }
        if row.bumpLimit != task.bumpLimit || row.deadlineDayKey != task.deadlineDayKey {
            row.bumpLimit = task.bumpLimit
            row.deadlineDayKey = task.deadlineDayKey
            changed = true
        }
        return changed
    }

    private static func insertVaultRow(for task: VaultTask, on day: String, id: UUID, now: Date, context: ModelContext) throws {
        let row = Occurrence(
            id: id,
            list: task.list,
            dayKey: day,
            title: task.title,
            sortOrder: try vaultNextSortOrder(on: day, list: task.list, context: context),
            createdAt: now,
            bumpLimit: task.bumpLimit,
            deadlineDayKey: task.deadlineDayKey
        )
        row.deadlineDayKey = task.deadlineDayKey
        context.insert(row)
    }

    private static func saveVaultChanges(context: ModelContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Ids of every row that came from the vault: the imported rows and the copies bumped from them.
    static func vaultOccurrenceIDs(context: ModelContext, defaults: UserDefaults) throws -> Set<UUID> {
        var ids = Set<UUID>()
        for start in (VaultManifest.load(from: defaults) ?? VaultManifest()).allRowIDs {
            var next: UUID? = start
            var steps = 0
            while let id = next, steps < 60, ids.insert(id).inserted {
                next = try occurrence(id: id, context: context)?.bumpedToID
                steps += 1
            }
        }
        return ids
    }

    /// Imported tasks ticked on days from `startKey` through `endKey`, by day. A task bumped and
    /// then done counts on the day it was done.
    static func vaultTasksDone(
        from startKey: String,
        through endKey: String,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> [String: [VaultHabits.DoneTask]] {
        var byDay: [String: [VaultHabits.DoneTask]] = [:]
        var seen = Set<UUID>()
        for (taskID, entry) in (VaultManifest.load(from: defaults) ?? VaultManifest()).entries {
            for start in entry.rows.values {
                var next: UUID? = start
                var steps = 0
                while let id = next, steps < 60, seen.insert(id).inserted, let row = try occurrence(id: id, context: context) {
                    if row.state == .done, row.dayKey >= startKey, row.dayKey <= endKey {
                        byDay[row.dayKey, default: []].append(
                            VaultHabits.DoneTask(id: taskID, title: row.title, doneAt: row.completedAt)
                        )
                    }
                    next = row.bumpedToID
                    steps += 1
                }
            }
        }
        return byDay.mapValues { tasks in
            tasks.sorted { lhs, rhs in
                let left = lhs.doneAt ?? .distantPast
                let right = rhs.doneAt ?? .distantPast
                return left != right ? left < right : lhs.id < rhs.id
            }
        }
    }

    /// The month document for `habits/YYYY-MM.json`: every day of `targetKey`'s month through
    /// `targetKey`, judged by the same rules Home shows (`dayLooks`, streaks).
    static func vaultHabitsDocument(
        through targetKey: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> JSONValue {
        let todayKey = dayKey(for: now, calendar: calendar)
        let month = String(targetKey.prefix(7))
        let startKey = "\(month)-01"
        // The same rules Home and the widget judge by (today from the settings if not stored yet).
        let history = DayRulesStore.resolvedHistory(in: defaults, todayKey: todayKey)
        let looks = try dayLooks(
            from: startKey, through: targetKey, todayKey: todayKey, history: history, context: context, calendar: calendar
        ).looks
        let inUse = Set(try listsInUse(context: context))

        var lists: [ListKind: VaultHabits.ListInput] = [:]
        var streaks: [ListKind: Int] = [:]
        for list in ListKind.allCases {
            let rows = try occurrences(from: startKey, through: targetKey, list: list, context: context)
            lists[list] = VaultHabits.ListInput(
                rowsByDay: Dictionary(grouping: rows.map { VaultHabits.RowFacts($0) }, by: \.dayKey),
                looks: looks[list] ?? [:]
            )
            // A list not in use (no items, no rows ever) has no streak.
            if inUse.contains(list) {
                streaks[list] = try streakState(for: list, through: todayKey, history: history, context: context, calendar: calendar).count
            } else {
                streaks[list] = 0
            }
        }

        return VaultHabits.document(
            month: month,
            through: targetKey,
            todayKey: todayKey,
            lists: lists,
            streaks: streaks,
            vaultTasksDone: try vaultTasksDone(from: startKey, through: targetKey, context: context, defaults: defaults),
            updatedAt: now,
            timeZone: calendar.timeZone
        )
    }

    /// The next one-off position on a day's list (the same rule as `addOneOff`).
    private static func vaultNextSortOrder(on dayKey: String, list: ListKind, context: ModelContext) throws -> Int {
        let oneOffs = try occurrences(on: dayKey, list: list, context: context).filter { !$0.isRepeating }
        return (oneOffs.map(\.sortOrder).max() ?? -1) + 1
    }
}
