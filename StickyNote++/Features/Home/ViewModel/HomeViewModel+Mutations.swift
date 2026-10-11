import Foundation
import SwiftData
import os
import SwiftUI

/// User-driven write operations for `HomeViewModel`, all through `ListService`.
/// Includes completion, bumping, add/reorder, and post-mutation refresh/reload coordination.
extension HomeViewModel {
    func toggleMorningEntry(_ entry: Occurrence, context: ModelContext) {
        guard canComplete(day: selectedDay) else { return }

        write("Toggle morning item", context: context) {
            if entry.isCompleted {
                _ = try ListService.uncomplete(entry, context: context)
            } else {
                _ = try ListService.complete(entry, at: now, context: context)
            }
        }
        finishMutation(context: context)

        if HomeModel.isToday(selectedDay, now: now), morningCompletionState.isComplete {
            manualContextualListOverride = nil
            contextualList = .daily
        }
    }

    /// Ticks or unticks a task. Unticking a bumped task un-bumps it (removes tomorrow's copy).
    func toggleDailyTask(_ task: Occurrence, context: ModelContext) {
        guard canComplete(day: selectedDay) else { return }

        write("Toggle daily task", context: context) {
            if task.isCompleted {
                _ = try ListService.uncomplete(task, context: context)
            } else {
                _ = try ListService.complete(task, at: now, context: context)
            }
        }
        finishMutation(context: context)
    }

    @discardableResult
    func completePastDailyTask(
        _ task: Occurrence,
        typedConfirmation: String,
        context: ModelContext
    ) -> Bool {
        guard HomeModel.isPastDay(selectedDay, now: now) else { return false }
        guard task.state == .open else { return false }
        guard typedConfirmation == task.title else { return false }

        let calendar = Calendar.current
        let taskDay = HomeModel.date(fromDayKey: task.dayKey, calendar: calendar)
            ?? HomeModel.normalizedDay(selectedDay, calendar: calendar)
        let endOfTaskDay = endOfDay(for: taskDay, calendar: calendar)

        let didComplete = write("Complete past task", context: context) {
            try ListService.complete(task, at: endOfTaskDay, context: context)
        } ?? false
        finishMutation(context: context)
        return didComplete
    }

    @discardableResult
    func addDailyTask(context: ModelContext, mustHappenToday: Bool = false) -> Bool {
        guard canManage(day: selectedDay) else { return false }

        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let added: Occurrence? = write("Create daily task", context: context) {
            try createDailyTask(selectedDay, title, mustHappenToday, context)
        } ?? nil
        guard added != nil else { return false }

        newTaskTitle = ""
        finishMutation(context: context)
        return true
    }

    func bumpTaskToTomorrow(
        _ task: Occurrence,
        bumpedTitle: String,
        context: ModelContext
    ) {
        guard canManage(day: selectedDay) else { return }
        guard canBump(task) else { return }

        let trimmedTitle = bumpedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        write("Bump task", context: context) {
            _ = try ListService.bump(task, newTitle: trimmedTitle, now: now, context: context)
        }
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

    private func endOfDay(for day: Date, calendar: Calendar) -> Date {
        let start = HomeModel.normalizedDay(day, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return next.addingTimeInterval(-1)
    }
}
