import Foundation
import SwiftData
import os
import SwiftUI

/// User-driven write operations for `HomeViewModel`, all through `ListService`.
/// Includes completion, bumping, add/reorder, and post-mutation refresh/reload coordination.
extension HomeViewModel {
    func toggleMorningEntry(_ entry: Occurrence, context: ModelContext) {
        guard canComplete(day: selectedDay), movedTo(entry) == nil else { return }

        write("Toggle morning item", context: context) {
            if entry.isCompleted {
                _ = try ListService.uncomplete(entry, context: context)
            } else {
                _ = try ListService.complete(entry, at: now, context: context)
            }
        }
        finishMutation(context: context)

        // A finished morning moves on to whichever list the time picks (day, or evening).
        if HomeModel.isToday(selectedDay, now: now), morningCompletionState.isComplete {
            manualListFlip = nil
            contextualList = automaticContextualList
        }
    }

    /// Ticks or unticks a task. Unticking a bumped task un-bumps it (removes tomorrow's copy).
    func toggleDailyTask(_ task: Occurrence, context: ModelContext) {
        guard canComplete(day: selectedDay), movedTo(task) == nil else { return }

        write("Toggle daily task", context: context) {
            if task.isCompleted {
                _ = try ListService.uncomplete(task, context: context)
            } else {
                _ = try ListService.complete(task, at: now, context: context)
            }
        }
        finishMutation(context: context)
    }

    /// A forgotten tick on a past day, any list, after retyping the title (fix round 3). Stamped
    /// by `BackfillRules`: the day and evening at 23:59:59, a counted morning row just before that
    /// day's deadline.
    @discardableResult
    func completePastOccurrence(
        _ occurrence: Occurrence,
        typedConfirmation: String,
        context: ModelContext
    ) -> Bool {
        guard canCompletePast(occurrence) else { return false }
        guard BackfillRules.confirms(typedConfirmation, title: occurrence.title) else { return false }
        guard let stamp = BackfillRules.stamp(
            list: occurrence.list,
            dayKey: occurrence.dayKey,
            rules: dayRulesHistory.rules(for: occurrence.dayKey),
            isBonus: isBonus(occurrence)
        ) else { return false }

        let didComplete = write("Complete past occurrence", context: context) {
            try ListService.complete(occurrence, at: stamp, context: context)
        } ?? false
        finishMutation(context: context)
        return didComplete
    }

    /// Adds a one-off to the day list with the add menu's options, then resets them.
    @discardableResult
    func addDailyTask(context: ModelContext) -> Bool {
        guard canManage(day: selectedDay) else { return false }

        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let options = newTaskOptions
        let added: Occurrence? = write("Create daily task", context: context) {
            try createDailyTask(selectedDay, title, options, context)
        } ?? nil
        guard added != nil else { return false }

        newTaskTitle = ""
        newTaskOptions = OneOffOptions()
        finishMutation(context: context)
        return true
    }

    /// Bumps to tomorrow with the title typed in the bump sheet. With Retype to bump on, nothing
    /// typed means no bump (`BumpRules.bumpedTitle`). Returns whether it bumped.
    @discardableResult
    func bump(_ occurrence: Occurrence, typedTitle: String, context: ModelContext) -> Bool {
        guard canManage(day: selectedDay) else { return false }
        guard canBump(occurrence) else { return false }
        guard let title = BumpRules.bumpedTitle(typed: typedTitle, original: occurrence.title, retypeRequired: retypeToBump) else {
            return false
        }

        let moved: Occurrence? = write("Bump task", context: context) {
            try ListService.bump(occurrence, newTitle: title, now: now, context: context)
        } ?? nil
        finishMutation(context: context)
        return moved != nil
    }

    /// Skip today (recurring rows): it drops out of the day's count.
    func skip(_ occurrence: Occurrence, context: ModelContext) {
        guard canComplete(day: selectedDay), occurrence.isRepeating else { return }
        write("Skip", context: context) {
            _ = try ListService.skip(occurrence, todayKey: HomeModel.dayKey(for: now), context: context)
        }
        finishMutation(context: context)
    }

    func unskip(_ occurrence: Occurrence, context: ModelContext) {
        guard canComplete(day: selectedDay), movedTo(occurrence) == nil else { return }
        write("Undo skip", context: context) {
            _ = try ListService.unskip(occurrence, todayKey: HomeModel.dayKey(for: now), context: context)
        }
        finishMutation(context: context)
    }

    /// Delete from the row menu, after its confirmation: a one-off goes; a recurring row deletes
    /// its item from today on (as in Edit lists), keeping earlier days.
    func delete(_ occurrence: Occurrence, context: ModelContext) {
        guard canManage(day: selectedDay) else { return }
        let todayKey = HomeModel.dayKey(for: now)
        write("Delete", context: context) {
            if let itemID = occurrence.itemID {
                if let item = try ListService.item(id: itemID, context: context) {
                    try ListService.deleteItem(item, todayKey: todayKey, context: context)
                }
            } else {
                _ = try ListService.deleteOneOff(occurrence, todayKey: todayKey, context: context)
            }
        }
        finishMutation(context: context)
    }

    /// Edit… on a one-off: this row only.
    func editOneOff(
        _ occurrence: Occurrence,
        title: String,
        bumpLimit: BumpLimit,
        deadlineDayKey: String?,
        context: ModelContext
    ) {
        guard canManage(day: selectedDay) else { return }
        write("Edit one-off", context: context) {
            _ = try ListService.editOneOff(
                occurrence, title: title, bumpLimit: bumpLimit, deadlineDayKey: deadlineDayKey,
                todayKey: HomeModel.dayKey(for: now), context: context
            )
        }
        finishMutation(context: context)
    }

    /// After the item editor saved (it writes through `ListService` itself).
    func itemsDidChange(context: ModelContext) {
        finishMutation(context: context)
    }

    func reorderDailyTask(
        draggedID: UUID,
        over targetID: UUID,
        context: ModelContext
    ) {
        guard draggedID != targetID else { return }
        guard let fromIndex = dailyTasks.firstIndex(where: { $0.id == draggedID }) else { return }
        guard let toIndex = dailyTasks.firstIndex(where: { $0.id == targetID }) else { return }
        guard fromIndex != toIndex else { return }

        var updated = dailyTasks
        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        updated.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
        write("Reorder daily tasks", context: context) {
            try ListService.reorderOneOffs(updated, context: context)
        }
        finishMutation(context: context)
    }

    private func finishMutation(context: ModelContext) {
        refresh(context: context)
        reloadWidget()
    }

    private func canComplete(day: Date) -> Bool {
        HomeModel.isToday(day, now: now)
    }

    private func canManage(day: Date) -> Bool {
        !HomeModel.isPastDay(day, now: now)
    }
}
