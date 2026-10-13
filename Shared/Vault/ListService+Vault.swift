import Foundation
import SwiftData
import os

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
        /// Done, skipped or bumped (or settled earlier): ticks and bumps always win.
        var untouched: [String] = []
        /// Imported, then deleted in the app: left deleted.
        var deletedInApp: [String] = []
        /// A `done` entry ticked the task's row on its day, or added it done there (done before
        /// its day; fix round 2).
        var ticked: [String] = []
        /// Moved from today to a later day: today's open row was left skipped, shown as "Moved to
        /// <day>" (fix round 2).
        var moved: [String] = []
        /// The manifest couldn't be read and was rebuilt from the store (deletions in the app are
        /// forgotten, so such a task may come back once).
        var manifestRebuilt = false

        var changedStore: Bool {
            !(added.isEmpty && updated.isEmpty && removed.isEmpty && ticked.isEmpty && moved.isEmpty)
        }
    }

    /// Brings imported one-offs in line with `tasks.json` (`docs/VAULT-API.md`). One row per task
    /// per day (`VaultTaskID`); rows dated before today are history and never change.
    ///
    /// For each task, with F = the file's day, today D, and T = F, or D if F is past:
    /// - T's row exists: if still open and never bumped, it takes the file's title, list, deadline
    ///   and bump limit when the file's task changed since the last import (so an edit made in the
    ///   app lasts until Now.md changes it). Its day never changes.
    /// - T's row was imported and deleted in the app: it stays deleted.
    /// - No row at T: one is added, unless the task is settled. A task settles on the day of its
    ///   latest done, skipped or bumped row, or of a row deleted in the app (`settledOn`). The
    ///   routines carry a still-listed action forward to today, so a settled task stays settled
    ///   until the file schedules it again: an explicit future day, or coming back after being
    ///   gone from the file (`scheduledFor`, set to that day, earlier or later). A bumped chain owns
    ///   its own future. An OPEN row left
    ///   on a past day doesn't settle the task: it stays as that day's miss, and today gets a row.
    /// - When T has a row, any other open, never-bumped row of the task on today or later is removed
    ///   (the task moved), except today's: moved from today to a later day, today's row is left
    ///   skipped and remembered as moved (`movedTo`), "Moved to <day>" on Home. If the file brings
    ///   the task back to today, that row is un-skipped and is the task's row again.
    /// Then each `done` entry (`applyVaultDone`): its task's open row on that day is ticked at
    /// `doneAt`, even on a past day; or, with no row that day, a done row is added there. Once per
    /// task and day (`doneApplied`).
    /// A task gone from the file (and not under `done`) loses its open, never-bumped rows on today
    /// or later; everything else stays, and the task is forgotten 62 days after it left. An
    /// existing row is never inserted again (fetched by id first), so a tick can't be reset.
    ///
    /// An unreadable manifest is rebuilt from the store first (`rebuildVaultManifest`).
    /// Saves once, then writes the manifest (never before the save). Callers that may race another
    /// process hold `VaultFileLock` around it, and pass a fresh context so rows another process
    /// changed are read from the store.
    @discardableResult
    static func reconcileVaultTasks(
        _ tasks: [VaultTask],
        done: [VaultDone] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> VaultReconcileResult {
        let todayKey = dayKey(for: now, calendar: calendar)
        var result = VaultReconcileResult()

        let stored = VaultManifest.load(from: defaults)
        var manifest: VaultManifest
        if let stored {
            manifest = stored
        } else {
            manifest = try rebuildVaultManifest(
                taskIDs: tasks.map(\.id) + done.map(\.id), todayKey: todayKey, calendar: calendar, context: context
            )
            result.manifestRebuilt = true
        }

        let wanted = Set(tasks.map(\.id))
        let math = DayMath(calendar: calendar)
        let forgetBefore = math.adding(days: -62, to: todayKey)
        // `done` covers today and the 6 days before, in Munich time (the contract), even when the
        // phone is elsewhere; anything else is ignored.
        let munich = VaultTasksFile.munichCalendar
        let munichToday = dayKey(for: now, calendar: munich)
        let doneFrom = DayMath(calendar: munich).adding(days: -6, to: munichToday)
        for task in tasks {
            var entry = manifest.entries[task.id] ?? VaultManifest.Entry()
            let target = max(task.dayKey, todayKey)
            if entry.absentSince != nil {
                // Back in the file after being gone: a new scheduling, from its day.
                entry.absentSince = nil
                entry.scheduledFor = target
            }
            if task.dayKey > todayKey {
                // An explicit future day: the scheduling is that day, earlier or later than before
                // (a tick on or after it settles the task again).
                entry.scheduledFor = task.dayKey
            } else if let scheduled = entry.scheduledFor, scheduled > todayKey {
                // Was scheduled for a later day, now due today (or carried): the scheduling is
                // today, so a tick today settles it.
                entry.scheduledFor = todayKey
            }
            // Rows older than 62 days leave the manifest (they stay in the store); a settling among
            // them is kept in `settledOnTrimmed`.
            for (day, id) in entry.rows where day < forgetBefore {
                let row = try occurrence(id: id, context: context)
                if row.map({ !isOpenAndNeverBumped($0) }) ?? true {
                    entry.settledOnTrimmed = max(entry.settledOnTrimmed ?? "", day)
                }
                entry.rows[day] = nil
            }
            let targetID = VaultTaskID.occurrenceID(for: task.id, dayKey: target)
            let fileChanged = entry.fingerprint != task.fingerprint

            // The task's rows the manifest knows, by day (nil: deleted in the app).
            var known: [(day: String, row: Occurrence?)] = []
            for day in entry.rows.keys.sorted() {
                if let id = entry.rows[day] {
                    known.append((day, try occurrence(id: id, context: context)))
                }
            }
            entry.settledOn = settledDay(known, trimmed: entry.settledOnTrimmed)
            let settled = isSettled(entry)

            var hasTargetRow = false
            if let row = try occurrence(id: targetID, context: context) {
                hasTargetRow = true
                entry.rows[target] = targetID
                if isOpenAndNeverBumped(row) {
                    if fileChanged, try applyVaultFields(of: task, to: row, context: context) {
                        result.updated.append(task.id)
                    }
                } else if target == todayKey, entry.isMovedRow(row), row.bumpedToID == nil,
                          markUnskipped(row, todayKey: todayKey) {
                    // Moved later, then back to today: today's moved row is the task's row again
                    // (one row per task per day), open, with the file's fields.
                    entry.movedTo?[target] = nil
                    _ = try applyVaultFields(of: task, to: row, context: context)
                    result.updated.append(task.id)
                } else {
                    result.untouched.append(task.id)
                }
            } else if entry.rows[target] != nil {
                // T's row was imported and then deleted in the app.
                result.deletedInApp.append(task.id)
            } else if settled {
                let byDeletion = known.contains { $0.day == entry.settledOn && $0.row == nil }
                if byDeletion {
                    result.deletedInApp.append(task.id)
                } else {
                    result.untouched.append(task.id)
                }
            } else {
                try insertVaultRow(for: task, on: target, id: targetID, now: now, context: context)
                entry.rows[target] = targetID
                hasTargetRow = true
                result.added.append(task.id)
            }

            if hasTargetRow {
                // The task moved: its other open, never-bumped rows on today or later go.
                for (day, row) in known where day >= todayKey && day != target {
                    guard let row, isOpenAndNeverBumped(row), row.dayKey >= todayKey else { continue }
                    if day == todayKey, target > todayKey, markSkipped(row, todayKey: todayKey) {
                        // Moved from today to a later day: today's row stays, skipped (no credit,
                        // no miss), as "Moved to <day>"; the live task is the new row.
                        var moves = entry.movedTo ?? [:]
                        moves[todayKey] = target
                        entry.movedTo = moves
                        result.moved.append(task.id)
                        continue
                    }
                    context.delete(row)
                    entry.rows[day] = nil
                    if !result.removed.contains(task.id) { result.removed.append(task.id) }
                }
            }
            entry.fingerprint = task.fingerprint
            manifest.entries[task.id] = entry
        }

        // Done in a Claude session: ticked, not removed. Before the gone-from-file rule below,
        // which never removes a done task's rows.
        var doneIDs = Set<String>()
        for item in done where !wanted.contains(item.id) && item.dayKey >= doneFrom && item.dayKey <= munichToday {
            doneIDs.insert(item.id)
            // The app never knew the task: nothing to tick.
            guard var entry = manifest.entries[item.id] else { continue }
            // Applied once: idempotent, and a vault tick un-ticked in the app stays un-ticked.
            guard !(entry.doneApplied ?? []).contains(item.dayKey) else { continue }
            // Recorded only once final: a refused tick is tried again next time.
            if try applyVaultDone(item, to: &entry, todayKey: todayKey, munich: munich, context: context, result: &result) {
                entry.doneApplied = ((entry.doneApplied ?? []) + [item.dayKey]).sorted()
            }
            manifest.entries[item.id] = entry
        }

        for (taskID, original) in manifest.entries where !wanted.contains(taskID) {
            var entry = original
            if entry.absentSince == nil {
                entry.absentSince = todayKey
            }
            for (day, id) in original.rows where !doneIDs.contains(taskID) {
                guard let row = try occurrence(id: id, context: context) else { continue }
                if row.dayKey >= todayKey, isOpenAndNeverBumped(row) {
                    context.delete(row)
                    entry.rows[day] = nil
                    if !result.removed.contains(taskID) { result.removed.append(taskID) }
                }
            }
            if let absent = entry.absentSince, absent < forgetBefore {
                // Gone from Now.md for 62 days: forgotten (its rows stay in the store).
                manifest.entries[taskID] = nil
            } else if entry != original {
                manifest.entries[taskID] = entry
            }
        }

        // Fix round 2's bookkeeping lasts as long as `done` can name the day (applied) or the rows
        // do (ticked, moved); today's moved row follows where the task went.
        for (taskID, entry) in manifest.entries {
            var pruned = entry
            try refreshTodaysMove(&pruned, todayKey: todayKey, context: context)
            pruned.doneApplied = nonEmpty(pruned.doneApplied?.filter { $0 >= doneFrom })
            pruned.tickedByVault = nonEmpty(pruned.tickedByVault?.filter { $0.key >= forgetBefore })
            pruned.movedTo = nonEmpty(pruned.movedTo?.filter { $0.key >= forgetBefore })
            if pruned != entry {
                manifest.entries[taskID] = pruned
            }
        }

        try saveVaultChanges(context: context)
        if manifest != stored {
            manifest.save(to: defaults)
        }
        return result
    }

    /// One `done` entry (a task finished in a Claude session, already deleted from Now.md), for a
    /// task the manifest knows, on day D (Munich; today or the 6 days before):
    /// - an open row of the task on D (a bumped copy too, or today's "moved" row) is ticked at
    ///   `doneAt`, through `complete`'s rule judged in Munich time: the one change the import makes
    ///   to a past day, since it is a real completion stamped inside that day;
    /// - a row on D bumped in the app counts as done already; the open copy it was bumped to (dated
    ///   after D, today on) is removed, unlinked as when a copy is deleted;
    /// - a row on D already done or skipped is left alone (ticks win); one deleted in the app stays
    ///   deleted;
    /// - no row on D: a done row is added only when D is the app's today, on a list other than the
    ///   morning, and the task isn't settled (done before its day). Never on a past day (a row
    ///   would mark the day opened and wipe its misses) nor on the morning (a late add with a late
    ///   tick would make the morning a miss);
    /// then its open, never-bumped rows after D, from today on, are removed (it's done).
    /// A row the vault ticked is recorded in `tickedByVault`. Returns whether the outcome is final
    /// (false only when the tick was refused, so the entry is tried again on the next fetch).
    private static func applyVaultDone(
        _ item: VaultDone,
        to entry: inout VaultManifest.Entry,
        todayKey: String,
        munich: Calendar,
        context: ModelContext,
        result: inout VaultReconcileResult
    ) throws -> Bool {
        let day = item.dayKey
        let rows = try vaultRows(of: entry, context: context)
        let onDay = rows.filter { $0.dayKey == day }
        var ticked: UUID?
        var final = true
        if let row = onDay.first(where: { $0.state == .open || entry.isMovedRow($0) }) {
            if markDone(row, at: item.doneAt, calendar: munich) {
                ticked = row.id
                entry.movedTo?[row.dayKey] = nil
            } else {
                final = false
                result.untouched.append(item.id)
            }
        } else if !onDay.isEmpty {
            // Ticked, skipped or bumped in the app: wins. A bump's open copy is now stale.
            for bumped in onDay where bumped.state == .bumped {
                try removeOpenBumpedCopies(after: bumped, todayKey: todayKey, context: context, result: &result, taskID: item.id)
            }
            result.untouched.append(item.id)
        } else if entry.rows[day] != nil {
            result.deletedInApp.append(item.id)
        } else if day == todayKey,
                  try !isSettledNow(entry, context: context),
                  let template = rows.filter({ $0.dayKey > day && isOpenAndNeverBumped($0) }).min(by: { $0.dayKey < $1.dayKey })
                    ?? rows.max(by: { $0.dayKey < $1.dayKey }),
                  template.list != .morning {
            let id = VaultTaskID.occurrenceID(for: item.id, dayKey: day)
            if try occurrence(id: id, context: context) == nil {
                context.insert(Occurrence(
                    id: id,
                    list: template.list,
                    dayKey: day,
                    title: template.title,
                    sortOrder: try vaultNextSortOrder(on: day, list: template.list, context: context),
                    state: .done,
                    completedAt: item.doneAt,
                    createdAt: min(template.createdAt, item.doneAt),
                    bumpLimit: template.bumpLimit,
                    deadlineDayKey: template.deadlineDayKey
                ))
                ticked = id
            } else {
                result.untouched.append(item.id)
            }
            entry.rows[day] = id
        } else {
            result.untouched.append(item.id)
        }
        if let ticked {
            var byDay = entry.tickedByVault ?? [:]
            byDay[day] = ticked
            entry.tickedByVault = byDay
            result.ticked.append(item.id)
        }

        // Done: its later open, never-bumped rows (today on) go, as a task gone from the file.
        for (rowDay, id) in entry.rows where rowDay > day && rowDay >= todayKey {
            guard let row = try occurrence(id: id, context: context), isOpenAndNeverBumped(row) else { continue }
            context.delete(row)
            entry.rows[rowDay] = nil
            if !result.removed.contains(item.id) { result.removed.append(item.id) }
        }
        return final
    }

    /// Follows a bumped row's chain and deletes its open copies dated after it, today on, unlinked
    /// as when a copy is deleted (`unlinkBeforeDelete`): the bumped row keeps its bumped state, so
    /// its day still counts as done.
    private static func removeOpenBumpedCopies(
        after bumped: Occurrence,
        todayKey: String,
        context: ModelContext,
        result: inout VaultReconcileResult,
        taskID: String
    ) throws {
        var next = bumped.bumpedToID
        var steps = 0
        while let id = next, steps < 60, let copy = try occurrence(id: id, context: context) {
            next = copy.bumpedToID
            steps += 1
            guard copy.state == .open, copy.dayKey > bumped.dayKey, copy.dayKey >= todayKey else { continue }
            try unlinkBeforeDelete(copy, context: context)
            context.delete(copy)
            if !result.removed.contains(taskID) { result.removed.append(taskID) }
        }
    }

    /// Today's moved row says where the task went: the earliest of its rows after today, or "" when
    /// it has none any more ("No longer planned": it left the file, or its later row was removed or
    /// deleted). Run on every reconcile, so a second move updates the day.
    private static func refreshTodaysMove(_ entry: inout VaultManifest.Entry, todayKey: String, context: ModelContext) throws {
        guard entry.movedTo?[todayKey] != nil, let rowID = entry.rows[todayKey],
              let row = try occurrence(id: rowID, context: context), entry.isMovedRow(row) else { return }
        var live = ""
        for day in entry.rows.keys.sorted() where day > todayKey {
            if let id = entry.rows[day], try occurrence(id: id, context: context) != nil {
                live = day
                break
            }
        }
        entry.movedTo?[todayKey] = live
    }

    /// Every row of a task: its imported rows and the copies bumped from them.
    private static func vaultRows(of entry: VaultManifest.Entry, context: ModelContext) throws -> [Occurrence] {
        var seen = Set<UUID>()
        var rows: [Occurrence] = []
        for start in entry.rows.keys.sorted().compactMap({ entry.rows[$0] }) {
            var next: UUID? = start
            var steps = 0
            while let id = next, steps < 60, seen.insert(id).inserted, let row = try occurrence(id: id, context: context) {
                rows.append(row)
                next = row.bumpedToID
                steps += 1
            }
        }
        return rows
    }

    /// The day the task settled: its latest done, skipped or bumped row, or row deleted in the app
    /// (`row` nil), or the latest such day among trimmed rows.
    private static func settledDay(_ known: [(day: String, row: Occurrence?)], trimmed: String?) -> String? {
        (known.filter { $0.row.map { !isOpenAndNeverBumped($0) } ?? true }.map(\.day) + [trimmed].compactMap { $0 }).max()
    }

    /// `isSettled`, from the rows as they are now (a task under `done` isn't in the file, so its
    /// `settledOn` is from its last import).
    private static func isSettledNow(_ entry: VaultManifest.Entry, context: ModelContext) throws -> Bool {
        var current = entry
        var known: [(day: String, row: Occurrence?)] = []
        for day in entry.rows.keys.sorted() {
            if let id = entry.rows[day] {
                known.append((day, try occurrence(id: id, context: context)))
            }
        }
        current.settledOn = settledDay(known, trimmed: entry.settledOnTrimmed)
        return isSettled(current)
    }

    /// Settled on or after its latest scheduling: no new row is added.
    private static func isSettled(_ entry: VaultManifest.Entry) -> Bool {
        entry.settledOn.map { $0 >= (entry.scheduledFor ?? "") } ?? false
    }

    private static func nonEmpty<C: Collection>(_ collection: C?) -> C? {
        collection.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Rebuilds the manifest from the store when it can't be read: per-day ids are computable, so
    /// for each task in the file it fetches the rows whose ids are `vault-task:<id>:<day>` for days
    /// from 62 days ago to 60 days ahead, in one fetch. Done, skipped and bumped rows settle their
    /// tasks again on the normal pass; which rows were deleted in the app is lost, and so are the
    /// last-import fingerprints (an open row takes the file's fields once).
    static func rebuildVaultManifest(
        taskIDs: [String],
        todayKey: String,
        calendar: Calendar,
        context: ModelContext
    ) throws -> VaultManifest {
        let math = DayMath(calendar: calendar)
        let days = (-62...60).map { math.adding(days: $0, to: todayKey) }
        var lookup: [UUID: (taskID: String, day: String)] = [:]
        for taskID in taskIDs {
            for day in days {
                lookup[VaultTaskID.occurrenceID(for: taskID, dayKey: day)] = (taskID, day)
            }
        }
        let ids = Array(lookup.keys)
        let rows = try context.fetch(FetchDescriptor<Occurrence>(predicate: #Predicate { ids.contains($0.id) }))
        var manifest = VaultManifest()
        for row in rows {
            guard let match = lookup[row.id] else { continue }
            manifest.entries[match.taskID, default: VaultManifest.Entry()].rows[match.day] = row.id
        }
        AppLogger.vault.error("Vault manifest rebuilt from \(rows.count, privacy: .public) rows")
        return manifest
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
    /// then done counts on the day it was done. Rows the vault ticked for a `done` entry are left
    /// out: they are already deleted from Now.md.
    static func vaultTasksDone(
        from startKey: String,
        through endKey: String,
        context: ModelContext,
        defaults: UserDefaults
    ) throws -> [String: [VaultHabits.DoneTask]] {
        var byDay: [String: [VaultHabits.DoneTask]] = [:]
        var seen = Set<UUID>()
        var countedTaskDays = Set<String>()
        let manifest = VaultManifest.load(from: defaults) ?? VaultManifest()
        // Ticked by the vault for a `done` entry: already deleted from Now.md, so not proposed.
        let tickedByVault = manifest.tickedByVaultIDs
        for (taskID, entry) in manifest.entries {
            for start in entry.rows.values {
                var next: UUID? = start
                var steps = 0
                while let id = next, steps < 60, seen.insert(id).inserted, let row = try occurrence(id: id, context: context) {
                    // Once per task per day, however many of its rows reach that day's tick.
                    if row.state == .done, !tickedByVault.contains(row.id), row.dayKey >= startKey, row.dayKey <= endKey,
                       countedTaskDays.insert("\(taskID)|\(row.dayKey)").inserted {
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
            // Bonus rows (added after the morning's cutoff) never count, here as everywhere.
            let rows = try countedRows(
                try occurrences(from: startKey, through: targetKey, list: list, context: context),
                history: history, context: context, calendar: calendar
            )
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
