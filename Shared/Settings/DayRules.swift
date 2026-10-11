import Foundation

/// The flip-time rules one day is judged by (DECISIONS.md, 2026-10-11 evening, "3: flip times and
/// settings"): how its morning ends, and when its evening starts. Each day stores the rules it had
/// the first time it was read (`DayRulesStore`), so changing a setting never recounts the past.
struct DayRules: Codable, Equatable {
    /// How the morning ends.
    enum MorningEnd: String, Codable, CaseIterable {
        /// "At a set time": the list shows until it's done or the time passes, which is also the
        /// streak deadline.
        case setTime
        /// "When everything's done or skipped": the list flips as soon as it's done or all skipped;
        /// the streak counts until 12:00, when the list flips to the day list anyway (provisional).
        case doneOrSkipped
    }

    var morningEnd: MorningEnd
    /// Minutes after midnight the morning ends at, in `setTime` mode. Kept in the other mode too.
    var morningEndMinutes: Int
    /// Minutes after midnight the evening list starts at; nil when the evening is Off.
    var eveningStartMinutes: Int?

    /// 12:00: the morning streak deadline, and the latest flip, with no set time.
    static let noonMinutes = 12 * 60
    /// The old fixed cutoff. Days from before this build have no stored rules and use it.
    static let legacyCutoffMinutes = 9 * 60
    static let defaultEveningStartMinutes = 21 * 60

    /// What every day before the first stored one is judged by: the old fixed 09:00 cutoff.
    static let legacy = DayRules(
        morningEnd: .setTime,
        morningEndMinutes: legacyCutoffMinutes,
        eveningStartMinutes: defaultEveningStartMinutes
    )

    init(morningEnd: MorningEnd, morningEndMinutes: Int, eveningStartMinutes: Int?) {
        self.morningEnd = morningEnd
        self.morningEndMinutes = Self.clamped(morningEndMinutes)
        self.eveningStartMinutes = eveningStartMinutes.map(Self.clamped)
    }

    /// When the morning stops counting for the streak (the set time, or 12:00 with no set time),
    /// and the latest moment the morning list shows on its own.
    var morningDeadlineMinutes: Int {
        switch morningEnd {
        case .setTime: return morningEndMinutes
        case .doneOrSkipped: return Self.noonMinutes
        }
    }

    /// The morning streak deadline on `day` (wall-clock time, so DST days keep it).
    func morningDeadline(on day: Date, calendar: Calendar = .current) -> Date {
        Self.time(morningDeadlineMinutes, on: day, calendar: calendar)
    }

    /// When the evening list starts on `day`, or nil when the evening is Off.
    func eveningStart(on day: Date, calendar: Calendar = .current) -> Date? {
        eveningStartMinutes.map { Self.time($0, on: day, calendar: calendar) }
    }

    /// The next moment the automatic list can change on its own after `now`: the morning's end
    /// (set time or 12:00), the evening's start, or the next midnight, whichever comes first.
    func nextBoundary(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(3_600)
        let candidates = [morningDeadline(on: today, calendar: calendar), eveningStart(on: today, calendar: calendar)]
            .compactMap { $0 }
            .filter { $0 > now && $0 < midnight }
        return candidates.min() ?? midnight
    }

    /// `minutes` after midnight on `day`'s date, as a wall-clock time: 09:00 is 09:00 on the days
    /// the clocks change. A time the clocks skip (02:30 on the spring change) becomes the next
    /// time that exists.
    static func time(_ minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        let clamped = Self.clamped(minutes)
        guard clamped > 0 else { return start }
        let components = DateComponents(hour: clamped / 60, minute: clamped % 60)
        if let exact = calendar.nextDate(after: start, matching: components, matchingPolicy: .nextTime),
           calendar.isDate(exact, inSameDayAs: start) {
            return exact
        }
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? start
    }

    static func clamped(_ minutes: Int) -> Int {
        max(0, min(1_439, minutes))
    }
}
