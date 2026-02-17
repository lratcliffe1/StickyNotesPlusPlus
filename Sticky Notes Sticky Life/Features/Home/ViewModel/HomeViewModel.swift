import Combine
import Foundation
import SwiftData

@MainActor
final class HomeViewModel: ObservableObject {
    enum MorningModeSelection {
        case cutoff
        case sinceWakeUp
    }

    // UI state
    @Published var selectedDay: Date = HomeModel.normalizedDay(Date())
    @Published var morningEntries: [MorningRoutineEntry] = []
    @Published var dailyTasks: [DailyTask] = []
    @Published var dayRecord: DayRecord?
    @Published var newTaskTitle: String = ""

    @Published private(set) var contextualList: HomeModel.ContextualList = .daily
    @Published private(set) var isReadOnly: Bool = false
    @Published private(set) var morningStreakCount: Int = 0
    @Published private(set) var dailyTaskStreakCount: Int = 0
    @Published private(set) var sevenDayProgress: [HomeModel.DayProgress] = []
    @Published private(set) var isNeverMissTwiceMorningRisk: Bool = false
    @Published private(set) var isNeverMissTwiceDailyRisk: Bool = false

    // Defaults from the implementation spec.
    var morningModeSelection: MorningModeSelection = .cutoff
    var morningCutoffTime: DateComponents = DateComponents(hour: 9, minute: 0)
    var wakeUpTime: DateComponents = DateComponents(hour: 7, minute: 0)
    var morningWindowDurationMinutes: Int = 90
    var nowOverride: Date?

    private var now: Date {
        nowOverride ?? Date()
    }

    // MARK: - Public API

    func refresh(context: ModelContext) {
        let calendar = Calendar.current
        let day = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        selectedDay = day

        if HomeModel.isToday(day, now: now, calendar: calendar) {
            ensureMorningEntriesExist(for: day, context: context)
        }

        morningEntries = fetchMorningEntries(for: day, context: context)
        dailyTasks = fetchDailyTasks(for: day, context: context)
        upsertDayRecord(for: day, context: context)
        dayRecord = fetchDayRecord(for: day, context: context)

        recalculateDerivedState(context: context)
    }

    func goToToday(context: ModelContext) {
        selectedDay = HomeModel.normalizedDay(now)
        refresh(context: context)
    }

    func toggleMorningEntry(_ entry: MorningRoutineEntry, context: ModelContext) {
        guard canEdit(day: entry.date) else { return }

        entry.isCompleted.toggle()
        entry.completedAt = entry.isCompleted ? now : nil
        save(context: context)
        refresh(context: context)
    }

    func toggleDailyTask(_ task: DailyTask, context: ModelContext) {
        guard canEdit(day: task.date) else { return }

        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? now : nil
        save(context: context)
        refresh(context: context)
    }

    func addDailyTask(context: ModelContext) {
        guard canEdit(day: selectedDay) else { return }

        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let task = DailyTask(date: selectedDay, title: title)
        context.insert(task)
        newTaskTitle = ""
        save(context: context)
        refresh(context: context)
    }

    func bumpTaskToTomorrow(_ task: DailyTask, context: ModelContext) {
        guard canEdit(day: task.date) else { return }
        guard task.isBumpable, !task.isCompleted else { return }

        let cal = Calendar.current
        let taskDay = HomeModel.normalizedDay(task.date, calendar: cal)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: taskDay) ?? taskDay

        let bumpedTask = DailyTask(
            date: HomeModel.normalizedDay(tomorrow, calendar: cal),
            title: task.title,
            isCompleted: false,
            completedAt: nil,
            bumpCount: task.bumpCount + 1,
            isBumpable: task.isBumpable
        )

        context.insert(bumpedTask)
        save(context: context)
        refresh(context: context)
    }

    // MARK: - Computed for UI

    var isMorningMode: Bool {
        contextualList == .morning
    }

    var morningProgress: Double {
        HomeModel.morningCompletion(entries: morningEntries).value
    }

    var isMorningProgressImplicit: Bool {
        HomeModel.morningCompletion(entries: morningEntries).isImplicitlyComplete
    }

    var dailyProgress: Double {
        HomeModel.dailyCompletion(tasks: dailyTasks).value
    }

    var isDailyProgressImplicit: Bool {
        HomeModel.dailyCompletion(tasks: dailyTasks).isImplicitlyComplete
    }

    var neverMissTwiceBannerText: String? {
        guard isNeverMissTwiceMorningRisk || isNeverMissTwiceDailyRisk else { return nil }

        if isMorningMode, isNeverMissTwiceMorningRisk {
            return "Yesterday slipped. Finish your morning list today."
        }
        if !isMorningMode, isNeverMissTwiceDailyRisk {
            return "Yesterday slipped. Finish today’s tasks to avoid missing twice."
        }
        if isNeverMissTwiceMorningRisk {
            return "Morning consistency is at risk today."
        }
        return "Daily consistency is at risk today."
    }

    // MARK: - Derived state

    private func recalculateDerivedState(context: ModelContext) {
        isReadOnly = HomeModel.isPastDay(selectedDay, now: now)

        if HomeModel.shouldShowMorningList(
            for: selectedDay,
            morningEntries: morningEntries,
            mode: morningMode,
            now: now
        ) {
            contextualList = .morning
        } else {
            contextualList = .daily
        }

        refreshSevenDayProgress(context: context)
        refreshMorningStreak(context: context)
        refreshDailyTaskStreak(context: context)
        refreshNeverMissTwiceState(context: context)
    }

    private func refreshSevenDayProgress(context: ModelContext) {
        let calendar = Calendar.current
        let endDay = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        guard let startRaw = calendar.date(byAdding: .day, value: -6, to: endDay) else {
            sevenDayProgress = []
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let weeklyMorning = fetchMorningEntries(from: startDay, through: endDay, context: context)
        let weeklyDaily = fetchDailyTasks(from: startDay, through: endDay, context: context)

        let morningByDay = Dictionary(grouping: weeklyMorning) {
            HomeModel.normalizedDay($0.date, calendar: calendar)
        }

        let dailyByDay = Dictionary(grouping: weeklyDaily) {
            HomeModel.normalizedDay($0.date, calendar: calendar)
        }

        sevenDayProgress = (0..<7).compactMap { offset in
            guard let dayRaw = calendar.date(byAdding: .day, value: offset, to: startDay) else { return nil }
            let day = HomeModel.normalizedDay(dayRaw, calendar: calendar)

            let morningState = HomeModel.morningCompletion(entries: morningByDay[day] ?? [])
            let dailyState = HomeModel.dailyCompletion(tasks: dailyByDay[day] ?? [])

            return HomeModel.DayProgress(date: day, morning: morningState, daily: dailyState)
        }
    }

    private func refreshMorningStreak(context: ModelContext) {
        let calendar = Calendar.current
        let endDay = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        guard let startRaw = calendar.date(byAdding: .day, value: -365, to: endDay) else {
            morningStreakCount = 0
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let entries = fetchMorningEntries(from: startDay, through: endDay, context: context)
        let entriesByDay = Dictionary(grouping: entries) {
            HomeModel.normalizedDay($0.date, calendar: calendar)
        }

        morningStreakCount = HomeModel.morningStreak(
            through: endDay,
            entriesByDay: entriesByDay,
            mode: morningMode,
            calendar: calendar
        )
    }

    private func refreshDailyTaskStreak(context: ModelContext) {
        let calendar = Calendar.current
        let endDay = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        guard let startRaw = calendar.date(byAdding: .day, value: -365, to: endDay) else {
            dailyTaskStreakCount = 0
            return
        }

        let startDay = HomeModel.normalizedDay(startRaw, calendar: calendar)
        let tasks = fetchDailyTasks(from: startDay, through: endDay, context: context)
        let tasksByDay = Dictionary(grouping: tasks) {
            HomeModel.normalizedDay($0.date, calendar: calendar)
        }

        dailyTaskStreakCount = HomeModel.dailyStreak(
            through: endDay,
            tasksByDay: tasksByDay,
            calendar: calendar
        )
    }

    private func refreshNeverMissTwiceState(context: ModelContext) {
        let calendar = Calendar.current
        let today = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        guard let yesterdayRaw = calendar.date(byAdding: .day, value: -1, to: today) else {
            isNeverMissTwiceMorningRisk = false
            isNeverMissTwiceDailyRisk = false
            return
        }

        let yesterday = HomeModel.normalizedDay(yesterdayRaw, calendar: calendar)

        let yesterdayMorningCompletion = HomeModel.morningCompletion(
            entries: fetchMorningEntries(for: yesterday, context: context)
        ).value

        let yesterdayDailyCompletion = HomeModel.dailyCompletion(
            tasks: fetchDailyTasks(for: yesterday, context: context)
        ).value

        let todayMorningCompletion = HomeModel.morningCompletion(entries: morningEntries).value
        let todayDailyCompletion = HomeModel.dailyCompletion(tasks: dailyTasks).value

        isNeverMissTwiceMorningRisk = yesterdayMorningCompletion < 1.0 && todayMorningCompletion < 1.0
        isNeverMissTwiceDailyRisk = yesterdayDailyCompletion < 1.0 && todayDailyCompletion < 1.0
    }

    private func canEdit(day: Date) -> Bool {
        !HomeModel.isPastDay(day, now: now)
    }

    var morningMode: HomeModel.MorningMode {
        switch morningModeSelection {
        case .cutoff:
            return .cutoff(time: morningCutoffTime)
        case .sinceWakeUp:
            return .sinceWakeUp(
                wakeUpTime: wakeUpTime,
                durationMinutes: morningWindowDurationMinutes
            )
        }
    }

#if DEBUG
    func applyPreviewDerivedState(
        contextualList: HomeModel.ContextualList,
        isReadOnly: Bool,
        morningStreakCount: Int,
        dailyTaskStreakCount: Int,
        sevenDayProgress: [HomeModel.DayProgress],
        isNeverMissTwiceMorningRisk: Bool,
        isNeverMissTwiceDailyRisk: Bool
    ) {
        self.contextualList = contextualList
        self.isReadOnly = isReadOnly
        self.morningStreakCount = morningStreakCount
        self.dailyTaskStreakCount = dailyTaskStreakCount
        self.sevenDayProgress = sevenDayProgress
        self.isNeverMissTwiceMorningRisk = isNeverMissTwiceMorningRisk
        self.isNeverMissTwiceDailyRisk = isNeverMissTwiceDailyRisk
    }
#endif
}
