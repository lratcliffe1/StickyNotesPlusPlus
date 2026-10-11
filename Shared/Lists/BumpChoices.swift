import Foundation

/// A bump limit as the editors offer it: the kind, with the day count and deadline chosen alongside.
enum BumpLimitChoice: String, CaseIterable, Identifiable {
    case cantBump
    case upToDays
    case endOfWeek
    case untilDeadline
    case unlimited

    var id: String { rawValue }

    init(_ limit: BumpLimit) {
        switch limit {
        case .cantBump: self = .cantBump
        case .upToDays: self = .upToDays
        case .endOfWeek: self = .endOfWeek
        case .untilDeadline: self = .untilDeadline
        case .unlimited: self = .unlimited
        }
    }

    /// The limit this choice makes, or nil for "until deadline" without a deadline.
    func limit(days: Int, deadlineDayKey: String?) -> BumpLimit? {
        switch self {
        case .cantBump: return .cantBump
        case .upToDays: return .upToDays(max(1, days))
        case .endOfWeek: return .endOfWeek
        case .untilDeadline:
            guard let deadlineDayKey, !deadlineDayKey.isEmpty else { return nil }
            return .untilDeadline(dayKey: deadlineDayKey)
        case .unlimited: return .unlimited
        }
    }
}

/// The options behind the add field's menu (DECISIONS.md, 2b): must happen today (can't bump),
/// a deadline date, and a bump limit. A plain add keeps the default, up to 3 days.
struct OneOffOptions: Equatable {
    var mustHappenToday = false
    var deadlineDayKey: String?
    var limitChoice: BumpLimitChoice = .upToDays
    var days = 3

    /// "Must happen today" wins; "until deadline" without a deadline falls back to the default.
    var bumpLimit: BumpLimit {
        if mustHappenToday { return .cantBump }
        return limitChoice.limit(days: days, deadlineDayKey: deadlineDayKey) ?? .defaultForNewOneOffs
    }

    var isDefault: Bool {
        self == OneOffOptions()
    }
}

/// One line of what a bump costs, for the bump sheet (DECISIONS.md, 2b).
enum BumpCost: Equatable {
    /// Up to N bumps along the chain: `used` so far, of `limit`.
    case bumpsUsed(used: Int, limit: Int)
    /// May move up to and including this day.
    case deadline(dayKey: String)
    /// Until the last day of the week it was first added in; `isThisWeek` when that's the row's own week.
    case endOfWeek(dayKey: String, isThisWeek: Bool)
    /// A repeat: up to the end of its period (`period`, e.g. "week"), or, when `beforeNextDue`,
    /// up to the day before it's next due, which comes first.
    case periodEnd(dayKey: String, period: String?, beforeNextDue: Bool)
    case unlimited

    func text(calendar: Calendar = .current) -> String {
        switch self {
        case let .bumpsUsed(used, limit):
            return "\(used) of \(limit) \(limit == 1 ? "bump" : "bumps") used"
        case let .deadline(dayKey):
            return "Can bump until \(Self.format(dayKey, calendar: calendar))"
        case let .endOfWeek(dayKey, isThisWeek):
            return isThisWeek ? "Until the end of this week" : "Until the end of its week (\(Self.format(dayKey, calendar: calendar)))"
        case let .periodEnd(dayKey, period, beforeNextDue):
            if beforeNextDue {
                return "Can bump until \(Self.format(dayKey, calendar: calendar)), before it's next due"
            }
            return "Until the end of its \(period ?? "period") (\(Self.format(dayKey, calendar: calendar)))"
        case .unlimited:
            return "No bump limit"
        }
    }

    /// "Fri 17 Oct" style, in the user's locale.
    static func format(_ dayKey: String, calendar: Calendar = .current) -> String {
        guard let date = DayMath(calendar: calendar).noon(dayKey) else { return dayKey }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

extension BumpRules {
    /// What bumping this occurrence costs: its period end (repeats) and its limit, one line each.
    /// `repeatInfo` is the item's rule and start day, for naming the period.
    static func costs(
        dayKey: String,
        isRepeating: Bool,
        scheduledDayKey: String?,
        periodEndDayKey: String?,
        repeatInfo: (rule: RepeatRule, startDayKey: String)?,
        limit: BumpLimit,
        bumpCount: Int,
        firstAddedDayKey: String,
        calendar: Calendar = .current
    ) -> [BumpCost] {
        let math = DayMath(calendar: calendar)
        var lines: [BumpCost] = []

        if isRepeating, let periodEndDayKey {
            var beforeNextDue = false
            if let repeatInfo {
                let natural = repeatInfo.rule.naturalPeriodEnd(
                    for: scheduledDayKey ?? dayKey, startDayKey: repeatInfo.startDayKey, calendar: calendar
                )
                beforeNextDue = periodEndDayKey < natural
            }
            lines.append(.periodEnd(dayKey: periodEndDayKey, period: repeatInfo?.rule.periodName, beforeNextDue: beforeNextDue))
        }

        switch limit {
        case .cantBump:
            break
        case let .upToDays(days):
            lines.append(.bumpsUsed(used: bumpCount, limit: days))
        case let .untilDeadline(deadline):
            lines.append(.deadline(dayKey: deadline))
        case .endOfWeek:
            let anchor = firstAddedDayKey.isEmpty ? dayKey : firstAddedDayKey
            let end = math.endOfWeek(anchor)
            lines.append(.endOfWeek(dayKey: end, isThisWeek: end == math.endOfWeek(dayKey)))
        case .unlimited:
            if !isRepeating { lines.append(.unlimited) }
        }
        return lines
    }

    /// The title a bump gives the new copy, or nil when it can't go ahead. With Retype to bump on,
    /// something must be typed (and may differ from the old title); with it off, an empty field
    /// keeps the old title.
    static func bumpedTitle(typed: String, original: String, retypeRequired: Bool) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return retypeRequired ? nil : original
        }
        return trimmed
    }
}
