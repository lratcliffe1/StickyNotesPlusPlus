import Foundation

/// A forgotten tick on a past day (DECISIONS.md, 2026-10-16, fix round 3): the time it's stamped
/// with, since the real one is lost. Liam ticks it after retyping the title, as on the day list.
enum BackfillRules {
    /// When a back-filled tick on `dayKey` is stamped, or nil for a key that isn't a date.
    /// - The day and evening lists count until midnight: 23:59:59 that day.
    /// - A morning row that counts: one second before that day's own deadline (its stored rules),
    ///   so it counts as on time. A deadline of 00:00 stamps 00:00 itself, still on its day and
    ///   not after the deadline.
    /// - A morning bonus row (added after the cutoff) never counts, and a tick before the row was
    ///   created would be nonsense: 23:59:59, like the other lists.
    static func stamp(
        list: ListKind,
        dayKey: String,
        rules: DayRules,
        isBonus: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        guard let day = HomeModel.date(fromDayKey: dayKey, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: day)
        if list == .morning, !isBonus {
            return max(start, rules.morningDeadline(on: start, calendar: calendar).addingTimeInterval(-1))
        }
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return next.addingTimeInterval(-1)
    }

    /// Whether the typed text confirms the tick: the title exactly, ignoring spaces at either end
    /// (the keyboard's trailing space after a word), and with curly and straight apostrophes,
    /// quotes and dashes alike (the keyboard's smart punctuation, which SwiftUI's text field can't turn off).
    static func confirms(_ typed: String, title: String) -> Bool {
        plain(typed.trimmingCharacters(in: .whitespaces)) == plain(title)
    }

    private static func plain(_ text: String) -> String {
        String(text.map { character -> Character in
            switch character {
            case "\u{2018}", "\u{2019}", "\u{201B}": return "'"
            case "\u{201C}", "\u{201D}", "\u{201E}": return "\""
            case "\u{2013}", "\u{2014}": return "-"
            default: return character
            }
        })
    }
}
