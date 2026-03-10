import Foundation
import SwiftData

extension HomeViewModel {
    func recalculateDerivedState(context: ModelContext) {
        let calendar = Calendar.current
        isReadOnly = HomeModel.isPastDay(selectedDay, now: now, calendar: calendar)
        let anchorDay = HomeModel.normalizedDay(selectedDay, calendar: calendar)

        let autoContextualList: HomeModel.ContextualList
        if HomeModel.shouldShowMorningList(
            for: selectedDay,
            morningEntries: morningEntries,
            mode: morningMode,
            now: now
        ) {
            autoContextualList = .morning
        } else {
            autoContextualList = .daily
        }

        contextualList = manualContextualListOverride ?? autoContextualList

        refreshSevenDayProgress(anchoredOn: anchorDay, context: context)
        refreshMorningStreak(through: anchorDay, context: context)
        refreshDailyTaskStreak(through: anchorDay, context: context)
        refreshNeverMissTwiceState(context: context)
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
        let weeklyMorning = fetchMorningEntries(from: startDay, through: endDay, context: context)
        let weeklyDaily = fetchDailyTasks(from: startDay, through: endDay, context: context)

        let morningByDay = Dictionary(grouping: weeklyMorning) {
            dayFromStored(dayKey: $0.dayKey, fallbackDate: $0.date, calendar: calendar)
        }
        let dailyByDay = Dictionary(grouping: weeklyDaily) {
            dayFromStored(dayKey: $0.dayKey, fallbackDate: $0.date, calendar: calendar)
        }

        sevenDayProgress = (0..<progressWindowDays).compactMap { offset in
            guard let dayRaw = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            let day = HomeModel.normalizedDay(dayRaw, calendar: calendar)

            let morningState = HomeModel.morningCompletion(entries: morningByDay[day] ?? [])
            let dailyState = HomeModel.dailyCompletion(tasks: dailyByDay[day] ?? [])
            return HomeModel.DayProgress(date: day, morning: morningState, daily: dailyState)
        }
    }

    private func refreshMorningStreak(
        through endDay: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        guard let startRaw = calendar.date(byAdding: .day, value: -streakLookbackDays, to: endDay) else {
            morningStreakCount = 0
            isMorningStreakFrozen = false
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let entries = fetchMorningEntries(from: startDay, through: endDay, context: context)
        let entriesByDay = Dictionary(grouping: entries) {
            dayFromStored(dayKey: $0.dayKey, fallbackDate: $0.date, calendar: calendar)
        }

        let streakState = HomeModel.morningStreakState(
            through: endDay,
            entriesByDay: entriesByDay,
            mode: morningMode,
            calendar: calendar
        )
        morningStreakCount = streakState.count
        isMorningStreakFrozen = streakState.isFrozen
    }

    private func refreshDailyTaskStreak(
        through endDay: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        guard let startRaw = calendar.date(byAdding: .day, value: -streakLookbackDays, to: endDay) else {
            dailyTaskStreakCount = 0
            isDailyTaskStreakFrozen = false
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let tasks = fetchDailyTasks(from: startDay, through: endDay, context: context)
        let tasksByDay = Dictionary(grouping: tasks) {
            dayFromStored(dayKey: $0.dayKey, fallbackDate: $0.date, calendar: calendar)
        }

        let streakState = HomeModel.dailyStreakState(
            through: endDay,
            tasksByDay: tasksByDay,
            calendar: calendar
        )
        dailyTaskStreakCount = streakState.count
        isDailyTaskStreakFrozen = streakState.isFrozen
    }

    private func refreshNeverMissTwiceState(context: ModelContext) {
        let calendar = Calendar.current
        let today = HomeModel.normalizedDay(now, calendar: calendar)

        guard let startRaw = calendar.date(byAdding: .day, value: -streakLookbackDays, to: today) else {
            isNeverMissTwiceMorningRisk = false
            isNeverMissTwiceDailyRisk = false
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let morningEntries = fetchMorningEntries(from: startDay, through: today, context: context)
        let morningByDay = Dictionary(grouping: morningEntries) {
            dayFromStored(dayKey: $0.dayKey, fallbackDate: $0.date, calendar: calendar)
        }

        let dailyTasks = fetchDailyTasks(from: startDay, through: today, context: context)
        let dailyByDay = Dictionary(grouping: dailyTasks) {
            dayFromStored(dayKey: $0.dayKey, fallbackDate: $0.date, calendar: calendar)
        }

        let morningStreakStateToday = HomeModel.morningStreakState(
            through: today,
            entriesByDay: morningByDay,
            mode: morningMode,
            calendar: calendar
        )
        let dailyStreakStateToday = HomeModel.dailyStreakState(
            through: today,
            tasksByDay: dailyByDay,
            calendar: calendar
        )

        isNeverMissTwiceMorningRisk = morningStreakStateToday.isFrozen
        isNeverMissTwiceDailyRisk = dailyStreakStateToday.isFrozen
    }
}
