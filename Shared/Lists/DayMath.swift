import Foundation

/// Day arithmetic on `YYYY-MM-DD` day keys.
///
/// Uses a Gregorian copy of the calendar passed in, keeping its time zone, locale, first weekday
/// and minimum days in the first week, so weeks start where that calendar says (Monday in Munich)
/// and weekends follow its locale. Works at noon, so a DST change never shifts a day.
struct DayMath {
    struct YMD: Equatable {
        let year: Int
        let month: Int
        let day: Int
    }

    let calendar: Calendar

    init(calendar base: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = base.timeZone
        gregorian.locale = base.locale
        gregorian.firstWeekday = base.firstWeekday
        gregorian.minimumDaysInFirstWeek = base.minimumDaysInFirstWeek
        calendar = gregorian
    }

    static func parse(_ key: String) -> YMD? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return YMD(year: year, month: month, day: day)
    }

    static func key(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon on that day in the calendar's time zone.
    func noon(_ key: String) -> Date? {
        guard let ymd = Self.parse(key) else { return nil }
        return calendar.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: 12))
    }

    func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return Self.key(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    func adding(days: Int, to key: String) -> String {
        guard days != 0 else { return key }
        guard let date = noon(key), let moved = calendar.date(byAdding: .day, value: days, to: date) else {
            return key
        }
        return self.key(for: moved)
    }

    /// Whole days from `from` to `to` (negative if `to` is earlier).
    func daysBetween(_ from: String, _ to: String) -> Int {
        guard let start = noon(from), let end = noon(to) else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// 1 = Sunday … 7 = Saturday, as `Calendar` numbers weekdays.
    func weekday(_ key: String) -> Int {
        guard let date = noon(key) else { return 1 }
        return calendar.component(.weekday, from: date)
    }

    func isWeekend(_ key: String) -> Bool {
        guard let date = noon(key) else { return false }
        return calendar.isDateInWeekend(date)
    }

    /// First day of the calendar week containing `key`, per `firstWeekday`.
    func startOfWeek(_ key: String) -> String {
        let offset = (weekday(key) - calendar.firstWeekday + 7) % 7
        return adding(days: -offset, to: key)
    }

    /// Last day of the calendar week containing `key`.
    func endOfWeek(_ key: String) -> String {
        adding(days: 6, to: startOfWeek(key))
    }

    func daysInMonth(year: Int, month: Int) -> Int {
        guard
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
            let range = calendar.range(of: .day, in: .month, for: date)
        else {
            return 31
        }
        return range.count
    }

    /// Calendar months from `from`'s month to `to`'s month; the days are ignored.
    func monthsBetween(_ from: String, _ to: String) -> Int {
        guard let start = Self.parse(from), let end = Self.parse(to) else { return 0 }
        return (end.year - start.year) * 12 + (end.month - start.month)
    }

    /// The year and month `months` after the given one.
    static func shift(year: Int, month: Int, by months: Int) -> (year: Int, month: Int) {
        let total = year * 12 + (month - 1) + months
        let shiftedYear = Int((Double(total) / 12).rounded(.down))
        return (shiftedYear, total - shiftedYear * 12 + 1)
    }

    func lastDayOfMonth(year: Int, month: Int) -> String {
        Self.key(year: year, month: month, day: daysInMonth(year: year, month: month))
    }
}
