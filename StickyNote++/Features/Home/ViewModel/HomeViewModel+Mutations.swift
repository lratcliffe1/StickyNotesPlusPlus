import Foundation
import SwiftData
import os
import SwiftUI

extension HomeViewModel {
    func toggleMorningEntry(_ entry: MorningRoutineEntry, context: ModelContext) {
        guard canComplete(day: selectedDay) else { return }

        entry.isCompleted.toggle()
        entry.completedAt = entry.isCompleted ? now : nil
        finishMutation(context: context)

        if HomeModel.isToday(selectedDay, now: now),
           HomeModel.morningCompletion(entries: morningEntries).value >= 1.0 {
            manualContextualListOverride = nil
            contextualList = .daily
        }
    }

    func toggleDailyTask(_ task: DailyTask, context: ModelContext) {
        guard canComplete(day: selectedDay) else { return }

        if task.isCompleted, let bumpedTaskID = task.bumpedTaskID {
            task.isCompleted = false
            task.completedAt = nil
            task.bumpedTaskID = nil

            if let bumpedTask = fetchDailyTask(id: bumpedTaskID, context: context) {
                context.delete(bumpedTask)
            }

            finishMutation(context: context)
            return
        }

        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? now : nil
        finishMutation(context: context)
    }

    @discardableResult
    func completePastDailyTask(
        _ task: DailyTask,
        typedConfirmation: String,
        context: ModelContext
    ) -> Bool {
        guard HomeModel.isPastDay(selectedDay, now: now) else { return false }
        guard !task.isCompleted else { return false }
        guard typedConfirmation == task.title else { return false }

        let calendar = Calendar.current
        let taskDay = HomeModel.date(fromDayKey: task.dayKey, calendar: calendar)
            ?? HomeModel.normalizedDay(task.date, calendar: calendar)
        let endOfTaskDay = endOfDay(for: taskDay, calendar: calendar)

        task.isCompleted = true
        task.completedAt = endOfTaskDay
        finishMutation(context: context)
        return true
    }

    @discardableResult
    func addDailyTask(context: ModelContext, mustHappenToday: Bool = false) -> Bool {
        guard canManage(day: selectedDay) else { return false }

        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        do {
            _ = try createDailyTask(selectedDay, title, mustHappenToday, context)
        } catch {
            AppLogger.persistence.error("Create daily task failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        newTaskTitle = ""
        finishMutation(context: context)
        return true
    }

    func bumpTaskToTomorrow(
        _ task: DailyTask,
        bumpedTitle: String,
        context: ModelContext
    ) {
        guard canManage(day: selectedDay) else { return }
        guard task.isBumpable, !task.isCompleted else { return }
        guard task.bumpedTaskID == nil else { return }

        let trimmedTitle = bumpedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let calendar = Calendar.current
        let taskDay = HomeModel.date(fromDayKey: task.dayKey, calendar: calendar)
            ?? HomeModel.normalizedDay(task.date, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: taskDay) ?? taskDay

        let bumpedTask = DailyTask(
            date: HomeModel.normalizedDay(tomorrow, calendar: calendar),
            title: trimmedTitle,
            isCompleted: false,
            completedAt: nil,
            sortOrder: nextSortOrder(for: tomorrow, insertAtTop: false, context: context),
            bumpCount: task.bumpCount + 1,
            isBumpable: task.isBumpable
        )

        context.insert(bumpedTask)
        task.isCompleted = true
        task.completedAt = now
        task.bumpedTaskID = bumpedTask.id
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
        applyDailyTaskOrder(updated, context: context)
    }

    private func applyDailyTaskOrder(_ orderedTasks: [DailyTask], context: ModelContext) {
        for (index, task) in orderedTasks.enumerated() where task.sortOrder != index {
            task.sortOrder = index
        }

        dailyTasks = orderedTasks
        finishMutation(context: context)
    }

    private func nextSortOrder(for day: Date, insertAtTop: Bool, context: ModelContext) -> Int {
        do {
            return try repository.nextSortOrder(for: day, insertAtTop: insertAtTop, context: context)
        } catch {
            AppLogger.persistence.error("Compute next sort order failed: \(error.localizedDescription, privacy: .public)")
            return insertAtTop ? -1 : 0
        }
    }

    private func finishMutation(context: ModelContext) {
        save(context: context)
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
