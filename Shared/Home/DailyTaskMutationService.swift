import Foundation
import SwiftData

enum DailyTaskMutationService {
    @discardableResult
    static func createTask(
        for day: Date,
        title: String,
        mustHappenToday: Bool,
        context: ModelContext,
        saveImmediately: Bool
    ) throws -> DailyTask {
        let normalizedDay = HomeModel.normalizedDay(day)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortOrder = try HomeDataStore.nextSortOrder(
            for: normalizedDay,
            insertAtTop: mustHappenToday,
            context: context
        )

        let task = DailyTask(
            date: normalizedDay,
            title: trimmedTitle,
            sortOrder: sortOrder,
            isBumpable: !mustHappenToday
        )
        context.insert(task)

        if saveImmediately {
            try context.save()
        }

        return task
    }
}
