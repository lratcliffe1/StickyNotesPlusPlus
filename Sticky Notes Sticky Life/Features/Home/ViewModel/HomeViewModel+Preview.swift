#if DEBUG
import Foundation

extension HomeViewModel {
    enum PreviewScenario {
        case morningActive
        case dailyAfterMorningWindow
        case dailyAfterMorningCompleted
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
        }
        let today = HomeModel.normalizedDay(scenarioNow, calendar: calendar)

        vm.selectedDay = today
        vm.nowOverride = scenarioNow
        vm.dailyTasks = [
            DailyTask(date: today, title: "Plan top priority", isCompleted: false, completedAt: nil, bumpCount: 0, isBumpable: true),
            DailyTask(date: today, title: "10 minute walk", isCompleted: false, completedAt: nil, bumpCount: 1, isBumpable: true)
        ]

        switch scenario {
        case .morningActive:
            vm.morningEntries = [
                MorningRoutineEntry(date: today, titleSnapshot: "Drink water", targetTimeSnapshot: DateComponents(hour: 7, minute: 0), isCompleted: false, completedAt: nil),
                MorningRoutineEntry(date: today, titleSnapshot: "Stretch for 5 minutes", targetTimeSnapshot: DateComponents(hour: 7, minute: 10), isCompleted: false, completedAt: nil),
                MorningRoutineEntry(date: today, titleSnapshot: "Read 10 pages", targetTimeSnapshot: DateComponents(hour: 7, minute: 20), isCompleted: false, completedAt: nil)
            ]
        case .dailyAfterMorningWindow:
            vm.morningEntries = [
                MorningRoutineEntry(date: today, titleSnapshot: "Drink water", targetTimeSnapshot: DateComponents(hour: 7, minute: 0), isCompleted: true, completedAt: calendar.date(bySettingHour: 7, minute: 5, second: 0, of: today)),
                MorningRoutineEntry(date: today, titleSnapshot: "Stretch for 5 minutes", targetTimeSnapshot: DateComponents(hour: 7, minute: 10), isCompleted: false, completedAt: nil),
                MorningRoutineEntry(date: today, titleSnapshot: "Read 10 pages", targetTimeSnapshot: DateComponents(hour: 7, minute: 20), isCompleted: false, completedAt: nil)
            ]
        case .dailyAfterMorningCompleted:
            vm.morningEntries = [
                MorningRoutineEntry(date: today, titleSnapshot: "Drink water", targetTimeSnapshot: DateComponents(hour: 7, minute: 0), isCompleted: true, completedAt: calendar.date(bySettingHour: 6, minute: 55, second: 0, of: today)),
                MorningRoutineEntry(date: today, titleSnapshot: "Stretch for 5 minutes", targetTimeSnapshot: DateComponents(hour: 7, minute: 10), isCompleted: true, completedAt: calendar.date(bySettingHour: 7, minute: 8, second: 0, of: today)),
                MorningRoutineEntry(date: today, titleSnapshot: "Read 10 pages", targetTimeSnapshot: DateComponents(hour: 7, minute: 20), isCompleted: true, completedAt: calendar.date(bySettingHour: 7, minute: 18, second: 0, of: today))
            ]
        }

        let contextualList: HomeModel.ContextualList = HomeModel.shouldShowMorningList(
            for: today,
            morningEntries: vm.morningEntries,
            mode: vm.morningMode,
            now: scenarioNow,
            calendar: calendar
        ) ? .morning : .daily

        vm.applyPreviewDerivedState(
            contextualList: contextualList,
            isReadOnly: HomeModel.isPastDay(today, now: scenarioNow, calendar: calendar),
            morningStreakCount: 0,
            dailyTaskStreakCount: 0,
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
                morning: .init(value: pair.0, isImplicitlyComplete: false),
                daily: .init(value: pair.1, isImplicitlyComplete: false)
            )
        }
    }
}
#endif
