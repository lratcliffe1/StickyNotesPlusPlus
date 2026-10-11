import Foundation

/// Whether an occurrence may move to the next day (DECISIONS.md, "Bump limits" and "Repeating items").
enum BumpRules {
    /// - Repeating occurrences may move day by day up to their period end, so a daily one never moves.
    /// - Every occurrence also obeys its bump limit: can't bump; up to N bumps along the chain;
    ///   up to and including a deadline day; up to the last day of the calendar week it was first
    ///   added in; or unlimited.
    /// - Only open occurrences move.
    static func canBump(
        state: OccurrenceState,
        dayKey: String,
        isRepeating: Bool,
        periodEndDayKey: String?,
        limit: BumpLimit,
        bumpCount: Int,
        firstAddedDayKey: String,
        calendar: Calendar = .current
    ) -> Bool {
        guard state == .open else { return false }
        let math = DayMath(calendar: calendar)
        let target = math.adding(days: 1, to: dayKey)

        if isRepeating {
            guard let periodEndDayKey, target <= periodEndDayKey else { return false }
        }

        switch limit {
        case .cantBump:
            return false
        case let .upToDays(days):
            return bumpCount < days
        case let .untilDeadline(deadline):
            return target <= deadline
        case .endOfWeek:
            let anchor = firstAddedDayKey.isEmpty ? dayKey : firstAddedDayKey
            return target <= math.endOfWeek(anchor)
        case .unlimited:
            return true
        }
    }
}
