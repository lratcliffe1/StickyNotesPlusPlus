import Combine
import Foundation
import SwiftData
import os

/// What the calendar reads, one month at a time (step 4). Nothing is fetched for a month until it
/// scrolls into view; each month is then fetched once (a day-key range, `ListService.dayLooks` and
/// `ListService.plannedDayKeys`) and kept while the calendar is open. Read-only: tapping a day hands
/// it back to Home.
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

    let todayKey: String
    let calendar: Calendar
    /// The calendar's months: from the first entry's month (or the current one, if earlier) through
    /// the next 12 months.
    let months: [CalendarRules.Month]
    /// The lists in use (a day's circle has a segment for each) and the first entry's day (days
    /// before it are plain).
    let lists: [ListKind]
    let firstEntryDayKey: String?
    @Published private(set) var loaded: [String: MonthData] = [:]

    private let items: [Item]
    private let history: DayRulesHistory

    init(now: Date, defaults: UserDefaults, context: ModelContext, calendar: Calendar = .current) {
        self.calendar = calendar
        let todayKey = HomeModel.dayKey(for: now, calendar: calendar)
        self.todayKey = todayKey
        var lists: [ListKind] = []
        var firstEntryDayKey: String?
        var items: [Item] = []
        do {
            lists = try ListService.listsInUse(context: context)
            firstEntryDayKey = try ListService.firstEntryDayKey(context: context)
            items = try ListService.allItems(context: context)
        } catch {
            AppLogger.persistence.error("Calendar setup failed: \(error.localizedDescription, privacy: .public)")
        }
        self.lists = lists
        self.firstEntryDayKey = firstEntryDayKey
        self.items = items
        // Each day is judged by its own stored rules; today by the settings if it has none yet.
        history = DayRulesStore.resolvedHistory(in: defaults, todayKey: todayKey)
        months = CalendarRules.months(firstEntryDayKey: firstEntryDayKey, todayKey: todayKey)
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
