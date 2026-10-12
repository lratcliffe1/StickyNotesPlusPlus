import Foundation

/// The fields the pure list rules need from an occurrence. `Occurrence` conforms; tests can use
/// plain values.
protocol OccurrenceFacts {
    var title: String { get }
    var dayKey: String { get }
    var itemID: UUID? { get }
    var sortOrder: Int { get }
    var createdAt: Date { get }
    var completedAt: Date? { get }
    var state: OccurrenceState { get }
    var bumpLimit: BumpLimit { get }
    /// Repeating occurrences: the day they were scheduled for.
    var scheduledDayKey: String? { get }
    /// Repeating occurrences: the last day they can still be done or bumped to.
    var periodEndDayKey: String? { get }
    /// A bumped copy: the row it was bumped from (nil once that row is deleted). Defaults to nil.
    var bumpedFromID: UUID? { get }
    /// How many times the chain was bumped before this row (a bumped copy is at least 1). Defaults to 0.
    var bumpCount: Int { get }
    /// Imported from the vault's `tasks.json` (planned there, never a late addition in the app).
    /// Defaults to false.
    var isImported: Bool { get }
}

extension OccurrenceFacts {
    var bumpedFromID: UUID? { nil }
    var bumpCount: Int { 0 }
    var isImported: Bool { false }

    /// Moved here from an earlier day by a bump.
    var wasBumpedIn: Bool { bumpedFromID != nil || bumpCount > 0 }
}

/// How one day counts towards one list's streak.
enum DayStatus: Equatable {
    case complete
    case missed
    /// Nothing counted that day (empty, or everything skipped): neither extends nor breaks a streak.
    case neutral
}

/// Pure rules for completion, streaks and order (DECISIONS.md, "streak rules" and "Order").
enum ListRules {
    // MARK: - Completion

    /// Skipped occurrences drop out of the count; bumped ones count as done.
    /// Nothing left to count is neutral (value 0), never 100%.
    static func completion<T: OccurrenceFacts>(_ occurrences: [T]) -> HomeModel.CompletionState {
        let counted = occurrences.filter { $0.state != .skipped }
        guard !counted.isEmpty else { return .neutral }
        let done = counted.filter { $0.state.countsAsDone }.count
        return HomeModel.CompletionState(value: Double(done) / Double(counted.count), isNeutral: false)
    }

    /// A day is complete when every counted occurrence is done or bumped and, with a `deadline`
    /// (the morning cutoff), the last completion came before it. Completions without a timestamp
    /// (old rows) are trusted. An occurrence still open on a past day is a miss for that day.
    static func dayStatus<T: OccurrenceFacts>(_ occurrences: [T], deadline: Date?) -> DayStatus {
        let counted = occurrences.filter { $0.state != .skipped }
        guard !counted.isEmpty else { return .neutral }
        guard counted.allSatisfy({ $0.state.countsAsDone }) else { return .missed }
        if let deadline, let latest = counted.compactMap(\.completedAt).max(), latest > deadline {
            return .missed
        }
        return .complete
    }

    // MARK: - Bonus rows (fix round 1)

    /// A morning row added after that day's morning deadline is a bonus (DECISIONS.md, 2026-10-12):
    /// it shows and can be ticked, but never counts towards the morning's verdict, its %, the
    /// streak, the ring, the calendar or the habits file. Only the morning has a deadline before
    /// midnight, so a nil `deadline` (the day and evening lists) is never a bonus.
    ///
    /// "Added" is when Liam created the thing, never when the day's row was materialised (rows for
    /// repeating items are created when the app first reads the day, so opening the app late can't
    /// turn the routine into bonus rows):
    /// - a one-off: its own `createdAt`. A row bumped in from an earlier day is never a bonus, and
    ///   nor is one imported from the vault (`isImported`): Liam planned it there, so when the app
    ///   happened to sync says nothing about when it was added.
    /// - a repeating row: its item's `createdAt` (`ItemSchedule.createdAt`), and only on the day the
    ///   item started, when it was created that same day. An item from an earlier day can't be a
    ///   late add today; a backfilled item (created after its start day) never is. A repeat change's
    ///   replacement item keeps its predecessor's `createdAt` (`ListService.updateItem`), so editing
    ///   an undone routine item after the cutoff can't dodge a miss. An item with no schedule (or no
    ///   `createdAt`) is never a bonus.
    static func isBonus<T: OccurrenceFacts>(
        _ row: T,
        schedules: [UUID: ItemSchedule],
        deadline: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let deadline else { return false }
        if let itemID = row.itemID {
            guard let schedule = schedules[itemID], let added = schedule.createdAt else { return false }
            return schedule.startDayKey == row.dayKey
                && HomeModel.dayKey(for: added, calendar: calendar) == row.dayKey
                && added > deadline
        }
        guard !row.wasBumpedIn, !row.isImported else { return false }
        return row.createdAt > deadline
    }

    /// The rows that count: `rows` without the bonus ones (`isBonus`), each judged by its own day's
    /// deadline. Apply it before `completion` and `dayStatus` wherever a morning is judged.
    static func countedRows<T: OccurrenceFacts>(
        _ rows: [T],
        schedules: [ItemSchedule],
        calendar: Calendar = .current,
        deadline: (String) -> Date?
    ) -> [T] {
        let byItem = scheduleIndex(schedules)
        var deadlines: [String: Date?] = [:]
        var counted: [T] = []
        for row in rows {
            let cutoff = cachedDeadline(row.dayKey, &deadlines, deadline)
            if !isBonus(row, schedules: byItem, deadline: cutoff, calendar: calendar) {
                counted.append(row)
            }
        }
        return counted
    }

    /// `deadline(key)`, read once per day.
    private static func cachedDeadline(_ key: String, _ cache: inout [String: Date?], _ deadline: (String) -> Date?) -> Date? {
        if let cached = cache[key] { return cached }
        let value = deadline(key)
        cache[key] = .some(value)
        return value
    }

    /// Schedules by item id (the first one wins if an id repeats).
    static func scheduleIndex(_ schedules: [ItemSchedule]) -> [UUID: ItemSchedule] {
        Dictionary(schedules.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Streaks

    /// Never miss twice: one miss freezes the streak, a second miss in a row resets it, and a
    /// complete day after a single miss carries on. Neutral days are passed over as if absent,
    /// so two misses either side of a neutral day are two misses in a row.
    /// The anchor day only ever adds (it's still in progress); it never breaks the streak.
    /// Days are walked from the first one with data, so there is no lookback cap.
    static func streakState(through anchorKey: String, statuses: [String: DayStatus]) -> HomeModel.StreakState {
        var count = 0
        var isFrozen = false

        for key in statuses.keys.sorted() where key < anchorKey {
            switch statuses[key] ?? .neutral {
            case .neutral:
                continue
            case .complete:
                count += 1
                isFrozen = false
            case .missed:
                if isFrozen {
                    count = 0
                    isFrozen = false
                } else if count > 0 {
                    isFrozen = true
                }
            }
        }

        if statuses[anchorKey] == .complete {
            return HomeModel.StreakState(count: count + 1, isFrozen: false)
        }
        return HomeModel.StreakState(count: count, isFrozen: isFrozen && count > 0)
    }

    /// Streak for one list's occurrences through `anchorKey`, from the same day looks the ring and
    /// calendar show (`dayLooks`), so display and streak can't disagree.
    static func streakState<T: OccurrenceFacts>(
        through anchorKey: String,
        occurrences: [T],
        schedules: [ItemSchedule] = [],
        calendar: Calendar = .current,
        deadline: (String) -> Date?
    ) -> HomeModel.StreakState {
        let looks = dayLooks(
            occurrences: occurrences.filter { $0.dayKey <= anchorKey },
            schedules: schedules,
            missesBefore: anchorKey,
            calendar: calendar,
            deadline: deadline
        )
        return streakState(through: anchorKey, statuses: looks.mapValues(\.status))
    }

    // MARK: - How a day looks

    /// How one day looks for one list: its streak status and the completion the ring and calendar show.
    struct DayLook: Equatable {
        let status: DayStatus
        let completion: HomeModel.CompletionState
    }

    /// How each day looks for one list. The one source for the streak, the 7-day ring and the calendar.
    ///
    /// - A day's own rows count as before: skipped ones drop out, bumped ones count as done, and with a
    ///   `deadline` (the morning cutoff) a late finish makes the day a miss.
    /// - Bonus rows (`isBonus`: added after the morning's deadline) don't count at all, not even as
    ///   a deferred repeat's later miss; a day with only bonus rows is neutral. They still mark the
    ///   day as opened.
    /// - An open repeating occurrence whose period runs past its own day (less often than daily) isn't
    ///   counted on its day: it can still be done later. If it's still open, it is a miss on its period
    ///   end, once that day is before `missesBefore`.
    /// - A past day nobody opened is judged by what was due (`unopenedMissCounts`).
    /// - Each such miss adds one undone occurrence to its day, so the day shows below 100% (0% if it
    ///   has no rows of its own) and its status is a miss.
    /// - An item ended (deleted) on or before a period end never costs a miss on it: deleting an item
    ///   never costs a streak day after the delete.
    /// Days with nothing counted and nothing missed are absent (neutral).
    ///
    /// With a `window`, only days nobody opened inside it are judged, and only looks inside it are
    /// returned. Given every row inside the window, the looks from `CalendarRules.fetchStart` on are
    /// the same as from the whole history (the calendar fetches one month at a time).
    static func dayLooks<T: OccurrenceFacts>(
        occurrences: [T],
        schedules: [ItemSchedule],
        missesBefore cutoffKey: String,
        calendar: Calendar = .current,
        window: ClosedRange<String>? = nil,
        deadline: (String) -> Date?
    ) -> [String: DayLook] {
        var endByItem: [UUID: String] = [:]
        for schedule in schedules {
            if let end = schedule.endDayKey { endByItem[schedule.itemID] = end }
        }
        let scheduleByItem = scheduleIndex(schedules)
        var deadlines: [String: Date?] = [:]

        var counted: [String: [T]] = [:]
        var openedDays: Set<String> = []
        var materialised: Set<String> = []
        var extraMisses: [String: Int] = [:]
        for occurrence in occurrences {
            openedDays.insert(occurrence.dayKey)
            if let itemID = occurrence.itemID {
                materialised.insert(materialisedKey(itemID, occurrence.scheduledDayKey ?? occurrence.dayKey))
            }
            // A bonus row never counts: not on its day, and not as a miss at its period end.
            if isBonus(occurrence, schedules: scheduleByItem, deadline: cachedDeadline(occurrence.dayKey, &deadlines, deadline),
                       calendar: calendar) {
                continue
            }
            if isDeferred(occurrence) {
                if let periodEnd = occurrence.periodEndDayKey, periodEnd < cutoffKey,
                   !endsOnOrBefore(endByItem[occurrence.itemID ?? UUID()], periodEnd) {
                    extraMisses[periodEnd, default: 0] += 1
                }
                continue
            }
            if occurrence.state != .skipped {
                counted[occurrence.dayKey, default: []].append(occurrence)
            }
        }
        let unopened = unopenedMissCounts(
            schedules: schedules, openedDays: openedDays, materialised: materialised,
            before: cutoffKey, calendar: calendar, window: window
        )
        extraMisses.merge(unopened, uniquingKeysWith: +)

        var looks: [String: DayLook] = [:]
        for key in Set(counted.keys).union(extraMisses.keys) where window?.contains(key) ?? true {
            let rows = counted[key] ?? []
            let missed = extraMisses[key] ?? 0
            let total = rows.count + missed
            guard total > 0 else { continue }
            let done = rows.filter { $0.state.countsAsDone }.count
            let completion = HomeModel.CompletionState(value: Double(done) / Double(total), isNeutral: false)
            let status: DayStatus = missed > 0 ? .missed : dayStatus(rows, deadline: cachedDeadline(key, &deadlines, deadline))
            looks[key] = DayLook(status: status, completion: completion)
        }
        return looks
    }

    /// An open repeating occurrence that can still be done after its own day.
    static func isDeferred<T: OccurrenceFacts>(_ occurrence: T) -> Bool {
        guard occurrence.itemID != nil, occurrence.state == .open, let periodEnd = occurrence.periodEndDayKey else {
            return false
        }
        return periodEnd > occurrence.dayKey
    }

    /// "itemID|scheduledDayKey": one occurrence of one item.
    static func materialisedKey(_ itemID: UUID, _ scheduledDayKey: String) -> String {
        "\(itemID.uuidString)|\(scheduledDayKey)"
    }

    /// Whether an item that ends on `endDayKey` (nil: never) is gone by `dayKey`.
    private static func endsOnOrBefore(_ endDayKey: String?, _ dayKey: String) -> Bool {
        guard let endDayKey else { return false }
        return endDayKey <= dayKey
    }

    // MARK: - Days nobody opened

    /// An item's schedule, as plain values.
    struct ItemSchedule {
        let itemID: UUID
        let rule: RepeatRule
        let startDayKey: String
        /// The first day the item no longer exists on.
        let endDayKey: String?
        /// When Liam added the item (a repeat change's replacement keeps its predecessor's): what
        /// the bonus rule reads (`isBonus`). Nil: never a bonus.
        var createdAt: Date? = nil

        func isActive(on dayKey: String) -> Bool {
            guard dayKey >= startDayKey else { return false }
            if let endDayKey { return dayKey < endDayKey }
            return true
        }
    }

    /// Days with misses that rows can't show, because nobody opened the day the item was due.
    /// See `unopenedMissCounts`.
    static func unopenedMisses(
        schedules: [ItemSchedule],
        openedDays: Set<String>,
        materialised: Set<String> = [],
        before anchorKey: String,
        calendar: Calendar = .current
    ) -> Set<String> {
        Set(unopenedMissCounts(
            schedules: schedules, openedDays: openedDays, materialised: materialised,
            before: anchorKey, calendar: calendar
        ).keys)
    }

    /// Only today's rows are ever created, so a past day with no rows for a list was never opened.
    /// "Neutral" means nothing was due, not nothing was created: for each unopened day S before the
    /// anchor, every item that existed on S and whose rule falls on S was due and was never done.
    /// That occurrence counts as a miss on its period end P (`RepeatRule.periodEnd`), the last day it
    /// could have been done, if P is before the anchor and the item hadn't ended by P. For a daily
    /// item P == S, so the unopened day itself is the miss; for a weekly item the miss lands on its
    /// period end (Sunday), whether or not that day was opened, and the unopened days inside the
    /// period aren't misses by themselves. An occurrence that got a row later in its period
    /// (`materialised`, "itemID|scheduledDayKey") is judged by that row instead.
    /// Returns the number of missed occurrences per day.
    /// With a `window`, only the unopened days inside it are walked (the caller has every row in it).
    static func unopenedMissCounts(
        schedules: [ItemSchedule],
        openedDays: Set<String>,
        materialised: Set<String> = [],
        before anchorKey: String,
        calendar: Calendar = .current,
        window: ClosedRange<String>? = nil
    ) -> [String: Int] {
        guard let firstStart = schedules.map(\.startDayKey).min(), firstStart < anchorKey else { return [:] }
        let math = DayMath(calendar: calendar)
        var misses: [String: Int] = [:]
        var day = max(firstStart, window?.lowerBound ?? firstStart)
        while day < anchorKey && day <= (window?.upperBound ?? day) {
            if !openedDays.contains(day) {
                for schedule in schedules where schedule.isActive(on: day) {
                    guard schedule.rule.occurs(on: day, startDayKey: schedule.startDayKey, math: math) else { continue }
                    guard !materialised.contains(materialisedKey(schedule.itemID, day)) else { continue }
                    let periodEnd = schedule.rule.periodEnd(for: day, startDayKey: schedule.startDayKey, calendar: calendar)
                    if periodEnd < anchorKey && !endsOnOrBefore(schedule.endDayKey, periodEnd) {
                        misses[periodEnd, default: 0] += 1
                    }
                }
            }
            day = math.adding(days: 1, to: day)
        }
        return misses
    }

    // MARK: - Order

    /// Recurring items first in their set order, then one-offs: "can't bump" ones at the top,
    /// then the rest in creation order (`sortOrder` is set at creation and changed only by a reorder).
    static func ordered<T: OccurrenceFacts>(_ occurrences: [T]) -> [T] {
        occurrences.sorted { lhs, rhs in
            let lhsGroup = orderGroup(lhs)
            let rhsGroup = orderGroup(rhs)
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.title < rhs.title
        }
    }

    private static func orderGroup<T: OccurrenceFacts>(_ occurrence: T) -> Int {
        if occurrence.itemID != nil { return 0 }
        return occurrence.bumpLimit == .cantBump ? 1 : 2
    }

    // MARK: - Bumps

    /// Days that had something bumped from them (the ↻ mark on the ring and calendar).
    static func bumpedDays<T: OccurrenceFacts>(_ occurrences: [T]) -> Set<String> {
        Set(occurrences.filter { $0.state == .bumped }.map(\.dayKey))
    }

    /// Bump actions on days from `startKey` through `endKey`: each bumped row is one bump, on the day
    /// it was bumped from.
    static func bumpCount<T: OccurrenceFacts>(_ occurrences: [T], from startKey: String, through endKey: String) -> Int {
        occurrences.filter { $0.state == .bumped && $0.dayKey >= startKey && $0.dayKey <= endKey }.count
    }

    // MARK: - Duplicates

    /// Of several rows for the same item and day, the one to keep: the most progressed
    /// (done > bumped > skipped > open), then the earliest created.
    static func preferredDuplicate<T: OccurrenceFacts>(_ rows: [T]) -> T? {
        rows.min { lhs, rhs in
            if lhs.state.progressRank != rhs.state.progressRank {
                return lhs.state.progressRank > rhs.state.progressRank
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
