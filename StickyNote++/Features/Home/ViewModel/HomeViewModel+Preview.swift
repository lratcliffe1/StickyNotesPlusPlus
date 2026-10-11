#if DEBUG
import Foundation

/// Deterministic preview scenarios for HomeViewModel states in SwiftUI previews.
extension HomeViewModel {
    enum PreviewScenario {
        case morningActive
        case dailyAfterMorningWindow
        case dailyAfterMorningCompleted
        case morningStreakFrozen
        case dailyStreakFrozen
        case streakReset
    }

    static func preview(_ scenario: PreviewScenario) -> HomeViewModel {
        let vm = HomeViewModel()
        let calendar = Calendar.current
        let baseDay = HomeModel.normalizedDay(Date(), calendar: calendar)
        let scenarioNow: Date

        switch scenario {
        case .morningActive:
            scenarioNow = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: baseDay) ?? baseDay
        case .dailyAfterMorningWindow:
            scenarioNow = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: baseDay) ?? baseDay
        case .dailyAfterMorningCompleted:
            scenarioNow = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: baseDay) ?? baseDay
        case .morningStreakFrozen, .dailyStreakFrozen, .streakReset:
            scenarioNow = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: baseDay) ?? baseDay
        }
        let today = HomeModel.normalizedDay(scenarioNow, calendar: calendar)

        vm.selectedDay = today
        vm.nowOverride = scenarioNow
        let todayKey = HomeModel.dayKey(for: today, calendar: calendar)
        func task(_ title: String, bumps: Int) -> Occurrence {
            Occurrence(list: .day, dayKey: todayKey, title: title, bumpCount: bumps)
        }
        func routine(_ titles: [String], doneAt: [(Int, Int)?]) -> [Occurrence] {
            titles.enumerated().map { index, title in
                let done = doneAt[index].flatMap { calendar.date(bySettingHour: $0.0, minute: $0.1, second: 0, of: today) }
                return Occurrence(
                    itemID: UUID(),
                    list: .morning,
                    dayKey: todayKey,
                    title: title,
                    sortOrder: index,
                    state: done == nil ? .open : .done,
                    completedAt: done,
                    bumpLimit: .unlimited,
                    scheduledDayKey: todayKey,
                    periodEndDayKey: todayKey
                )
            }
        }
        let titles = ["Drink water", "Stretch for 5 minutes", "Read 10 pages"]

        vm.dailyTasks = [
            task("Plan top priority", bumps: 0),
            task("10 minute walk", bumps: 1),
        ]

        switch scenario {
        case .morningActive:
            vm.morningEntries = routine(titles, doneAt: [nil, nil, nil])
        case .dailyAfterMorningWindow:
            vm.morningEntries = routine(titles, doneAt: [(7, 5), nil, nil])
        case .dailyAfterMorningCompleted:
            vm.morningEntries = routine(titles, doneAt: [(6, 55), (7, 8), (7, 18)])
        case .morningStreakFrozen, .dailyStreakFrozen, .streakReset:
            vm.morningEntries = routine(titles, doneAt: [(7, 4), nil, nil])
        }

        let contextualList = HomeModel.automaticList(
            for: today,
            now: scenarioNow,
            rules: .legacy,
            morning: ListRules.completion(vm.morningEntries),
            eveningIsEmpty: true,
            calendar: calendar
        )

        let streakState: (morningCount: Int, dailyCount: Int, morningFrozen: Bool, dailyFrozen: Bool)
        switch scenario {
        case .morningActive:
            streakState = (morningCount: 4, dailyCount: 2, morningFrozen: false, dailyFrozen: false)
        case .dailyAfterMorningWindow:
            streakState = (morningCount: 3, dailyCount: 5, morningFrozen: false, dailyFrozen: false)
        case .dailyAfterMorningCompleted:
            streakState = (morningCount: 6, dailyCount: 4, morningFrozen: false, dailyFrozen: false)
        case .morningStreakFrozen:
            streakState = (morningCount: 6, dailyCount: 4, morningFrozen: true, dailyFrozen: false)
        case .dailyStreakFrozen:
            streakState = (morningCount: 5, dailyCount: 7, morningFrozen: false, dailyFrozen: true)
        case .streakReset:
            streakState = (morningCount: 0, dailyCount: 0, morningFrozen: false, dailyFrozen: false)
        }

        vm.applyPreviewDerivedState(
            contextualList: contextualList,
            isReadOnly: HomeModel.isPastDay(today, now: scenarioNow, calendar: calendar),
            morningStreakCount: streakState.morningCount,
            dailyTaskStreakCount: streakState.dailyCount,
            isMorningStreakFrozen: streakState.morningFrozen,
            isDailyTaskStreakFrozen: streakState.dailyFrozen,
            sevenDayProgress: previewWeek(endingOn: today, calendar: calendar),
            isNeverMissTwiceMorningRisk: false,
            isNeverMissTwiceDailyRisk: false
        )

        return vm
    }

    private static func previewWeek(endingOn endDay: Date, calendar: Calendar) -> [HomeModel.DayProgress] {
        let values: [(Double, Double)] = [
            (0.30, 0.40), (0.55, 0.65), (1.0, 0.20), (0.90, 1.0), (0.60, 0.75), (0.85, 0.90), (0.50, 0.60)
        ]

        return values.enumerated().compactMap { index, pair in
            let offset = index - 6
            guard let dayRaw = calendar.date(byAdding: .day, value: offset, to: endDay) else { return nil }
            let day = HomeModel.normalizedDay(dayRaw, calendar: calendar)
            return HomeModel.DayProgress(
                date: day,
                morning: .init(value: pair.0, isNeutral: false),
                daily: .init(value: pair.1, isNeutral: false)
            )
        }
    }
}
#endif
