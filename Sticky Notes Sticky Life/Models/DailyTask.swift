import Foundation
import SwiftData

/// DailyTask — task tied to a specific day
/// Spec fields:
/// - id: UUID
/// - date: Date (normalized)
/// - title: String
/// - isCompleted: Bool
/// - completedAt: Date?
/// - bumpCount: Int
/// - isBumpable: Bool
@Model
final class DailyTask {
    @Attribute(.unique)
    var id: UUID
    var date: Date
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var bumpCount: Int
    var isBumpable: Bool

    /// Initializes a DailyTask. The `date` is normalized to the start of day in the current calendar/timezone.
    init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        bumpCount: Int = 0,
        isBumpable: Bool = true
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.bumpCount = bumpCount
        self.isBumpable = isBumpable
    }
}
