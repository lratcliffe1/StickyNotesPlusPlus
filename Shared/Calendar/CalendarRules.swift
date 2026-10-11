import Foundation

/// One list's part of a day's circle (the calendar and the 7-day ring draw the same thing).
struct DaySegment: Equatable {
    let list: ListKind
    /// How the day looks for this list (`ListRules.dayLooks`); nil when nothing counted (neutral).
    let look: ListRules.DayLook?
}

/// Pure rules for the calendar (DECISIONS.md, 2026-10-11 evening, "4: calendar"): which months it
/// shows, how a month's grid is laid out, which lists a day's circle has, which future days have
/// something planned, and how far back a range of days must fetch to judge its days.
///
/// Day identity is the `dayKey`; all day arithmetic goes through `DayMath` (noon-based, so DST-safe).
/// Weeks start on the calendar's `firstWeekday` (Monday in Munich), never a hardcoded day.
enum CalendarRules {
    // MARK: - Months

    /// One calendar month.
    struct Month: Hashable, Identifiable, Comparable {
        let year: Int
        let month: Int

        /// "YYYY-MM".
        var id: String { String(format: "%04d-%02d", year, month) }

        var firstDayKey: String { DayMath.key(year: year, month: month, day: 1) }

        func lastDayKey(math: DayMath) -> String { math.lastDayOfMonth(year: year, month: month) }

        func shifted(by months: Int) -> Month {
            let shifted = DayMath.shift(year: year, month: month, by: months)
            return Month(year: shifted.year, month: shifted.month)
        }

        /// The month a day key falls in.
        init?(containing dayKey: String) {
            guard let ymd = DayMath.parse(dayKey) else { return nil }
            self.init(year: ymd.year, month: ymd.month)
        }

        init(year: Int, month: Int) {
            self.year = year
            self.month = month
        }

        static func < (lhs: Month, rhs: Month) -> Bool {
            (lhs.year, lhs.month) < (rhs.year, rhs.month)
        }
    }

    /// How many months after the current one the calendar runs to.
    static let monthsAhead = 12

    /// The calendar's months: from the earlier of the first entry's month and the current month,
    /// through `monthsAhead` months after the current one.
    static func months(firstEntryDayKey: String?, todayKey: String, monthsAhead: Int = monthsAhead) -> [Month] {
        guard let current = Month(containing: todayKey) else { return [] }
        let first = firstEntryDayKey.flatMap(Month.init(containing:)).map { min($0, current) } ?? current
        let last = current.shifted(by: monthsAhead)
        var months: [Month] = []
        var cursor = first
        while cursor <= last {
            months.append(cursor)
            cursor = cursor.shifted(by: 1)
        }
        return months
    }

    // MARK: - A month's grid

    /// Empty slots before day 1, for weeks starting on the calendar's `firstWeekday`.
    static func leadingBlanks(for month: Month, calendar: Calendar) -> Int {
        let math = DayMath(calendar: calendar)
        return (math.weekday(month.firstDayKey) - math.calendar.firstWeekday + 7) % 7
    }

    /// The month as weeks of seven slots: a day key, or nil for the days outside the month.
    static func weeks(for month: Month, calendar: Calendar) -> [[String?]] {
        let math = DayMath(calendar: calendar)
        let days = math.daysInMonth(year: month.year, month: month.month)
        var slots: [String?] = Array(repeating: nil, count: leadingBlanks(for: month, calendar: calendar))
        slots += (1...days).map { DayMath.key(year: month.year, month: month.month, day: $0) }
        while slots.count % 7 != 0 {
            slots.append(nil)
        }
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    /// The weekday column headers, starting on the calendar's `firstWeekday`.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    // MARK: - A day's segments

    /// The segments of a day's circle: one per list in use (`ListService.isInUse`, the same rule as
    /// the header's evening streak), in morning → day → evening order, each with its day look. A day
    /// before the first entry has none: it's drawn as a plain date.
    static func segments(
        on dayKey: String,
        lists: [ListKind],
        firstEntryDayKey: String?,
        looks: [ListKind: [String: ListRules.DayLook]]
    ) -> [DaySegment] {
        guard let firstEntryDayKey, dayKey >= firstEntryDayKey else { return [] }
        return ListKind.allCases
            .filter { lists.contains($0) }
            .map { DaySegment(list: $0, look: looks[$0]?[dayKey]) }
    }

    // MARK: - Planned days

    /// Whether a recurring item falls due on `dayKey`: it exists then and its rule lands there.
    static func isDue(_ schedule: ListRules.ItemSchedule, on dayKey: String, math: DayMath) -> Bool {
        schedule.isActive(on: dayKey) && schedule.rule.occurs(on: dayKey, startDayKey: schedule.startDayKey, math: math)
    }

    /// Whether a rule falls due every day. Its days carry no news, so they get no future-day dot.
    static func isEveryDay(_ rule: RepeatRule) -> Bool {
        rule.kind == .daily || (rule.kind == .everyNDays && rule.interval == 1)
    }

    /// Days from `startKey` through `endKey` with something planned worth a dot: a row exists (a
    /// one-off added ahead, or a copy bumped in), or a recurring item that isn't every-day falls due
    /// (a daily item would put a dot on every day, so it doesn't count).
    static func plannedDays(
        rowDayKeys: Set<String>,
        schedules: [ListRules.ItemSchedule],
        from startKey: String,
        through endKey: String,
        calendar: Calendar
    ) -> Set<String> {
        guard startKey <= endKey else { return [] }
        let math = DayMath(calendar: calendar)
        let telling = schedules.filter { !isEveryDay($0.rule) }
        var planned = Set(rowDayKeys.filter { $0 >= startKey && $0 <= endKey })
        var day = startKey
        while day <= endKey {
            if !planned.contains(day), telling.contains(where: { isDue($0, on: day, math: math) }) {
                planned.insert(day)
            }
            day = math.adding(days: 1, to: day)
        }
        return planned
    }

    // MARK: - What a range of days must fetch

    /// The first day whose rows can change how the days from `startKey` on look: an occurrence
    /// scheduled up to the longest repeat period before `startKey` can still be missed on a period
    /// end inside the range (`ListRules.dayLooks`). With only daily items, `startKey` itself.
    static func fetchStart(for startKey: String, schedules: [ListRules.ItemSchedule], calendar: Calendar) -> String {
        let lookback = schedules.map(\.rule.longestPeriodDays).max() ?? 0
        return DayMath(calendar: calendar).adding(days: -lookback, to: startKey)
    }

    // MARK: - Accessibility

    /// "Monday 12 October: morning done, day missed, bumped". Past days and today say each list's
    /// state, in the words of its drawn shape (`DayMark`); future days say whether anything is
    /// planned. `todayOpenLists`: the lists still undecided today (`DayMark.openListsToday`); nil
    /// treats every list as still open today.
    static func accessibilityLabel(
        dayKey: String,
        todayKey: String,
        segments: [DaySegment],
        hasBump: Bool,
        isPlanned: Bool,
        todayOpenLists: Set<ListKind>? = nil,
        calendar: Calendar
    ) -> String {
        let date = spokenDate(dayKey, calendar: calendar)
        let prefix = dayKey == todayKey ? "Today, \(date)" : date
        var parts: [String]
        if dayKey > todayKey {
            parts = [isPlanned ? "something planned" : "nothing planned"]
        } else {
            let open = dayKey == todayKey ? (todayOpenLists ?? Set(ListKind.allCases)) : []
            parts = segments.map { "\(listName($0.list)) \(stateWords($0.look, isOpen: open.contains($0.list)))" }
            if hasBump { parts.append("bumped") }
        }
        guard !parts.isEmpty else { return prefix }
        return "\(prefix): \(parts.joined(separator: ", "))"
    }

    /// "Monday 12 October" in the calendar's locale.
    static func spokenDate(_ dayKey: String, calendar: Calendar) -> String {
        formatted(dayKey, template: "EEEEdMMMM", calendar: calendar)
    }

    /// "October 2026": a month's title in the calendar's locale.
    static func monthTitle(_ month: Month, calendar: Calendar) -> String {
        formatted(month.firstDayKey, template: "MMMMyyyy", calendar: calendar)
    }

    /// A day key formatted from a localized template, at noon on that day.
    static func formatted(_ dayKey: String, template: String, calendar: Calendar) -> String {
        let math = DayMath(calendar: calendar)
        guard let date = math.noon(dayKey) else { return dayKey }
        return FormatterCache.shared.formatter(template: template, calendar: math.calendar, locale: calendar.locale ?? .current)
            .string(from: date)
    }

    static func listName(_ list: ListKind) -> String {
        switch list {
        case .morning: return "morning"
        case .day: return "day"
        case .evening: return "evening"
        }
    }

    /// One list's state in words, matching its drawn shape (`DayMark`).
    static func stateWords(_ look: ListRules.DayLook?, isOpen: Bool) -> String {
        DayMark.words(for: look, isOpen: isOpen)
    }
}

/// Date formatters are costly to make and the calendar formats every day cell on every render:
/// one per template, locale and time zone, made once.
final class FormatterCache {
    static let shared = FormatterCache()

    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(calendar.timeZone.identifier)|\(calendar.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter
    }
}

extension RepeatRule {
    /// The most days an occurrence's period end can fall after its scheduled day (an upper bound of
    /// `periodEnd(for:) - day`): how far back a range of days must look for misses landing in it.
    var longestPeriodDays: Int {
        switch kind {
        case .daily: return 0
        case .everyNDays: return interval - 1
        case .weekdays, .weekends, .weekly: return 6
        case .everyTwoWeeks: return 13
        case .everyNWeeks: return 7 * interval - 1
        case .monthly: return 30
        case .everyNMonths: return 31 * interval - 1
        case .yearly: return 365
        }
    }
}
