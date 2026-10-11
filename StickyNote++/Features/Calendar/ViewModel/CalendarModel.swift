import Combine
import Foundation
import SwiftData
import os

/// What the calendar reads, one month at a time (step 4). Nothing is fetched for a month until it
/// scrolls into view; each month is then fetched once (a day-key range, `ListService.dayLooks` and
/// `ListService.plannedDayKeys`) and kept until `reload` (foreground, a new day). Read-only: tapping
/// a day hands it back to Home.
@MainActor
final class CalendarModel: ObservableObject {
    /// One month's days, as the calendar draws them.
    struct MonthData {
        /// Past days and today: each list's day look (the streak's own rule).
        var looks: [ListKind: [String: ListRules.DayLook]] = [:]
        var bumpedDays: Set<String> = []
        /// Days after today with something planned.
        var plannedDays: Set<String> = []
    }

    let calendar: Calendar
    @Published private(set) var todayKey: String
    /// The calendar's months: from the first entry's month (or the current one, if earlier) through
    /// the next 12 months.
    @Published private(set) var months: [CalendarRules.Month] = []
    /// The lists in use (a day's circle has a segment for each) and the first entry's day (days
    /// before it are plain).
    @Published private(set) var lists: [ListKind] = []
    @Published private(set) var firstEntryDayKey: String?
    /// Today's lists still undecided (`DayMark.openListsToday`), drawn as in progress, not missed.
    @Published private(set) var todayOpenLists: Set<ListKind> = []
    /// The next moment today's open lists can change (the morning's streak deadline, the evening's
    /// start or midnight: `DayRules.nextBoundary`, as Home's timer). The view reloads then.
    @Published private(set) var nextBoundary: Date = .distantFuture
    @Published private(set) var loaded: [String: MonthData] = [:]
    /// Bumped by each `reload`, so the months on screen fetch again.
    @Published private(set) var generation = 0

    private let defaults: UserDefaults
    private var items: [Item] = []
    private var history = DayRulesHistory()

    init(now: Date, defaults: UserDefaults, context: ModelContext, calendar: Calendar = .current) {
        self.calendar = calendar
        self.defaults = defaults
        todayKey = HomeModel.dayKey(for: now, calendar: calendar)
        reload(now: now, context: context)
    }

    /// Reads everything again and forgets the fetched months (they refetch as they show): on
    /// opening, on returning to the foreground (the widget may have written) and when the day
    /// changes, so "today" and the months never go stale while the calendar is open.
    func reload(now: Date, context: ModelContext) {
        todayKey = HomeModel.dayKey(for: now, calendar: calendar)
        do {
            lists = try ListService.listsInUse(context: context)
            firstEntryDayKey = try ListService.firstEntryDayKey(context: context)
            items = try ListService.allItems(context: context)
        } catch {
            AppLogger.persistence.error("Calendar setup failed: \(error.localizedDescription, privacy: .public)")
        }
        // Each day is judged by its own stored rules; today by the settings if it has none yet.
        history = DayRulesStore.resolvedHistory(in: defaults, todayKey: todayKey)
        todayOpenLists = DayMark.openListsToday(now: now, rules: history.rules(for: todayKey), calendar: calendar)
        nextBoundary = history.rules(for: todayKey).nextBoundary(after: now, calendar: calendar)
        months = CalendarRules.months(firstEntryDayKey: firstEntryDayKey, todayKey: todayKey)
        loaded = [:]
        generation += 1
    }

    var currentMonth: CalendarRules.Month? {
        CalendarRules.Month(containing: todayKey)
    }

    /// Fetches a month the first time it appears.
    func load(_ month: CalendarRules.Month, context: ModelContext) {
        guard loaded[month.id] == nil else { return }
        let math = DayMath(calendar: calendar)
        let first = month.firstDayKey
        let last = month.lastDayKey(math: math)
        var data = MonthData()
        do {
            if first <= todayKey {
                let past = try ListService.dayLooks(
                    from: first, through: min(last, todayKey), todayKey: todayKey,
                    history: history, context: context, items: items, calendar: calendar
                )
                data.looks = past.looks
                data.bumpedDays = past.bumpedDays
            }
            if last > todayKey {
                data.plannedDays = try ListService.plannedDayKeys(
                    from: max(first, math.adding(days: 1, to: todayKey)), through: last,
                    context: context, items: items, calendar: calendar
                )
            }
        } catch {
            AppLogger.persistence.error("Calendar month \(month.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        loaded[month.id] = data
    }
}
