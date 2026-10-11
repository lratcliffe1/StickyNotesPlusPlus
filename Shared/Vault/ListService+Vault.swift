import Foundation
import SwiftData

/// The vault link's writes and reads, through the one write path (`docs/VAULT-API.md`).
/// Imported tasks are ordinary one-offs; which rows came from the vault is kept in the manifest
/// (App Group defaults), so the store's schema doesn't change.
extension ListService {
    /// What one reconcile did, by `tasks.json` id.
    struct VaultReconcileResult: Equatable {
        var added: [String] = []
        var updated: [String] = []
        var removed: [String] = []
        /// Done, skipped or bumped (or its bump chain moved on): ticks and bumps always win.
        var untouched: [String] = []
        /// Imported before, then deleted in the app: left deleted.
        var deletedInApp: [String] = []

        var changedStore: Bool { !(added.isEmpty && updated.isEmpty && removed.isEmpty) }
    }

    /// Brings imported one-offs in line with `tasks.json` (the contract's rules):
    /// - a new id is added as a one-off on its day (today, if that day is past), with its title,
    ///   deadline and bump limit, under an id derived from the task id;
    /// - a known id whose row is still open and was never bumped follows the file: its day always
    ///   (a past day becomes today), its title, list, deadline and bump limit when the file's task
    ///   changed since the last import (so an edit made in the app lasts until Now.md changes it);
    /// - a row that is done, skipped or bumped is never touched;
    /// - an id gone from the file is removed if its row is still open and was never bumped, and
    ///   kept otherwise;
    /// - an id the app imported and the user then deleted stays deleted.
    /// Saves once, then writes the manifest (never before the save).
    @discardableResult
    static func reconcileVaultTasks(
        _ tasks: [VaultTask],
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> VaultReconcileResult {
        let todayKey = dayKey(for: now, calendar: calendar)
        let math = DayMath(calendar: calendar)
        var manifest = VaultManifest.load(from: defaults)
        let before = manifest
        var result = VaultReconcileResult()

        for task in tasks {
            let entry = manifest.entries[task.id]
            let rowID = entry?.occurrenceID ?? VaultTaskID.occurrenceID(for: task.id)
            let targetDay = max(task.dayKey, todayKey)

            guard let row = try occurrence(id: rowID, context: context) else {
                if entry != nil {
                    result.deletedInApp.append(task.id)
                    continue
                }
                let added = Occurrence(
                    id: rowID,
                    list: task.list,
                    dayKey: targetDay,
                    title: task.title,
                    sortOrder: try vaultNextSortOrder(on: targetDay, list: task.list, context: context),
                    createdAt: now,
                    bumpLimit: task.bumpLimit,
                    deadlineDayKey: task.deadlineDayKey
                )
                added.deadlineDayKey = task.deadlineDayKey
                context.insert(added)
                manifest.entries[task.id] = VaultManifest.Entry(occurrenceID: rowID, fingerprint: task.fingerprint)
                result.added.append(task.id)
                continue
            }

            guard isOpenAndNeverBumped(row) else {
                manifest.entries[task.id] = VaultManifest.Entry(occurrenceID: row.id, fingerprint: entry?.fingerprint)
                result.untouched.append(task.id)
                continue
            }

            var changed = false
            let fileChanged = entry?.fingerprint != task.fingerprint
            let newList = fileChanged ? task.list : row.list
            if newList != row.list || targetDay != row.dayKey {
                row.sortOrder = try vaultNextSortOrder(on: targetDay, list: newList, context: context)
                row.listRaw = newList.rawValue
                row.dayKey = targetDay
                row.firstAddedDayKey = targetDay
                changed = true
            }
            if fileChanged {
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
            }
            manifest.entries[task.id] = VaultManifest.Entry(occurrenceID: row.id, fingerprint: task.fingerprint)
            if changed {
                result.updated.append(task.id)
            }
        }

        let wanted = Set(tasks.map(\.id))
        let pruneBefore = math.adding(days: -62, to: todayKey)
        for (taskID, entry) in manifest.entries where !wanted.contains(taskID) {
            guard let row = try occurrence(id: entry.occurrenceID, context: context) else {
                // Gone from the file and from the store: nothing left to follow.
                manifest.entries[taskID] = nil
                continue
            }
            if isOpenAndNeverBumped(row) {
                context.delete(row)
                manifest.entries[taskID] = nil
                result.removed.append(taskID)
            } else {
                result.untouched.append(taskID)
                // Kept for the habits file's "vault tasks done" until it's long past.
                if row.dayKey < pruneBefore {
                    manifest.entries[taskID] = nil
                }
            }
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        if manifest != before {
            manifest.save(to: defaults)
        }
        return result
    }

    /// Open, and never bumped from or into: the only state the vault may change.
    static func isOpenAndNeverBumped(_ row: Occurrence) -> Bool {
        row.state == .open && row.bumpedToID == nil && row.bumpedFromID == nil && row.bumpCount == 0
    }

    /// Ids of every row that came from the vault: the imported rows and the copies bumped from them.
    static func vaultOccurrenceIDs(context: ModelContext, defaults: UserDefaults) throws -> Set<UUID> {
        var ids = Set<UUID>()
        for entry in VaultManifest.load(from: defaults).entries.values {
            var next: UUID? = entry.occurrenceID
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
        for (taskID, entry) in VaultManifest.load(from: defaults).entries {
            var next: UUID? = entry.occurrenceID
            var steps = 0
            while let id = next, steps < 60, let row = try occurrence(id: id, context: context) {
                if row.state == .done, row.dayKey >= startKey, row.dayKey <= endKey {
                    byDay[row.dayKey, default: []].append(
                        VaultHabits.DoneTask(id: taskID, title: row.title, doneAt: row.completedAt)
                    )
                }
                next = row.bumpedToID
                steps += 1
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
