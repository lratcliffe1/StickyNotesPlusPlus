import Foundation

/// Pure domain rules for day identity, completion math, list gating, and streak behavior.
enum HomeModel {
    /// Which list the sticky note shows. The app picks it by the time and what's done
    /// (`automaticList`); the flip button cycles through all three (DECISIONS.md, 2b).
    enum ContextualList: CaseIterable {
        case morning
        case daily
        case evening

        /// The flip button's order: morning → day → evening → morning.
        var next: ContextualList {
            switch self {
            case .morning: return .daily
            case .daily: return .evening
            case .evening: return .morning
            }
        }

        var listKind: ListKind {
            switch self {
            case .morning: return .morning
            case .daily: return .day
            case .evening: return .evening
            }
        }
    }

    struct CompletionState: Equatable {
        let value: Double
        /// Nothing counted on the list that day (empty, or all skipped): shown as no fill and "—",
        /// never as 100%, and neither extends nor breaks a streak.
        let isNeutral: Bool

        static let neutral = CompletionState(value: 0, isNeutral: true)

        /// Every counted occurrence is done or bumped.
        var isComplete: Bool { !isNeutral && value >= 1.0 }
    }

    struct StreakState: Equatable {
        let count: Int
        let isFrozen: Bool
    }

    /// One day of the 7-day ring, drawn like a calendar day (step 4).
    struct DayProgress: Identifiable, Equatable {
        let date: Date
        let dayKey: String
        /// One per list in use that day, morning → day → evening (`CalendarRules.segments`).
        let segments: [DaySegment]
        /// Something on any list was bumped from this day (the ↻ mark).
        var hasBump: Bool = false
        /// After today: drawn as a plain day, with a dot when something is planned.
        var isFuture: Bool = false
        var isPlanned: Bool = false

        var id: String { dayKey }
    }

    static func normalizedDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let dayCalendar = gregorianCalendar(using: calendar)
        let components = dayCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let dayCalendar = gregorianCalendar(using: calendar)
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        return dayCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func gregorianCalendar(using base: Calendar) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = base.timeZone
        return calendar
    }

    static func isToday(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        normalizedDay(day, calendar: calendar) == normalizedDay(now, calendar: calendar)
    }

    static func isPastDay(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        normalizedDay(day, calendar: calendar) < normalizedDay(now, calendar: calendar)
    }

    struct ClockFollow: Equatable {
        /// The day Home should show.
        let day: Date
        /// Whether Home keeps moving with the clock from here on.
        let followingToday: Bool
        /// Whether yesterday's manual list flip should be dropped (the day changed under the user).
        let clearsManualList: Bool
    }

    /// What Home does once the clock has moved (midnight, foregrounding, a time-zone change):
    /// - following today: move to the new today, dropping yesterday's manual list flip;
    /// - on a chosen day: stay put, but once that day *is* today (e.g. Monday picked on Sunday
    ///   evening), start following again, or Home would stick on it the day after.
    static func followClock(
        selectedDay: Date,
        followingToday: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> ClockFollow {
        let today = normalizedDay(now, calendar: calendar)
        let selected = normalizedDay(selectedDay, calendar: calendar)
        let day = followingToday ? today : selected
        return ClockFollow(day: day, followingToday: day == today, clearsManualList: day != selected)
    }

    enum StreakRisk: Equatable {
        case none
        /// Missed yesterday; today can still keep the streak.
        case saveable
        /// Missed yesterday and today's chance has passed: the streak resets tomorrow.
        case lost
    }

    /// Never-miss-twice risk from a frozen streak. `deadline` is when today stops counting
    /// (the morning cutoff); `nil` means today counts until midnight.
    static func streakRisk(isFrozen: Bool, deadline: Date?, now: Date) -> StreakRisk {
        guard isFrozen else { return .none }
        if let deadline, now >= deadline {
            return .lost
        }
        return .saveable
    }

    /// The list Home and the widget show on their own (DECISIONS.md, "3: flip times and settings"):
    /// Morning → Day → Evening, by today's `rules`. On any day but today it is the day list.
    ///
    /// - **Evening**, from its start time (unless Off) until midnight, if it has anything on it.
    ///   Once complete it stays showing, as done. It takes over from an unfinished morning too.
    /// - **Morning**, while it has something still to do (not complete, and not empty or all
    ///   skipped): until its set time, or, with no set time, until it's done ("the list itself
    ///   flips only when you're done"; the streak still counts only until 12:00).
    /// - **Day** otherwise.
    static func automaticList(
        for selectedDay: Date,
        now: Date,
        rules: DayRules,
        morning: CompletionState,
        eveningIsEmpty: Bool,
        calendar: Calendar = .current
    ) -> ContextualList {
        guard isToday(selectedDay, now: now, calendar: calendar) else { return .daily }
        if !eveningIsEmpty, let start = rules.eveningStart(on: now, calendar: calendar), now >= start {
            return .evening
        }
        let morningOpen = !morning.isNeutral && morning.value < 1.0
        switch rules.morningEnd {
        case .setTime:
            if morningOpen, now < rules.morningDeadline(on: now, calendar: calendar) { return .morning }
        case .doneOrSkipped:
            if morningOpen { return .morning }
        }
        return .daily
    }

    /// A list picked with the flip button. It lasts until `expiresAt`: the next moment the
    /// automatic list could change on its own (`DayRules.nextListBoundary`), or for a day other
    /// than today, until Home leaves that day.
    struct ManualListFlip: Equatable {
        let list: ContextualList
        let expiresAt: Date

        /// A flip made at `now` while today is on screen.
        static func today(_ list: ContextualList, at now: Date, rules: DayRules, calendar: Calendar = .current) -> ManualListFlip {
            ManualListFlip(list: list, expiresAt: rules.nextListBoundary(after: now, calendar: calendar))
        }

        /// A flip on another day, or one that never expires on its own (the screenshot harness).
        static func untilLeft(_ list: ContextualList) -> ManualListFlip {
            ManualListFlip(list: list, expiresAt: .distantFuture)
        }

        func isActive(at now: Date) -> Bool {
            now < expiresAt
        }

        /// The same flip, ending no later than `boundary` (today's next list boundary as the
        /// settings now stand), so moving the evening earlier also ends the flip earlier. A flip
        /// that never expires on its own is left alone.
        func capped(at boundary: Date) -> ManualListFlip {
            guard expiresAt != .distantFuture, boundary < expiresAt else { return self }
            return ManualListFlip(list: list, expiresAt: boundary)
        }
    }

    /// The list on screen: a manual flip while it lasts, otherwise the automatic choice. Read on
    /// every refresh (foreground, timer, edits), so a flip can't outlive its boundary even when
    /// the app was in the background as the boundary passed.
    static func shownList(automatic: ContextualList, flip: ManualListFlip?, now: Date) -> ContextualList {
        guard let flip, flip.isActive(at: now) else { return automatic }
        return flip.list
    }
}
