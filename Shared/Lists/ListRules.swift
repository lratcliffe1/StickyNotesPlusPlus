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

    /// Streak for one list's occurrences. `deadline` gives a day's cutoff (morning) or nil (midnight).
    /// `schedules` are the list's items (ended ones too): past days nobody opened are judged against
    /// what was due on them (`unopenedMisses`) instead of counting as neutral.
    static func streakState<T: OccurrenceFacts>(
        through anchorKey: String,
        occurrences: [T],
        schedules: [ItemSchedule] = [],
        calendar: Calendar = .current,
        deadline: (String) -> Date?
    ) -> HomeModel.StreakState {
        var byDay: [String: [T]] = [:]
        for occurrence in occurrences where occurrence.dayKey <= anchorKey {
            byDay[occurrence.dayKey, default: []].append(occurrence)
        }
        var statuses: [String: DayStatus] = [:]
        for (key, rows) in byDay {
            statuses[key] = dayStatus(rows, deadline: deadline(key))
        }
        let misses = unopenedMisses(schedules: schedules, openedDays: Set(byDay.keys), before: anchorKey, calendar: calendar)
        for key in misses {
            statuses[key] = .missed
        }
        return streakState(through: anchorKey, statuses: statuses)
    }

    // MARK: - Days nobody opened

    /// An item's schedule, as plain values.
    struct ItemSchedule {
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

    /// Misses that rows can't show, because nobody opened the day the item was due.
    ///
    /// Only today's rows are ever created, so a past day with no rows for a list was never opened.
    /// "Neutral" means nothing was due, not nothing was created: for each unopened day S before the
    /// anchor, every item that existed on S and whose rule falls on S was due and was never done.
    /// That occurrence counts as a miss on its period end P (`RepeatRule.periodEnd`), the last day it
    /// could have been done, if P is before the anchor. For a daily item P == S, so the unopened day
    /// itself is the miss; for a weekly item the miss lands on its period end (Sunday), whether or
    /// not that day was opened, and the unopened days inside the period aren't misses by themselves.
    /// A day that was opened is judged by its own rows (opening creates every item due that day).
    static func unopenedMisses(
        schedules: [ItemSchedule],
        openedDays: Set<String>,
        before anchorKey: String,
        calendar: Calendar = .current
    ) -> Set<String> {
        guard let firstStart = schedules.map(\.startDayKey).min(), firstStart < anchorKey else { return [] }
        let math = DayMath(calendar: calendar)
        var misses: Set<String> = []
        var day = firstStart
        while day < anchorKey {
            if !openedDays.contains(day) {
                for schedule in schedules where schedule.isActive(on: day) {
                    guard schedule.rule.occurs(on: day, startDayKey: schedule.startDayKey, math: math) else { continue }
                    let periodEnd = schedule.rule.periodEnd(for: day, startDayKey: schedule.startDayKey, calendar: calendar)
                    if periodEnd < anchorKey {
                        misses.insert(periodEnd)
                    }
                }
            }
            day = math.adding(days: 1, to: day)
        }
        return misses
    }

    /// A day's completion for the ring and calendar: a past day nobody opened with something due
    /// shows as 0% (a miss), not as neutral grey.
    static func completion<T: OccurrenceFacts>(_ occurrences: [T], isUnopenedMiss: Bool) -> HomeModel.CompletionState {
        if occurrences.isEmpty && isUnopenedMiss {
            return HomeModel.CompletionState(value: 0, isNeutral: false)
        }
        return completion(occurrences)
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
