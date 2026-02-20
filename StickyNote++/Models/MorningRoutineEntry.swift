import Foundation
import SwiftData

/// MorningRoutineEntry — per-day instance of a morning item
/// Spec fields:
/// - id: UUID
/// - date: Date (normalized start-of-day, local timezone)
/// - titleSnapshot: String
/// - sortOrderSnapshot: Int
/// - targetTimeSnapshot: DateComponents?
/// - isCompleted: Bool
/// - completedAt: Date?
@Model
final class MorningRoutineEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var titleSnapshot: String
    var sortOrderSnapshot: Int
    var targetHour: Int16?
    var targetMinute: Int16?
    var isCompleted: Bool
    var completedAt: Date?

    /// Initializes a MorningRoutineEntry. The `date` is normalized to the start of day in the current calendar/timezone.
    init(
        id: UUID = UUID(),
        date: Date,
        titleSnapshot: String,
        sortOrderSnapshot: Int = 0,
        targetTimeSnapshot: DateComponents? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.titleSnapshot = titleSnapshot
        self.sortOrderSnapshot = sortOrderSnapshot
        self.targetHour = targetTimeSnapshot?.hour.map(Int16.init)
        self.targetMinute = targetTimeSnapshot?.minute.map(Int16.init)
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    /// Convenience computed property (not persisted)
    var targetTimeSnapshot: DateComponents? {
        get {
            guard let h = targetHour, let m = targetMinute else { return nil }
            return DateComponents(hour: Int(h), minute: Int(m))
        }
        set {
            targetHour = newValue?.hour.map(Int16.init)
            targetMinute = newValue?.minute.map(Int16.init)
        }
    }
}
