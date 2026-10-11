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
        /// "When everything's done or skipped": the list flips only when it's done or all skipped
        /// (or the evening starts); the streak counts until 12:00.
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

    private enum CodingKeys: String, CodingKey {
        case morningEnd, morningEndMinutes, eveningStartMinutes
    }

    /// Field by field, each with a default, so a record written by a later build (a new field, a
    /// new morning mode) still reads: what can't be read falls back to the old 09:00 rules.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let end = try? container.decodeIfPresent(MorningEnd.self, forKey: .morningEnd)
        let minutes = try? container.decodeIfPresent(Int.self, forKey: .morningEndMinutes)
        let evening = try? container.decodeIfPresent(Int.self, forKey: .eveningStartMinutes)
        self.init(
            morningEnd: end ?? Self.legacy.morningEnd,
            morningEndMinutes: minutes ?? Self.legacyCutoffMinutes,
            eveningStartMinutes: evening
        )
    }

    // MARK: - Changing today's rules

    /// Whether two rules end the morning the same way (with no set time, its hidden time is moot).
    func hasSameMorning(as other: DayRules) -> Bool {
        guard morningEnd == other.morningEnd else { return false }
        return morningEnd == .doneOrSkipped || morningEndMinutes == other.morningEndMinutes
    }

    /// Today's rules after a settings change at `now`. The evening start never affects a streak
    /// (the evening counts until midnight), so it changes today. The morning part changes today
    /// only while today's morning is still undecided: before both the old and the new deadline,
    /// and not already complete. Otherwise today keeps its morning and the change applies from
    /// tomorrow (each day keeps the cutoff it had).
    static func todayAfterChange(
        old: DayRules,
        new: DayRules,
        now: Date,
        morningComplete: Bool,
        calendar: Calendar = .current
    ) -> (rules: DayRules, morningFromTomorrow: Bool) {
        var result = new
        guard !old.hasSameMorning(as: new) else { return (result, false) }
        let undecided = !morningComplete
            && now < old.morningDeadline(on: now, calendar: calendar)
            && now < new.morningDeadline(on: now, calendar: calendar)
        if undecided { return (result, false) }
        result.morningEnd = old.morningEnd
        result.morningEndMinutes = old.morningEndMinutes
        return (result, true)
    }

    /// When the morning stops counting for the streak: the set time, or 12:00 with no set time.
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

    /// The next moment Home must refresh on its own after `now`: the morning's deadline (set time
    /// or 12:00, which also settles the never-miss-twice banner), the evening's start, or the next
    /// midnight, whichever comes first.
    func nextBoundary(after now: Date, calendar: Calendar = .current) -> Date {
        earliest(after: now, of: [morningDeadline(on: now, calendar: calendar), eveningStart(on: now, calendar: calendar)], calendar: calendar)
    }

    /// The next moment the automatic list itself can change after `now`: a set time, the evening's
    /// start, or midnight. With no set time, 12:00 isn't one: the list flips only when the morning
    /// is done. A manual flip lasts until this moment.
    func nextListBoundary(after now: Date, calendar: Calendar = .current) -> Date {
        let morningEnd: Date? = morningEnd == .setTime ? morningDeadline(on: now, calendar: calendar) : nil
        return earliest(after: now, of: [morningEnd, eveningStart(on: now, calendar: calendar)], calendar: calendar)
    }

    private func earliest(after now: Date, of times: [Date?], calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(3_600)
        return times.compactMap { $0 }.filter { $0 > now && $0 < midnight }.min() ?? midnight
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
