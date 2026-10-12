import Foundation

/// Calendars and plain-value occurrences shared by the list-rule tests.
enum TestCalendars {
    /// Munich: Europe/Berlin, weeks start on Monday, Saturday and Sunday are the weekend.
    static var munich: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Same zone, but weeks start on Sunday (the US convention).
    static var sundayFirst: Calendar {
        var calendar = munich
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private static var addedTicks = 0

    /// An item's `createdAt` long before any test day (1 Jan 2025), a second later on each call, so
    /// items made one after another keep their creation order (it was `Date()`), and none reads as
    /// added after a morning's cutoff (`ListRules.isBonus`) whatever day the tests run on.
    static func addedLongBefore() -> Date {
        addedTicks += 1
        return date("2025-01-01").addingTimeInterval(TimeInterval(addedTicks))
    }

    static func date(_ dayKey: String, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar = munich) -> Date {
        let ymd = DayMath.parse(dayKey) ?? DayMath.YMD(year: 1970, month: 1, day: 1)
        return calendar.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: hour, minute: minute)) ?? Date()
    }
}

/// A plain occurrence for the pure rules.
struct FactRow: OccurrenceFacts {
    var title: String = "Row"
    var dayKey: String
    var itemID: UUID? = nil
    var sortOrder: Int = 0
    var createdAt: Date = Date(timeIntervalSince1970: 0)
    var completedAt: Date? = nil
    var state: OccurrenceState
    var bumpLimit: BumpLimit = .unlimited
    var scheduledDayKey: String? = nil
    var periodEndDayKey: String? = nil
    var bumpedFromID: UUID? = nil
    var bumpCount: Int = 0
}
