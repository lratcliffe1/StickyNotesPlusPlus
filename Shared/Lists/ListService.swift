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
        recordTodaysRules(now: now, calendar: calendar, defaults: defaults)
        try V2Backfill.runIfNeeded(context: context, defaults: defaults, now: now, calendar: calendar)
        try ensureOccurrences(on: dayKey(for: now, calendar: calendar), context: context, now: now, calendar: calendar)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        HomeModel.dayKey(for: date, calendar: calendar)
    }

    // MARK: - Each day's rules

    /// Stores today's flip-time rules from the settings, unless today already has them: each day
    /// keeps the rules it had when first read (DECISIONS.md, "Each day keeps the cutoff it had").
    static func recordTodaysRules(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults) {
        DayRulesStore.record(AppSettings.currentRules(in: defaults), for: dayKey(for: now, calendar: calendar), in: defaults)
    }

    /// After a settings change: today takes the new evening start, and the new morning only while
    /// today's morning is still undecided (`DayRules.todayAfterChange`); past days keep theirs.
    /// Returns whether the morning change waits until tomorrow.
    ///
    /// `original` is today's record as it was when Settings opened (`todaysRules`). Each change in
    /// one visit is judged from it, not from what a half-made edit left (minutes first, then the
    /// hour), so today's morning ends up either as it was or as the latest setting, never as an
    /// in-between time nobody chose.
    @discardableResult
    static func applySettingsToToday(
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults,
        original: DayRules? = nil,
        context: ModelContext
    ) throws -> Bool {
        let todayKey = dayKey(for: now, calendar: calendar)
        let old = original ?? todaysRules(now: now, calendar: calendar, defaults: defaults)
        let morningComplete = ListRules.completion(try occurrences(on: todayKey, list: .morning, context: context)).isComplete
        let change = DayRules.todayAfterChange(
            old: old, new: AppSettings.currentRules(in: defaults), now: now,
            morningComplete: morningComplete, calendar: calendar
        )
        DayRulesStore.overwrite(change.rules, for: todayKey, in: defaults)
        return change.morningFromTomorrow
    }

    /// Today's rules as stored (or, without a record, from the settings).
    static func todaysRules(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults) -> DayRules {
        let todayKey = dayKey(for: now, calendar: calendar)
        return DayRulesStore.resolvedHistory(in: defaults, todayKey: todayKey).rules(for: todayKey)
    }

    /// Whether a list is in use: it has any item (ended ones too) or any occurrence.
    static func isInUse(_ list: ListKind, context: ModelContext) throws -> Bool {
        let raw = list.rawValue
        var items = FetchDescriptor<Item>(predicate: #Predicate { $0.listRaw == raw })
        items.fetchLimit = 1
        if try context.fetchCount(items) > 0 { return true }
        var rows = FetchDescriptor<Occurrence>(predicate: #Predicate { $0.listRaw == raw })
        rows.fetchLimit = 1
        return try context.fetchCount(rows) > 0
    }

    /// Creates the occurrences of every item due on `dayKey` that aren't there yet. Safe to call
    /// any number of times, from any process: an item occurrence's id comes from (item, scheduled
    /// day), so a second create lands on the same row. If duplicates exist anyway, keeps the most
    /// progressed one and deletes the rest.
    ///
    /// Less often than daily: if an occurrence scheduled on an earlier day is still within its period
    /// and never got a row (nobody opened that day), it is created today, keeping its scheduled day
    /// and period end, so it can still be done or bumped for the rest of its period.
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

        // Item rows created on this day (not bumped in), keyed by item and scheduled day.
        var rowsByKey: [String: [Occurrence]] = [:]
        for row in existing where row.bumpedFromID == nil {
            if let itemID = row.itemID {
                rowsByKey[ListRules.materialisedKey(itemID, row.scheduledDayKey ?? row.dayKey), default: []].append(row)
            }
        }
        for rows in rowsByKey.values where rows.count > 1 {
            guard let keep = ListRules.preferredDuplicate(rows) else { continue }
            for row in rows where row.id != keep.id {
                try unlinkBeforeDelete(row, context: context)
                context.delete(row)
                didChange = true
            }
        }

        let math = DayMath(calendar: calendar)
        for item in items where item.isActive(on: dayKey) {
            let rule = item.repeatRule
            if rule.occurs(on: dayKey, startDayKey: item.startDayKey, math: math) {
                guard rowsByKey[ListRules.materialisedKey(item.id, dayKey)] == nil else { continue }
                context.insert(makeOccurrence(for: item, scheduledOn: dayKey, on: dayKey, now: now, calendar: calendar))
                didChange = true
                continue
            }
            // Today isn't scheduled: is an earlier occurrence's period still running, with no row yet?
            guard
                let scheduled = latestOccurrence(of: item, before: dayKey, math: math),
                rule.periodEnd(for: scheduled, startDayKey: item.startDayKey, calendar: calendar) >= dayKey,
                try !hasRow(itemID: item.id, scheduledDayKey: scheduled, context: context)
            else { continue }
            context.insert(makeOccurrence(for: item, scheduledOn: scheduled, on: dayKey, now: now, calendar: calendar))
            didChange = true
        }

        if didChange {
            do {
                try context.save()
            } catch {
                // Never leave a failed insert pending: every later save in this context would fail too.
                context.rollback()
                throw error
            }
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

    /// One list's streak through `anchorKey` (DECISIONS.md, "streak rules"). The morning list is
    /// judged by each day's own deadline (`history`); the day and evening lists count until midnight.
    static func streakState(
        for list: ListKind,
        through anchorKey: String,
        history: DayRulesHistory,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> HomeModel.StreakState {
        let rows = try occurrences(through: anchorKey, list: list, context: context)
        let schedules = try self.schedules(for: list, context: context)
        return ListRules.streakState(
            through: anchorKey, occurrences: rows, schedules: schedules, calendar: calendar,
            deadline: deadline(for: list, history: history, calendar: calendar)
        )
    }

    /// How each day through `endKey` looks for a list (`ListRules.dayLooks`), with misses counted
    /// only on days before `todayKey`. The ring and calendar show these, so they match the streak.
    static func dayLooks(
        for list: ListKind,
        through endKey: String,
        todayKey: String,
        history: DayRulesHistory,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [String: ListRules.DayLook] {
        ListRules.dayLooks(
            occurrences: try occurrences(through: endKey, list: list, context: context),
            schedules: try schedules(for: list, context: context),
            missesBefore: todayKey,
            calendar: calendar,
            deadline: deadline(for: list, history: history, calendar: calendar)
        )
    }

    /// A list's streak deadline for a day: the morning's comes from that day's own rules (its set
    /// time, or 12:00 with no set time; 09:00 before this build); the day and evening lists count
    /// until midnight (nil).
    static func deadline(for list: ListKind, history: DayRulesHistory, calendar: Calendar) -> (String) -> Date? {
        { key in
            guard list == .morning, let day = HomeModel.date(fromDayKey: key, calendar: calendar) else { return nil }
            return history.rules(for: key).morningDeadline(on: day, calendar: calendar)
        }
    }

    /// Every item of a list (ended ones too), as schedules for judging days nobody opened.
    static func schedules(for list: ListKind, context: ModelContext) throws -> [ListRules.ItemSchedule] {
        try items(in: list, context: context).map(\.schedule)
    }

    /// Past days (before `anchorKey`) that count as misses for a list although nobody opened them
    /// (see `ListRules.unopenedMisses`). The ring and calendar show these as 0%.
    static func unopenedMissDays(
        for list: ListKind,
        before anchorKey: String,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> Set<String> {
        let rows = try occurrences(through: anchorKey, list: list, context: context)
        return ListRules.unopenedMisses(
            schedules: try schedules(for: list, context: context),
            openedDays: Set(rows.map(\.dayKey)),
            materialised: Set(rows.compactMap { row in
                row.itemID.map { ListRules.materialisedKey($0, row.scheduledDayKey ?? row.dayKey) }
            }),
            before: anchorKey,
            calendar: calendar
        )
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

    /// Skips an open occurrence: it drops out of the day's count. Refused on a day before
    /// `todayKey` (a menu left open past midnight can't rewrite yesterday).
    @discardableResult
    static func skip(_ occurrence: Occurrence, todayKey: String, context: ModelContext) throws -> Bool {
        guard occurrence.state == .open, occurrence.dayKey >= todayKey else { return false }
        occurrence.state = .skipped
        occurrence.completedAt = nil
        try context.save()
        return true
    }

    /// Undoes a skip: the occurrence is open again and counts towards its day. Refused on a day
    /// before `todayKey`.
    @discardableResult
    static func unskip(_ occurrence: Occurrence, todayKey: String, context: ModelContext) throws -> Bool {
        guard occurrence.state == .skipped, occurrence.dayKey >= todayKey else { return false }
        occurrence.state = .open
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
    /// Refused for a row on a day before `now`'s day (a sheet left open past midnight).
    @discardableResult
    static func bump(
        _ occurrence: Occurrence,
        newTitle: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) throws -> Occurrence? {
        guard canBump(occurrence, calendar: calendar) else { return nil }
        guard occurrence.dayKey >= dayKey(for: now, calendar: calendar) else { return nil }

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
            deadlineDayKey: occurrence.deadlineDayKey,
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

    /// What bumping this occurrence costs, one line each (its repeat's period, its limit).
    static func bumpCosts(for occurrence: Occurrence, calendar: Calendar = .current, context: ModelContext) throws -> [BumpCost] {
        var repeatInfo: (rule: RepeatRule, startDayKey: String)?
        if let itemID = occurrence.itemID, let item = try item(id: itemID, context: context) {
            repeatInfo = (item.repeatRule, item.startDayKey)
        }
        return BumpRules.costs(
            dayKey: occurrence.dayKey,
            isRepeating: occurrence.isRepeating,
            scheduledDayKey: occurrence.scheduledDayKey,
            periodEndDayKey: occurrence.periodEndDayKey,
            repeatInfo: repeatInfo,
            limit: occurrence.bumpLimit,
            bumpCount: occurrence.bumpCount,
            firstAddedDayKey: occurrence.firstAddedDayKey,
            calendar: calendar
        )
    }

    // MARK: - Bump marks

    /// Every bumped row from `startKey` through `endKey`, on all lists. Each is one bump, on the day
    /// it was bumped from.
    static func bumpedOccurrences(from startKey: String, through endKey: String, context: ModelContext) throws -> [Occurrence] {
        let start = startKey
        let end = endKey
        let bumped = OccurrenceState.bumped.rawValue
        let descriptor = FetchDescriptor<Occurrence>(
            predicate: #Predicate { $0.dayKey >= start && $0.dayKey <= end && $0.stateRaw == bumped }
        )
        return try context.fetch(descriptor)
    }

    /// Days from `startKey` through `endKey` that had something bumped (the ↻ mark).
    static func bumpedDayKeys(from startKey: String, through endKey: String, context: ModelContext) throws -> Set<String> {
        ListRules.bumpedDays(try bumpedOccurrences(from: startKey, through: endKey, context: context))
    }

    /// "N bumps in 7 days" (provisional): bump actions on days from `startKey` through `endKey`, all
    /// lists. Home passes the ring's own days, so the count covers exactly the ↻ marks on show.
    static func bumpCount(from startKey: String, through endKey: String, context: ModelContext) throws -> Int {
        ListRules.bumpCount(try bumpedOccurrences(from: startKey, through: endKey, context: context), from: startKey, through: endKey)
    }

    // MARK: - One-offs

    /// Adds a one-off with the add menu's options (must happen today, deadline, bump limit).
    @discardableResult
    static func addOneOff(
        list: ListKind,
        dayKey: String,
        title: String,
        options: OneOffOptions,
        now: Date = Date(),
        context: ModelContext
    ) throws -> Occurrence? {
        try addOneOff(
            list: list,
            dayKey: dayKey,
            title: title,
            bumpLimit: options.bumpLimit,
            deadlineDayKey: options.deadlineDayKey,
            now: now,
            context: context
        )
    }

    /// Edits one one-off row (provisional: this row only, not its bump chain): its title, bump
    /// limit and deadline. An empty title keeps the old one. An "until deadline" limit sets the
    /// deadline; otherwise `deadlineDayKey` replaces it (nil clears it). Refused on a day before
    /// `todayKey`.
    @discardableResult
    static func editOneOff(
        _ occurrence: Occurrence,
        title: String,
        bumpLimit: BumpLimit,
        deadlineDayKey: String?,
        todayKey: String,
        context: ModelContext
    ) throws -> Bool {
        guard !occurrence.isRepeating, occurrence.dayKey >= todayKey else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            occurrence.title = trimmed
        }
        occurrence.bumpLimit = bumpLimit
        occurrence.deadlineDayKey = bumpLimit.storedDeadlineDayKey ?? deadlineDayKey
        try context.save()
        return true
    }

    /// Adds a one-off to any day, today or later (or earlier). New one-offs default to
    /// "up to 3 days". `deadlineDayKey` is independent of the limit. Returns nil for an empty title.
    @discardableResult
    static func addOneOff(
        list: ListKind,
        dayKey: String,
        title: String,
        bumpLimit: BumpLimit = .defaultForNewOneOffs,
        deadlineDayKey: String? = nil,
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
            bumpLimit: bumpLimit,
            deadlineDayKey: deadlineDayKey
        )
        context.insert(occurrence)
        try context.save()
        return occurrence
    }

    /// Deletes a one-off. If it was bumped in from an earlier day, that day's row goes back to open
    /// (the work it was moved forward for is gone). Refused on a day before `todayKey`.
    @discardableResult
    static func deleteOneOff(_ occurrence: Occurrence, todayKey: String, context: ModelContext) throws -> Bool {
        guard !occurrence.isRepeating, occurrence.dayKey >= todayKey else { return false }
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
        let existing = try currentItems(in: list, context: context)
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
            context.insert(makeOccurrence(for: item, scheduledOn: today, on: today, now: now, calendar: calendar))
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
    /// occurrences that weren't done or bumped are removed, and earlier days keep theirs. As with
    /// `deleteOneOff`, a removed copy that was bumped in sends its source day back to open.
    /// The rest of the list closes up. An item that has already ended (deleted, or replaced by a
    /// repeat change) is refused, so its end day never moves (returns false).
    @discardableResult
    static func deleteItem(_ item: Item, todayKey: String, context: ModelContext) throws -> Bool {
        guard item.endDayKey == nil else { return false }
        item.endDayKey = max(todayKey, item.startDayKey)
        for occurrence in try occurrences(ofItem: item.id, from: todayKey, context: context)
        where occurrence.state == .open || occurrence.state == .skipped {
            if let fromID = occurrence.bumpedFromID, let source = try self.occurrence(id: fromID, context: context),
               source.bumpedToID == occurrence.id {
                source.bumpedToID = nil
                if source.state == .bumped {
                    source.state = .open
                    source.completedAt = nil
                }
            }
            context.delete(occurrence)
        }
        try context.save()

        let remaining = try currentItems(in: item.list, context: context).filter { $0.id != item.id }
        try reorderItems(remaining, todayKey: todayKey, context: context)
        return true
    }

    /// Of the items behind these rows, the ones that have ended (deleted, or replaced by a repeat
    /// change). Home hides Edit… and Delete on their rows: without a link from an ended item to its
    /// replacement, the item to edit can't be told apart from a deleted one.
    static func endedItemIDs(among occurrences: [Occurrence], context: ModelContext) throws -> Set<UUID> {
        let wanted = Set(occurrences.compactMap(\.itemID))
        guard !wanted.isEmpty else { return [] }
        let ended = try context.fetch(FetchDescriptor<Item>(predicate: #Predicate { $0.endDayKey != nil }))
        return Set(ended.map(\.id)).intersection(wanted)
    }
    static func item(id: UUID, context: ModelContext) throws -> Item? {
        let target = id
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The items Edit lists shows: not deleted or replaced (no end day), including one that starts
    /// tomorrow after a repeat change. In their set order.
    static func currentItems(in list: ListKind, context: ModelContext) throws -> [Item] {
        try items(in: list, context: context).filter { $0.endDayKey == nil }
    }

    /// A new bump limit for an item: the item, and today's open occurrence of it. Other days keep
    /// theirs. Items carry no deadline, so "until deadline" is refused (returns false), as is an
    /// item that has ended.
    @discardableResult
    static func updateItemBumpLimit(_ item: Item, to limit: BumpLimit, todayKey: String, context: ModelContext) throws -> Bool {
        if case .untilDeadline = limit { return false }
        guard item.endDayKey == nil else { return false }
        item.defaultBumpLimitRaw = limit.kind.rawValue
        item.defaultBumpLimitDays = limit.storedDays
        for occurrence in try occurrences(ofItem: item.id, from: todayKey, context: context)
        where occurrence.dayKey == todayKey && occurrence.state == .open {
            occurrence.bumpLimit = limit
        }
        try context.save()
        return true
    }

    /// Saves the item editor (DECISIONS.md, 2b; the repeat rule is provisional):
    /// - a new title is a rename from today (`renameItem`);
    /// - a new bump limit changes the item and today's open occurrence (`updateItemBumpLimit`);
    /// - a new repeat splits the item, so past days are never recounted: the old item ends and a new
    ///   one (new id, same title order) starts on the split day: today, or tomorrow if today's
    ///   occurrence is already done, skipped or bumped. From the split day on, the old item's open
    ///   scheduled rows are removed (copies bumped in stay where they are), and if the new rule
    ///   falls due today, today's occurrence is created for the new item.
    /// A new title is applied from today in a split too, so a done row today takes it as well.
    /// An item that has ended (deleted, or already replaced) is refused: returns nil, nothing changes.
    /// Returns the item in effect afterwards: the new one after a split.
    @discardableResult
    static func updateItem(
        _ item: Item,
        title: String,
        rule: RepeatRule,
        bumpLimit: BumpLimit,
        now: Date = Date(),
        calendar: Calendar = .current,
        context: ModelContext
    ) throws -> Item? {
        guard item.endDayKey == nil else { return nil }
        let today = dayKey(for: now, calendar: calendar)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = trimmed.isEmpty ? item.title : trimmed
        var limit = bumpLimit
        if case .untilDeadline = limit {
            limit = item.defaultBumpLimit
        }

        guard rule != item.repeatRule else {
            if newTitle != item.title {
                try renameItem(item, to: newTitle, todayKey: today, context: context)
            }
            if limit != item.defaultBumpLimit {
                try updateItemBumpLimit(item, to: limit, todayKey: today, context: context)
            }
            return item
        }

        if newTitle != item.title {
            try renameItem(item, to: newTitle, todayKey: today, context: context)
        }
        let fromToday = try occurrences(ofItem: item.id, from: today, context: context)
        let todayProgressed = fromToday.contains { $0.dayKey == today && $0.state != .open }
        let earliest = todayProgressed ? DayMath(calendar: calendar).adding(days: 1, to: today) : today
        let splitDay = max(earliest, item.startDayKey)

        for occurrence in fromToday
        where occurrence.dayKey >= splitDay && occurrence.bumpedFromID == nil && occurrence.state == .open {
            try unlinkBeforeDelete(occurrence, context: context)
            context.delete(occurrence)
        }
        item.endDayKey = min(item.endDayKey ?? splitDay, splitDay)

        let replacement = Item(
            list: item.list,
            title: newTitle,
            sortOrder: item.sortOrder,
            repeatRule: rule,
            startDayKey: splitDay,
            defaultBumpLimit: limit,
            createdAt: now
        )
        context.insert(replacement)
        if splitDay == today, rule.occurs(on: today, startDayKey: today, calendar: calendar) {
            context.insert(makeOccurrence(for: replacement, scheduledOn: today, on: today, now: now, calendar: calendar))
        }
        try context.save()
        return replacement
    }

    // MARK: - Helpers

    /// The row for `item`'s occurrence scheduled on `scheduledDayKey`, placed on `dayKey` (the same
    /// day, or a later day in its period). Its id is derived from (item, scheduled day).
    static func makeOccurrence(
        for item: Item,
        scheduledOn scheduledDayKey: String,
        on dayKey: String,
        now: Date,
        calendar: Calendar
    ) -> Occurrence {
        Occurrence(
            id: OccurrenceID.forItem(item.id, scheduledDayKey: scheduledDayKey),
            itemID: item.id,
            list: item.list,
            dayKey: dayKey,
            title: item.title,
            sortOrder: item.sortOrder,
            createdAt: now,
            bumpLimit: item.defaultBumpLimit,
            scheduledDayKey: scheduledDayKey,
            periodEndDayKey: item.repeatRule.periodEnd(for: scheduledDayKey, startDayKey: item.startDayKey, calendar: calendar)
        )
    }

    /// The item's most recent scheduled day before `dayKey`, looking back at most one longest period.
    private static func latestOccurrence(of item: Item, before dayKey: String, math: DayMath) -> String? {
        let rule = item.repeatRule
        let lookback = 366 * max(1, rule.interval) + 31
        var day = math.adding(days: -1, to: dayKey)
        var steps = 0
        while day >= item.startDayKey && steps < lookback {
            if rule.occurs(on: day, startDayKey: item.startDayKey, math: math) {
                return day
            }
            day = math.adding(days: -1, to: day)
            steps += 1
        }
        return nil
    }

    /// Whether any row (on any day, bumped copies included) exists for this occurrence.
    private static func hasRow(itemID: UUID, scheduledDayKey: String, context: ModelContext) throws -> Bool {
        let target: UUID? = itemID
        let scheduled: String? = scheduledDayKey
        var descriptor = FetchDescriptor<Occurrence>(predicate: #Predicate { $0.itemID == target && $0.scheduledDayKey == scheduled })
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
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
