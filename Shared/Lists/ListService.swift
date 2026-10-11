import Foundation
import SwiftData

/// The one write path for lists, used by the app and the widget for every write, plus the
/// queries they read through. Rules live in `RepeatRule`, `BumpRules` and `ListRules`.
///
/// - Call `prepare` before reading anything: it runs the one-time V1 → V2 copy, then makes sure
///   today's occurrences exist.
/// - Only today's item occurrences are created, when today is first read. Past days are never
///   back-filled and future days never pre-created (one-offs can still be added for any day).
/// - Every mutation saves before it returns.
enum ListService {
    // MARK: - Start of every read

    static func prepare(
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = SharedPersistence.sharedDefaults
    ) throws {
        try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: calendar)
        try ensureOccurrences(on: dayKey(for: now, calendar: calendar), context: context, now: now, calendar: calendar)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        HomeModel.dayKey(for: date, calendar: calendar)
    }

    /// Creates the occurrences of every item due on `dayKey` that aren't there yet. Safe to call
    /// any number of times: an item gets one scheduled row per day. If two exist anyway (the app and
    /// the widget racing), keeps the most progressed one and deletes the rest. Rows bumped in from
    /// an earlier day don't count as that day's scheduled row.
    @discardableResult
    static func ensureOccurrences(
        on dayKey: String,
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Bool {
        let items = try context.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\.sortOrder)]))
        let key = dayKey
        let existing = try context.fetch(FetchDescriptor<Occurrence>(predicate: #Predicate { $0.dayKey == key }))
        var didChange = false

        var scheduledByItem: [UUID: [Occurrence]] = [:]
        for row in existing where (row.scheduledDayKey ?? row.dayKey) == row.dayKey {
            if let itemID = row.itemID {
                scheduledByItem[itemID, default: []].append(row)
            }
        }
        for rows in scheduledByItem.values where rows.count > 1 {
            guard let keep = ListRules.preferredDuplicate(rows) else { continue }
            for row in rows where row.id != keep.id {
                try unlinkBeforeDelete(row, context: context)
                context.delete(row)
                didChange = true
            }
        }

        for item in items where scheduledByItem[item.id] == nil && item.isActive(on: dayKey) {
            guard item.repeatRule.occurs(on: dayKey, startDayKey: item.startDayKey, calendar: calendar) else { continue }
            context.insert(makeOccurrence(for: item, on: dayKey, now: now, calendar: calendar))
            didChange = true
        }

        if didChange {
            try context.save()
        }
        return didChange
    }

    // MARK: - Queries

    /// One list's occurrences on a day, in display order.
    static func occurrences(on dayKey: String, list: ListKind, context: ModelContext) throws -> [Occurrence] {
        let key = dayKey
        let raw = list.rawValue
        let descriptor = FetchDescriptor<Occurrence>(predicate: #Predicate { $0.dayKey == key && $0.listRaw == raw })
        return ListRules.ordered(try context.fetch(descriptor))
    }

    /// One list's occurrences from `startKey` through `endKey`, sorted by day.
    static func occurrences(
        from startKey: String,
        through endKey: String,
        list: ListKind,
        context: ModelContext
    ) throws -> [Occurrence] {
        let start = startKey
        let end = endKey
        let raw = list.rawValue
        let descriptor = FetchDescriptor<Occurrence>(
            predicate: #Predicate { $0.dayKey >= start && $0.dayKey <= end && $0.listRaw == raw },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        return try context.fetch(descriptor)
    }

    /// Every occurrence of one list up to and including `endKey` (streaks walk the whole history).
    static func occurrences(through endKey: String, list: ListKind, context: ModelContext) throws -> [Occurrence] {
        let end = endKey
        let raw = list.rawValue
        let descriptor = FetchDescriptor<Occurrence>(
            predicate: #Predicate { $0.dayKey <= end && $0.listRaw == raw },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        return try context.fetch(descriptor)
    }

    static func occurrence(id: UUID, context: ModelContext) throws -> Occurrence? {
        let target = id
        var descriptor = FetchDescriptor<Occurrence>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// A list's items, in their set order. With `activeOn`, only those that exist on that day.
    static func items(in list: ListKind, activeOn dayKey: String? = nil, context: ModelContext) throws -> [Item] {
        let raw = list.rawValue
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.listRaw == raw },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let all = try context.fetch(descriptor)
        guard let dayKey else { return all }
        return all.filter { $0.isActive(on: dayKey) }
    }

    /// One list's streak through `anchorKey` (DECISIONS.md, "streak rules"). The morning list keeps
    /// its cutoff; the day and evening lists count until midnight.
    static func streakState(
        for list: ListKind,
        through anchorKey: String,
        morningMode: HomeModel.MorningMode,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> HomeModel.StreakState {
        let rows = try occurrences(through: anchorKey, list: list, context: context)
        return ListRules.streakState(through: anchorKey, occurrences: rows) { key in
            guard list == .morning, let day = HomeModel.date(fromDayKey: key, calendar: calendar) else { return nil }
            return HomeModel.morningDeadline(for: day, mode: morningMode, calendar: calendar)
        }
    }

    // MARK: - Completing, skipping

    /// Marks an open (or skipped) occurrence done at `date`.
    @discardableResult
    static func complete(_ occurrence: Occurrence, at date: Date, context: ModelContext) throws -> Bool {
        guard occurrence.state == .open || occurrence.state == .skipped else { return false }
        occurrence.state = .done
        occurrence.completedAt = date
        try context.save()
        return true
    }

    /// Back to open. A bumped occurrence is un-bumped: the next day's copy is removed, as long as
    /// it is still open and hasn't moved on itself.
    @discardableResult
    static func uncomplete(_ occurrence: Occurrence, context: ModelContext) throws -> Bool {
        switch occurrence.state {
        case .open:
            return false
        case .done, .skipped:
            break
        case .bumped:
            if let nextID = occurrence.bumpedToID, let next = try self.occurrence(id: nextID, context: context) {
                guard next.state == .open, next.bumpedToID == nil else { return false }
                context.delete(next)
            }
            occurrence.bumpedToID = nil
        }
        occurrence.state = .open
        occurrence.completedAt = nil
        try context.save()
        return true
    }

    /// Skips an open occurrence: it drops out of the day's count.
    @discardableResult
    static func skip(_ occurrence: Occurrence, context: ModelContext) throws -> Bool {
        guard occurrence.state == .open else { return false }
        occurrence.state = .skipped
        occurrence.completedAt = nil
        try context.save()
        return true
    }

    // MARK: - Bumping

    static func canBump(_ occurrence: Occurrence, calendar: Calendar = .current) -> Bool {
        BumpRules.canBump(
            state: occurrence.state,
            dayKey: occurrence.dayKey,
            isRepeating: occurrence.isRepeating,
            periodEndDayKey: occurrence.periodEndDayKey,
            limit: occurrence.bumpLimit,
            bumpCount: occurrence.bumpCount,
            firstAddedDayKey: occurrence.firstAddedDayKey,
            calendar: calendar
        )
    }

    /// Moves an occurrence to the next day: this row becomes `bumped` (done for its day) and a new
    /// open row is created the next day, linked both ways, with `bumpCount + 1`, the same item,
    /// bump limit and chain origin. The item's next scheduled occurrence is unaffected.
    /// `newTitle` (trimmed, if not empty) becomes the new row's title. Returns the new row.
    @discardableResult
    static func bump(
        _ occurrence: Occurrence,
        newTitle: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) throws -> Occurrence? {
        guard canBump(occurrence, calendar: calendar) else { return nil }

        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? occurrence.title : trimmed
        let targetKey = DayMath(calendar: calendar).adding(days: 1, to: occurrence.dayKey)
        let sortOrder = occurrence.isRepeating
            ? occurrence.sortOrder
            : try nextOneOffSortOrder(on: targetKey, list: occurrence.list, context: context)

        let next = Occurrence(
            itemID: occurrence.itemID,
            list: occurrence.list,
            dayKey: targetKey,
            title: title,
            sortOrder: sortOrder,
            createdAt: now,
            bumpLimit: occurrence.bumpLimit,
            bumpedFromID: occurrence.id,
            bumpCount: occurrence.bumpCount + 1,
            firstAddedDayKey: occurrence.firstAddedDayKey,
            firstAddedTitle: occurrence.firstAddedTitle,
            scheduledDayKey: occurrence.scheduledDayKey,
            periodEndDayKey: occurrence.periodEndDayKey
        )
        context.insert(next)
        occurrence.state = .bumped
        occurrence.completedAt = now
        occurrence.bumpedToID = next.id
        try context.save()
        return next
    }

    // MARK: - One-offs

    /// Adds a one-off to any day, today or later (or earlier). New one-offs default to
    /// "up to 3 days". Returns nil for an empty title.
    @discardableResult
    static func addOneOff(
        list: ListKind,
        dayKey: String,
        title: String,
        bumpLimit: BumpLimit = .defaultForNewOneOffs,
        now: Date = Date(),
        context: ModelContext
    ) throws -> Occurrence? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let occurrence = Occurrence(
            list: list,
            dayKey: dayKey,
            title: trimmed,
            sortOrder: try nextOneOffSortOrder(on: dayKey, list: list, context: context),
            createdAt: now,
            bumpLimit: bumpLimit
        )
        context.insert(occurrence)
        try context.save()
        return occurrence
    }

    /// Deletes a one-off. If it was bumped in from an earlier day, that day's row goes back to open
    /// (the work it was moved forward for is gone).
    @discardableResult
    static func deleteOneOff(_ occurrence: Occurrence, context: ModelContext) throws -> Bool {
        guard !occurrence.isRepeating else { return false }
        if let fromID = occurrence.bumpedFromID, let source = try self.occurrence(id: fromID, context: context),
           source.bumpedToID == occurrence.id {
            source.bumpedToID = nil
            if source.state == .bumped {
                source.state = .open
                source.completedAt = nil
            }
        }
        if let toID = occurrence.bumpedToID, let next = try self.occurrence(id: toID, context: context) {
            next.bumpedFromID = nil
        }
        context.delete(occurrence)
        try context.save()
        return true
    }

    /// Saves a new order for a day's list. Only one-offs take it: items keep their set order.
    static func reorderOneOffs(_ ordered: [Occurrence], context: ModelContext) throws {
        for (index, occurrence) in ordered.enumerated() where !occurrence.isRepeating && occurrence.sortOrder != index {
            occurrence.sortOrder = index
        }
        try context.save()
    }

    // MARK: - Items

    /// Adds a recurring item. It exists from today; if it falls due today, today's occurrence is
    /// created straight away. Returns nil for an empty title.
    @discardableResult
    static func addItem(
        list: ListKind,
        title: String,
        rule: RepeatRule,
        defaultBumpLimit: BumpLimit = .unlimited,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) throws -> Item? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let today = dayKey(for: now, calendar: calendar)
        let existing = try items(in: list, activeOn: today, context: context)
        let item = Item(
            list: list,
            title: trimmed,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            repeatRule: rule,
            startDayKey: today,
            defaultBumpLimit: defaultBumpLimit,
            createdAt: now
        )
        context.insert(item)
        if rule.occurs(on: today, startDayKey: today, calendar: calendar) {
            context.insert(makeOccurrence(for: item, on: today, now: now, calendar: calendar))
        }
        try context.save()
        return item
    }

    /// Renames from today: today's and later occurrences take the new title; earlier days keep theirs.
    static func renameItem(_ item: Item, to title: String, todayKey: String, context: ModelContext) throws {
        item.title = title
        for occurrence in try occurrences(ofItem: item.id, from: todayKey, context: context) {
            occurrence.title = title
        }
        try context.save()
    }

    /// Saves a new item order; today's and later occurrences follow it.
    static func reorderItems(_ ordered: [Item], todayKey: String, context: ModelContext) throws {
        for (index, item) in ordered.enumerated() {
            if item.sortOrder != index {
                item.sortOrder = index
            }
            for occurrence in try occurrences(ofItem: item.id, from: todayKey, context: context) where occurrence.sortOrder != index {
                occurrence.sortOrder = index
            }
        }
        try context.save()
    }

    /// Deletes from today: the item stops from today onwards (`endDayKey = today`), today's and later
    /// occurrences that weren't done or bumped are removed, and earlier days keep theirs.
    /// The rest of the list closes up.
    static func deleteItem(_ item: Item, todayKey: String, context: ModelContext) throws {
        item.endDayKey = max(todayKey, item.startDayKey)
        for occurrence in try occurrences(ofItem: item.id, from: todayKey, context: context)
        where occurrence.state == .open || occurrence.state == .skipped {
            if let fromID = occurrence.bumpedFromID, let source = try self.occurrence(id: fromID, context: context) {
                source.bumpedToID = nil
            }
            context.delete(occurrence)
        }
        try context.save()

        let remaining = try items(in: item.list, activeOn: todayKey, context: context).filter { $0.id != item.id }
        try reorderItems(remaining, todayKey: todayKey, context: context)
    }

    // MARK: - Helpers

    static func makeOccurrence(for item: Item, on dayKey: String, now: Date, calendar: Calendar) -> Occurrence {
        Occurrence(
            itemID: item.id,
            list: item.list,
            dayKey: dayKey,
            title: item.title,
            sortOrder: item.sortOrder,
            createdAt: now,
            bumpLimit: item.defaultBumpLimit,
            scheduledDayKey: dayKey,
            periodEndDayKey: item.repeatRule.periodEnd(for: dayKey, startDayKey: item.startDayKey, calendar: calendar)
        )
    }

    private static func occurrences(ofItem itemID: UUID, from dayKey: String, context: ModelContext) throws -> [Occurrence] {
        let target: UUID? = itemID
        let key = dayKey
        let descriptor = FetchDescriptor<Occurrence>(predicate: #Predicate { $0.itemID == target && $0.dayKey >= key })
        return try context.fetch(descriptor)
    }

    private static func nextOneOffSortOrder(on dayKey: String, list: ListKind, context: ModelContext) throws -> Int {
        let oneOffs = try occurrences(on: dayKey, list: list, context: context).filter { !$0.isRepeating }
        return (oneOffs.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Clears the links pointing at a row that is about to be deleted.
    private static func unlinkBeforeDelete(_ row: Occurrence, context: ModelContext) throws {
        if let fromID = row.bumpedFromID, let source = try occurrence(id: fromID, context: context), source.bumpedToID == row.id {
            source.bumpedToID = nil
        }
        if let toID = row.bumpedToID, let next = try occurrence(id: toID, context: context), next.bumpedFromID == row.id {
            next.bumpedFromID = nil
        }
    }
}
