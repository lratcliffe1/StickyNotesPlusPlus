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
    /// - An open repeating occurrence whose period runs past its own day (less often than daily) isn't
    ///   counted on its day: it can still be done later. If it's still open, it is a miss on its period
    ///   end, once that day is before `missesBefore`.
    /// - A past day nobody opened is judged by what was due (`unopenedMissCounts`).
    /// - Each such miss adds one undone occurrence to its day, so the day shows below 100% (0% if it
    ///   has no rows of its own) and its status is a miss.
    /// - An item ended (deleted) on or before a period end never costs a miss on it: deleting an item
    ///   never costs a streak day after the delete.
    /// Days with nothing counted and nothing missed are absent (neutral).
    static func dayLooks<T: OccurrenceFacts>(
        occurrences: [T],
        schedules: [ItemSchedule],
        missesBefore cutoffKey: String,
        calendar: Calendar = .current,
        deadline: (String) -> Date?
    ) -> [String: DayLook] {
        var endByItem: [UUID: String] = [:]
        for schedule in schedules {
            if let end = schedule.endDayKey { endByItem[schedule.itemID] = end }
        }

        var counted: [String: [T]] = [:]
        var openedDays: Set<String> = []
        var materialised: Set<String> = []
        var extraMisses: [String: Int] = [:]
        for occurrence in occurrences {
            openedDays.insert(occurrence.dayKey)
            if let itemID = occurrence.itemID {
                materialised.insert(materialisedKey(itemID, occurrence.scheduledDayKey ?? occurrence.dayKey))
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
            before: cutoffKey, calendar: calendar
        )
        extraMisses.merge(unopened, uniquingKeysWith: +)

        var looks: [String: DayLook] = [:]
        for key in Set(counted.keys).union(extraMisses.keys) {
            let rows = counted[key] ?? []
            let missed = extraMisses[key] ?? 0
            let total = rows.count + missed
            guard total > 0 else { continue }
            let done = rows.filter { $0.state.countsAsDone }.count
            let completion = HomeModel.CompletionState(value: Double(done) / Double(total), isNeutral: false)
            let status: DayStatus = missed > 0 ? .missed : dayStatus(rows, deadline: deadline(key))
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
    static func unopenedMissCounts(
        schedules: [ItemSchedule],
        openedDays: Set<String>,
        materialised: Set<String> = [],
        before anchorKey: String,
        calendar: Calendar = .current
    ) -> [String: Int] {
        guard let firstStart = schedules.map(\.startDayKey).min(), firstStart < anchorKey else { return [:] }
        let math = DayMath(calendar: calendar)
        var misses: [String: Int] = [:]
        var day = firstStart
        while day < anchorKey {
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
