import Foundation
import SwiftData

/// Derived UI state for `HomeViewModel`: which list shows, the 7-day ring, the streaks and the
/// never-miss-twice risk. The rules themselves are in `ListRules` (tested in `Shared/`).
extension HomeViewModel {
    func recalculateDerivedState(context: ModelContext) {
        let calendar = Calendar.current
        isReadOnly = HomeModel.isPastDay(selectedDay, now: now, calendar: calendar)
        let anchorDay = HomeModel.normalizedDay(selectedDay, calendar: calendar)

        let autoContextualList: HomeModel.ContextualList
        if HomeModel.shouldShowMorningList(
            for: selectedDay,
            morningCompletion: morningCompletionState,
            mode: morningMode,
            now: now
        ) {
            autoContextualList = .morning
        } else {
            autoContextualList = .daily
        }

        contextualList = manualContextualListOverride ?? autoContextualList

        refreshSevenDayProgress(anchoredOn: anchorDay, context: context)
        let streaks = refreshStreaks(through: anchorDay, context: context)
        refreshNeverMissTwiceState(anchorDay: anchorDay, anchorStreaks: streaks, context: context)
    }

    private func refreshSevenDayProgress(
        anchoredOn endDay: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        guard let startRaw = calendar.date(byAdding: .day, value: -(progressWindowDays - 1), to: endDay) else {
            sevenDayProgress = []
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let startKey = HomeModel.dayKey(for: startDay, calendar: calendar)
        let endKey = HomeModel.dayKey(for: endDay, calendar: calendar)
        let morningByDay = Dictionary(
            grouping: fetchOccurrences(from: startKey, through: endKey, list: .morning, context: context),
            by: \.dayKey
        )
        let dailyByDay = Dictionary(
            grouping: fetchOccurrences(from: startKey, through: endKey, list: .day, context: context),
            by: \.dayKey
        )

        sevenDayProgress = (0..<progressWindowDays).compactMap { offset in
            guard let dayRaw = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            let day = HomeModel.normalizedDay(dayRaw, calendar: calendar)
            let key = HomeModel.dayKey(for: day, calendar: calendar)
            return HomeModel.DayProgress(
                date: day,
                morning: ListRules.completion(morningByDay[key] ?? []),
                daily: ListRules.completion(dailyByDay[key] ?? [])
            )
        }
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
