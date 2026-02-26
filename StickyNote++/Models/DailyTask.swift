import Foundation
import SwiftData

/// DailyTask — task tied to a specific day
/// Spec fields:
/// - id: UUID
/// - date: Date (normalized)
/// - dayKey: String (stable YYYY-MM-DD day identity)
/// - title: String
/// - isCompleted: Bool
/// - completedAt: Date?
/// - bumpCount: Int
/// - isBumpable: Bool
/// - bumpedTaskID: UUID?
@Model
final class DailyTask {
    @Attribute(.unique)
    var id: UUID
    var date: Date
    var dayKey: String = ""
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var bumpCount: Int
    var isBumpable: Bool
    var bumpedTaskID: UUID?

    /// Initializes a DailyTask. The `date` is normalized to the start of day in the current calendar/timezone.
    init(
        id: UUID = UUID(),
        date: Date,
        dayKey: String? = nil,
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        bumpCount: Int = 0,
        isBumpable: Bool = true,
        bumpedTaskID: UUID? = nil
    ) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        self.id = id
        self.date = normalizedDate
        self.dayKey = dayKey ?? HomeModel.dayKey(for: normalizedDate)
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.bumpCount = bumpCount
        self.isBumpable = isBumpable
        self.bumpedTaskID = bumpedTaskID
    }
}
