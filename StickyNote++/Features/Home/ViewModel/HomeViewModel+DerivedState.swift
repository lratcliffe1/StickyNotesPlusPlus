import Foundation
import SwiftData

/// Derived UI state for `HomeViewModel`: which list shows, the 7-day ring, the streaks and the
/// never-miss-twice risk. The rules themselves are in `ListRules` (tested in `Shared/`).
extension HomeViewModel {
    func recalculateDerivedState(context: ModelContext) {
        let calendar = Calendar.current
        isReadOnly = HomeModel.isPastDay(selectedDay, now: now, calendar: calendar)
        let anchorDay = HomeModel.normalizedDay(selectedDay, calendar: calendar)

        automaticContextualList = HomeModel.automaticList(
            for: selectedDay,
            now: now,
            rules: todaysRules,
            morning: morningCompletionState,
            eveningIsEmpty: eveningEntries.isEmpty,
            calendar: calendar
        )
        // A flip that has expired (its boundary passed, even while the app was in the background)
        // is dropped here, on every refresh.
        if let flip = manualListFlip {
            let capped = flip.capped(at: todaysRules.nextListBoundary(after: now, calendar: calendar))
            manualListFlip = capped.isActive(at: now) ? capped : nil
        }
        contextualList = HomeModel.shownList(automatic: automaticContextualList, flip: manualListFlip, now: now)

        refreshSevenDayProgress(anchoredOn: anchorDay, context: context)
        // On a future day the streaks stay as of today: days to come aren't misses yet.
        let streakDay = min(anchorDay, HomeModel.normalizedDay(now, calendar: calendar))
        let streaks = refreshStreaks(through: streakDay, context: context)
        refreshNeverMissTwiceState(anchorDay: streakDay, anchorStreaks: streaks, context: context)
    }

    /// The ring's seven days, ending on the selected day, drawn like calendar days: past days and
    /// today with one segment per list in use (the streak's own day looks, fetched for these days
    /// only), later days plain with a dot when something is planned.
    private func refreshSevenDayProgress(
        anchoredOn endDay: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let math = DayMath(calendar: calendar)
        let endKey = HomeModel.dayKey(for: endDay, calendar: calendar)
        let startKey = math.adding(days: -(progressWindowDays - 1), to: endKey)
        let todayKey = HomeModel.dayKey(for: now, calendar: calendar)

        let basis = dayCircleBasis(context: context)
        let past = dayLooks(from: startKey, through: min(endKey, todayKey), context: context)
        let planned = plannedDayKeys(from: max(startKey, math.adding(days: 1, to: todayKey)), through: endKey, context: context)

        sevenDayProgress = (0..<progressWindowDays).compactMap { offset in
            let key = math.adding(days: offset, to: startKey)
            guard let date = HomeModel.date(fromDayKey: key, calendar: calendar) else { return nil }
            let isFuture = key > todayKey
            return HomeModel.DayProgress(
                date: HomeModel.normalizedDay(date, calendar: calendar),
                dayKey: key,
                segments: isFuture ? [] : CalendarRules.segments(
                    on: key, lists: basis.lists, firstEntryDayKey: basis.firstEntryDayKey, looks: past.looks
                ),
                hasBump: !isFuture && past.bumpedDays.contains(key),
                isFuture: isFuture,
                isPlanned: planned.contains(key)
            )
        }
        // The ring's days up to today (later days show no ↻), so the count matches the marks on show.
        bumpsInSevenDays = bumpCount(from: startKey, through: min(endKey, todayKey), context: context)
    }

    private struct ListStreaks {
        let morning: HomeModel.StreakState
        let day: HomeModel.StreakState
        let evening: HomeModel.StreakState
    }

    private func streaks(through day: Date, context: ModelContext) -> ListStreaks {
        ListStreaks(
            morning: streakState(for: .morning, through: day, context: context),
            day: streakState(for: .day, through: day, context: context),
            evening: streakState(for: .evening, through: day, context: context)
        )
    }

    private func refreshStreaks(through endDay: Date, context: ModelContext) -> ListStreaks {
        let state = streaks(through: endDay, context: context)
        morningStreakCount = state.morning.count
        isMorningStreakFrozen = state.morning.isFrozen
        dailyTaskStreakCount = state.day.count
        isDailyTaskStreakFrozen = state.day.isFrozen
        eveningStreakCount = state.evening.count
        isEveningStreakFrozen = state.evening.isFrozen
        return state
    }

    /// The banner is about today, whichever day is on screen.
    private func refreshNeverMissTwiceState(anchorDay: Date, anchorStreaks: ListStreaks, context: ModelContext) {
        let today = HomeModel.normalizedDay(now)
        let todayStreaks = anchorDay == today ? anchorStreaks : streaks(through: today, context: context)
        isNeverMissTwiceMorningRisk = todayStreaks.morning.isFrozen
        isNeverMissTwiceDailyRisk = todayStreaks.day.isFrozen
    }
}
