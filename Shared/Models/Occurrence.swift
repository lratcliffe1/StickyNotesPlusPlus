import Foundation
import SwiftData

/// Occurrence: what is on a list on a given day (schema V2). Either an instance of an `Item`
/// (`itemID` set) or a one-off (`itemID` nil).
///
/// - `title` is a snapshot: renaming an item changes today's and later occurrences only.
/// - A bump marks this row `bumped` and creates the next day's row, linked both ways
///   (`bumpedToID` / `bumpedFromID`), with `bumpCount + 1`. `firstAddedDayKey` and
///   `firstAddedTitle` stay those of the first row in the chain ("first added Mon as …").
/// - An item occurrence's id is derived from (item, scheduled day) (`OccurrenceID`), so it can only
///   be created once, whichever process gets there first.
/// - Repeating occurrences remember the day they were scheduled for (`scheduledDayKey`) and the
///   last day they may be bumped to (`periodEndDayKey`); a bumped copy keeps both.
/// Enums are stored as raw values.
@Model
final class Occurrence {
    @Attribute(.unique)
    var id: UUID
    var itemID: UUID?
    var listRaw: String
    var dayKey: String
    var title: String
    var sortOrder: Int
    var stateRaw: String
    var completedAt: Date?
    var createdAt: Date
    var bumpLimitRaw: String
    var bumpLimitDays: Int
    /// An optional deadline, independent of the bump limit (a one-off can have a deadline and
    /// "up to 3 days"). The `untilDeadline` limit reads it.
    var deadlineDayKey: String?
    var bumpedFromID: UUID?
    var bumpedToID: UUID?
    var bumpCount: Int
    var firstAddedDayKey: String
    var firstAddedTitle: String
    var scheduledDayKey: String?
    var periodEndDayKey: String?

    init(
        id: UUID = UUID(),
        itemID: UUID? = nil,
        list: ListKind,
        dayKey: String,
        title: String,
        sortOrder: Int = 0,
        state: OccurrenceState = .open,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        bumpLimit: BumpLimit = .defaultForNewOneOffs,
        deadlineDayKey: String? = nil,
        bumpedFromID: UUID? = nil,
        bumpedToID: UUID? = nil,
        bumpCount: Int = 0,
        firstAddedDayKey: String? = nil,
        firstAddedTitle: String? = nil,
        scheduledDayKey: String? = nil,
        periodEndDayKey: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.listRaw = list.rawValue
        self.dayKey = dayKey
        self.title = title
        self.sortOrder = sortOrder
        self.stateRaw = state.rawValue
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.bumpLimitRaw = bumpLimit.kind.rawValue
        self.bumpLimitDays = bumpLimit.storedDays
        self.deadlineDayKey = bumpLimit.storedDeadlineDayKey ?? deadlineDayKey
        self.bumpedFromID = bumpedFromID
        self.bumpedToID = bumpedToID
        self.bumpCount = bumpCount
        self.firstAddedDayKey = firstAddedDayKey ?? dayKey
        self.firstAddedTitle = firstAddedTitle ?? title
        self.scheduledDayKey = scheduledDayKey
        self.periodEndDayKey = periodEndDayKey
    }

    var list: ListKind {
        ListKind(rawValue: listRaw) ?? .day
    }

    var state: OccurrenceState {
        get { OccurrenceState(rawValue: stateRaw) ?? .open }
        set { stateRaw = newValue.rawValue }
    }

    var bumpLimit: BumpLimit {
        get { BumpLimit(kindRaw: bumpLimitRaw, days: bumpLimitDays, deadlineDayKey: deadlineDayKey) }
        set {
            bumpLimitRaw = newValue.kind.rawValue
            bumpLimitDays = newValue.storedDays
            // Only an `untilDeadline` limit sets the deadline; other limits leave it alone.
            if let deadline = newValue.storedDeadlineDayKey {
                deadlineDayKey = deadline
            }
        }
    }

    /// Done, or bumped (which counts as done for its day). Drives the strike-through.
    var isCompleted: Bool {
        state.countsAsDone
    }

    var isRepeating: Bool {
        itemID != nil
    }
}

extension Occurrence: OccurrenceFacts {
    /// A one-off whose id follows the `vault-task:` scheme (`VaultTaskID`): imported from
    /// `tasks.json`. Item rows have name-based ids too (`OccurrenceID`), hence the one-off check.
    var isImported: Bool {
        itemID == nil && VaultTaskID.isNameBased(id)
    }
}
