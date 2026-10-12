import Foundation
import SwiftData

/// Item: a recurring thing on one of the three lists (schema V2).
///
/// It exists from `startDayKey` (the day it was created) onwards; deleting it sets `endDayKey`
/// and it stops from that day on, while earlier days keep their occurrences. Days link to it by
/// `id`, never by title. Enums are stored as raw values.
@Model
final class Item {
    @Attribute(.unique)
    var id: UUID
    var listRaw: String
    var title: String
    var sortOrder: Int
    var repeatKindRaw: String
    var repeatInterval: Int
    /// Bit 0 = Sunday … bit 6 = Saturday.
    var repeatWeekdayMask: Int
    var startDayKey: String
    /// The first day the item no longer appears on (set on delete).
    var endDayKey: String?
    /// Copied onto each occurrence. Repeating occurrences are also held to their period end.
    var defaultBumpLimitRaw: String
    var defaultBumpLimitDays: Int
    /// When Liam added the item. A repeat change's replacement keeps its predecessor's
    /// (`ListService.updateItem`), so this is when the thing was first added: the bonus rule reads
    /// it (`ListRules.isBonus`).
    var createdAt: Date

    init(
        id: UUID = UUID(),
        list: ListKind,
        title: String,
        sortOrder: Int,
        repeatRule: RepeatRule,
        startDayKey: String,
        endDayKey: String? = nil,
        defaultBumpLimit: BumpLimit = .unlimited,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.listRaw = list.rawValue
        self.title = title
        self.sortOrder = sortOrder
        self.repeatKindRaw = repeatRule.kind.rawValue
        self.repeatInterval = repeatRule.interval
        self.repeatWeekdayMask = repeatRule.weekdayMask
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.defaultBumpLimitRaw = defaultBumpLimit.kind.rawValue
        self.defaultBumpLimitDays = defaultBumpLimit.storedDays
        self.createdAt = createdAt
    }

    var list: ListKind {
        ListKind(rawValue: listRaw) ?? .day
    }

    var repeatRule: RepeatRule {
        get { RepeatRule(kindRaw: repeatKindRaw, interval: repeatInterval, weekdayMask: repeatWeekdayMask) }
        set {
            repeatKindRaw = newValue.kind.rawValue
            repeatInterval = newValue.interval
            repeatWeekdayMask = newValue.weekdayMask
        }
    }

    /// Items don't carry a deadline date, so `untilDeadline` isn't offered here.
    var defaultBumpLimit: BumpLimit {
        BumpLimit(kindRaw: defaultBumpLimitRaw, days: defaultBumpLimitDays, deadlineDayKey: nil)
    }

    var schedule: ListRules.ItemSchedule {
        ListRules.ItemSchedule(itemID: id, rule: repeatRule, startDayKey: startDayKey, endDayKey: endDayKey, createdAt: createdAt)
    }

    /// Whether the item exists on `dayKey` (whether it falls due there is the repeat rule's call).
    func isActive(on dayKey: String) -> Bool {
        guard dayKey >= startDayKey else { return false }
        if let endDayKey {
            return dayKey < endDayKey
        }
        return true
    }
}
