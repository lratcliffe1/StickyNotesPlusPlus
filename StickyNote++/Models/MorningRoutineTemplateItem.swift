import Foundation
import SwiftData

/// MorningRoutineTemplateItem — editable routine definition in Settings
/// Spec fields:
/// - id: UUID
/// - title: String
/// - sortOrder: Int
/// - targetTime: DateComponents?
@Model
final class MorningRoutineTemplateItem {
    var id: UUID
    var title: String
    var sortOrder: Int
    var targetHour: Int16?
    var targetMinute: Int16?
    
    init(
        id: UUID = UUID(),
        title: String,
        sortOrder: Int,
        targetTime: DateComponents? = nil
    ) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.targetHour = targetTime?.hour.map(Int16.init)
        self.targetMinute = targetTime?.minute.map(Int16.init)
    }
    
    /// Convenience computed property (NOT persisted)
    var targetTime: DateComponents? {
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

