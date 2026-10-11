import Foundation

extension RepeatRule {
    /// "Daily", "Weekdays", "Weekly on Mon, Thu", "Every 3 days"… Weekly rules without chosen days
    /// fall on the start day's weekday.
    func summary(startDayKey: String?, calendar: Calendar = .current) -> String {
        switch kind {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .weekly: return "Weekly" + daysSuffix(startDayKey: startDayKey, calendar: calendar)
        case .everyTwoWeeks: return "Every 2 weeks" + daysSuffix(startDayKey: startDayKey, calendar: calendar)
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .everyNDays: return interval == 1 ? "Every day" : "Every \(interval) days"
        case .everyNWeeks:
            return (interval == 1 ? "Every week" : "Every \(interval) weeks") + daysSuffix(startDayKey: startDayKey, calendar: calendar)
        case .everyNMonths: return interval == 1 ? "Every month" : "Every \(interval) months"
        }
    }

    /// The weekdays it falls on, as `Calendar` numbers: the chosen ones, else the start day's.
    func effectiveWeekdays(startDayKey: String?, calendar: Calendar = .current) -> Set<Int> {
        if !weekdays.isEmpty { return weekdays }
        guard let startDayKey else { return [] }
        return [DayMath(calendar: calendar).weekday(startDayKey)]
    }

    /// Weekday numbers in the calendar's week order (Monday first in Munich).
    static func weekdayOrder(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func daysSuffix(startDayKey: String?, calendar: Calendar) -> String {
        let days = effectiveWeekdays(startDayKey: startDayKey, calendar: calendar)
        guard !days.isEmpty else { return "" }
        let names = Self.weekdayOrder(calendar: calendar)
            .filter(days.contains)
            .map { calendar.shortWeekdaySymbols[$0 - 1] }
        return " on " + names.joined(separator: ", ")
    }
}
