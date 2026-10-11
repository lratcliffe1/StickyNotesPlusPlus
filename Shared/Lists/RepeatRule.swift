import Foundation

/// Apple Reminders-style repeats (DECISIONS.md, "Repeats follow Apple Reminders").
/// The raw values are stored: never rename them.
enum RepeatKind: String, CaseIterable, Codable {
    case daily
    /// The calendar's working days (not its weekend).
    case weekdays
    /// The calendar's weekend.
    case weekends
    /// Every week on the chosen weekdays (the start day's weekday if none are chosen).
    case weekly
    /// Every other week on the start day's weekday (or the chosen weekdays), counted from the start week.
    case everyTwoWeeks
    /// The start day's day of month; months without it use their last day.
    case monthly
    /// The start day's month and day; 29 February falls on 28 February in other years.
    case yearly
    /// Custom: every N days from the start day.
    case everyNDays
    /// Custom: every N weeks on the chosen weekdays, counted from the start week.
    case everyNWeeks
    /// Custom: every N months on the start day's day of month (last day if the month is shorter).
    case everyNMonths
}

/// A repeat rule, pure and calendar-driven. Days are `YYYY-MM-DD` keys.
struct RepeatRule: Hashable {
    var kind: RepeatKind
    /// N for the custom rules (at least 1); ignored by the presets.
    var interval: Int
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday) for the weekly rules.
    var weekdays: Set<Int>

    init(kind: RepeatKind, interval: Int = 1, weekdays: Set<Int> = []) {
        self.kind = kind
        self.interval = max(1, interval)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
    }

    static let daily = RepeatRule(kind: .daily)
    static let weekdays = RepeatRule(kind: .weekdays)
    static let weekends = RepeatRule(kind: .weekends)
    static let everyTwoWeeks = RepeatRule(kind: .everyTwoWeeks)
    static let monthly = RepeatRule(kind: .monthly)
    static let yearly = RepeatRule(kind: .yearly)

    static func weekly(on weekdays: Set<Int>) -> RepeatRule {
        RepeatRule(kind: .weekly, weekdays: weekdays)
    }

    static func everyNDays(_ days: Int) -> RepeatRule {
        RepeatRule(kind: .everyNDays, interval: days)
    }

    static func everyNWeeks(_ weeks: Int, on weekdays: Set<Int>) -> RepeatRule {
        RepeatRule(kind: .everyNWeeks, interval: weeks, weekdays: weekdays)
    }

    static func everyNMonths(_ months: Int) -> RepeatRule {
        RepeatRule(kind: .everyNMonths, interval: months)
    }

    // MARK: - Storage

    /// Weekdays as a bitmask: bit 0 = Sunday … bit 6 = Saturday.
    var weekdayMask: Int {
        weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    /// Rebuilds a rule from its stored parts. An unknown kind falls back to daily.
    init(kindRaw: String, interval: Int, weekdayMask: Int) {
        let days = Set((1...7).filter { weekdayMask & (1 << ($0 - 1)) != 0 })
        self.init(kind: RepeatKind(rawValue: kindRaw) ?? .daily, interval: interval, weekdays: days)
    }

    // MARK: - Rules

    /// Whether the rule puts an occurrence on `dayKey`, for an item that started on `startDayKey`.
    func occurs(on dayKey: String, startDayKey: String, calendar: Calendar = .current) -> Bool {
        occurs(on: dayKey, startDayKey: startDayKey, math: DayMath(calendar: calendar))
    }

    /// The last day an occurrence scheduled on `dayKey` may be bumped to: the end of the rule's
    /// period (the day for daily; the calendar week for weekly rules; the 2- or N-week block from
    /// the start week; the month or N-month block; the calendar year), but never on or past the
    /// next scheduled occurrence, so a bump can't land on the item's next day.
    func periodEnd(for dayKey: String, startDayKey: String, calendar: Calendar = .current) -> String {
        let math = DayMath(calendar: calendar)
        let blockEnd = blockEnd(for: dayKey, startDayKey: startDayKey, math: math)
        var cursor = math.adding(days: 1, to: dayKey)
        while cursor <= blockEnd {
            if occurs(on: cursor, startDayKey: startDayKey, math: math) {
                return math.adding(days: -1, to: cursor)
            }
            cursor = math.adding(days: 1, to: cursor)
        }
        return max(blockEnd, dayKey)
    }

    /// The end of the rule's period block for an occurrence on `dayKey`, ignoring the next
    /// occurrence (`periodEnd` stops before that). Compared with `periodEnd`, it tells whether the
    /// next due day cuts a bump window short.
    func naturalPeriodEnd(for dayKey: String, startDayKey: String, calendar: Calendar = .current) -> String {
        max(blockEnd(for: dayKey, startDayKey: startDayKey, math: DayMath(calendar: calendar)), dayKey)
    }

    /// The period's name, for "Until the end of its week": "day", "week", "2 weeks", "month", "year"…
    var periodName: String {
        switch kind {
        case .daily:
            return "day"
        case .everyNDays:
            return interval == 1 ? "day" : "\(interval) days"
        case .weekdays, .weekends, .weekly:
            return "week"
        case .everyTwoWeeks:
            return "2 weeks"
        case .everyNWeeks:
            return interval == 1 ? "week" : "\(interval) weeks"
        case .monthly:
            return "month"
        case .everyNMonths:
            return interval == 1 ? "month" : "\(interval) months"
        case .yearly:
            return "year"
        }
    }

    func occurs(on dayKey: String, startDayKey: String, math: DayMath) -> Bool {
        guard dayKey >= startDayKey, let day = DayMath.parse(dayKey), let start = DayMath.parse(startDayKey) else {
            return false
        }

        switch kind {
        case .daily:
            return true
        case .weekdays:
            return !math.isWeekend(dayKey)
        case .weekends:
            return math.isWeekend(dayKey)
        case .weekly:
            return effectiveWeekdays(startDayKey: startDayKey, math: math).contains(math.weekday(dayKey))
        case .everyTwoWeeks:
            return occursInWeekBlock(dayKey, startDayKey: startDayKey, weeks: 2, math: math)
        case .everyNWeeks:
            return occursInWeekBlock(dayKey, startDayKey: startDayKey, weeks: interval, math: math)
        case .monthly:
            return occursInMonthBlock(day, start: start, months: 1, startDayKey: startDayKey, dayKey: dayKey, math: math)
        case .everyNMonths:
            return occursInMonthBlock(day, start: start, months: interval, startDayKey: startDayKey, dayKey: dayKey, math: math)
        case .yearly:
            guard day.month == start.month else { return false }
            return day.day == min(start.day, math.daysInMonth(year: day.year, month: day.month))
        case .everyNDays:
            return math.daysBetween(startDayKey, dayKey) % interval == 0
        }
    }

    // MARK: - Helpers

    private func effectiveWeekdays(startDayKey: String, math: DayMath) -> Set<Int> {
        weekdays.isEmpty ? [math.weekday(startDayKey)] : weekdays
    }

    /// Weeks from the start week to `dayKey`'s week.
    private func weekIndex(_ dayKey: String, startDayKey: String, math: DayMath) -> Int {
        math.daysBetween(math.startOfWeek(startDayKey), math.startOfWeek(dayKey)) / 7
    }

    private func occursInWeekBlock(_ dayKey: String, startDayKey: String, weeks: Int, math: DayMath) -> Bool {
        guard effectiveWeekdays(startDayKey: startDayKey, math: math).contains(math.weekday(dayKey)) else {
            return false
        }
        return weekIndex(dayKey, startDayKey: startDayKey, math: math) % weeks == 0
    }

    private func occursInMonthBlock(
        _ day: DayMath.YMD,
        start: DayMath.YMD,
        months: Int,
        startDayKey: String,
        dayKey: String,
        math: DayMath
    ) -> Bool {
        guard math.monthsBetween(startDayKey, dayKey) % months == 0 else { return false }
        return day.day == min(start.day, math.daysInMonth(year: day.year, month: day.month))
    }

    private func blockEnd(for dayKey: String, startDayKey: String, math: DayMath) -> String {
        switch kind {
        case .daily:
            return dayKey
        case .everyNDays:
            return math.adding(days: interval - 1, to: dayKey)
        case .weekdays, .weekends, .weekly:
            return math.endOfWeek(dayKey)
        case .everyTwoWeeks, .everyNWeeks:
            let weeks = kind == .everyTwoWeeks ? 2 : interval
            let startWeek = math.startOfWeek(startDayKey)
            let block = max(0, weekIndex(dayKey, startDayKey: startDayKey, math: math)) / weeks
            return math.adding(days: (block + 1) * weeks * 7 - 1, to: startWeek)
        case .monthly, .everyNMonths:
            let months = kind == .monthly ? 1 : interval
            guard let start = DayMath.parse(startDayKey) else { return dayKey }
            let block = max(0, math.monthsBetween(startDayKey, dayKey)) / months
            let last = DayMath.shift(year: start.year, month: start.month, by: (block + 1) * months - 1)
            return math.lastDayOfMonth(year: last.year, month: last.month)
        case .yearly:
            guard let day = DayMath.parse(dayKey) else { return dayKey }
            return DayMath.key(year: day.year, month: 12, day: 31)
        }
    }
}
