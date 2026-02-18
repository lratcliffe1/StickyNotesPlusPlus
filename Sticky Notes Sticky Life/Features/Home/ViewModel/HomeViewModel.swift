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
    private let defaults: UserDefaults
    private var manualContextualListOverride: HomeModel.ContextualList?
    private let streakLookbackDays = 365
    private let progressWindowDays = 7

    private var now: Date {
        nowOverride ?? Date()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadMorningSettings()
    }

    // MARK: - Public API

    func refresh(context: ModelContext) {
        loadMorningSettings()

        let calendar = Calendar.current
        let day = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        selectedDay = day

        if HomeModel.isToday(day, now: now, calendar: calendar) {
            reconcileMorningEntries(for: day, context: context)
        }

        morningEntries = fetchMorningEntries(for: day, context: context)
        dailyTasks = fetchDailyTasks(for: day, context: context)
        upsertDayRecord(for: day, context: context)

        recalculateDerivedState(context: context)
    }

    func setSelectedDay(
        _ day: Date,
        context: ModelContext,
        preferredList: HomeModel.ContextualList? = nil
    ) {
        selectedDay = HomeModel.normalizedDay(day)
        manualContextualListOverride = preferredList
        refresh(context: context)
    }

    func goToToday(context: ModelContext) {
        selectedDay = HomeModel.normalizedDay(now)
        manualContextualListOverride = nil
        refresh(context: context)
    }

    func flipStickyNoteList() {
        let nextList: HomeModel.ContextualList = isMorningMode ? .daily : .morning
        manualContextualListOverride = nextList
        contextualList = nextList
    }

    func toggleMorningEntry(_ entry: MorningRoutineEntry, context: ModelContext) {
        guard canComplete(day: entry.date) else { return }

        entry.isCompleted.toggle()
        entry.completedAt = entry.isCompleted ? now : nil
        save(context: context)
        refresh(context: context)

        if HomeModel.isToday(selectedDay, now: now),
           HomeModel.morningCompletion(entries: morningEntries).value >= 1.0 {
            manualContextualListOverride = nil
            contextualList = .daily
        }
    }

    func toggleDailyTask(_ task: DailyTask, context: ModelContext) {
        guard canComplete(day: task.date) else { return }

        if task.isCompleted, let bumpedTaskID = task.bumpedTaskID {
            task.isCompleted = false
            task.completedAt = nil
            task.bumpedTaskID = nil

            if let bumpedTask = fetchDailyTask(id: bumpedTaskID, context: context) {
                context.delete(bumpedTask)
            }

            save(context: context)
            refresh(context: context)
            return
        }

        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? now : nil
        save(context: context)
        refresh(context: context)
    }

    func addDailyTask(context: ModelContext) {
        guard canManage(day: selectedDay) else { return }

        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let task = DailyTask(date: selectedDay, title: title)
        context.insert(task)
        newTaskTitle = ""
        save(context: context)
        refresh(context: context)
    }

    func bumpTaskToTomorrow(
        _ task: DailyTask,
        bumpedTitle: String,
        context: ModelContext
    ) {
        guard canManage(day: task.date) else { return }
        guard task.isBumpable, !task.isCompleted else { return }
        guard task.bumpedTaskID == nil else { return }

        let bumpedTitle = bumpedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bumpedTitle.isEmpty else { return }

        let cal = Calendar.current
        let taskDay = HomeModel.normalizedDay(task.date, calendar: cal)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: taskDay) ?? taskDay

        let bumpedTask = DailyTask(
            date: HomeModel.normalizedDay(tomorrow, calendar: cal),
            title: bumpedTitle,
            isCompleted: false,
            completedAt: nil,
            bumpCount: task.bumpCount + 1,
            isBumpable: task.isBumpable
        )

        context.insert(bumpedTask)
        task.isCompleted = true
        task.completedAt = now
        task.bumpedTaskID = bumpedTask.id
        save(context: context)
        refresh(context: context)
    }

    // MARK: - Computed for UI

    var isMorningMode: Bool {
        contextualList == .morning
    }

    var canCompleteSelectedDay: Bool {
        HomeModel.isToday(selectedDay, now: now)
    }

    var canAddNewTask: Bool {
        !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedDayTitle: String {
        selectedDay.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var selectedDayRelativeLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDay) {
            return "Today"
        }
        if calendar.isDateInTomorrow(selectedDay) {
            return "Tomorrow"
        }
        if calendar.isDateInYesterday(selectedDay) {
            return "Yesterday"
        }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    var morningProgress: Double {
        morningCompletionState.value
    }

    var isMorningProgressImplicit: Bool {
        morningCompletionState.isImplicitlyComplete
    }

    var dailyProgress: Double {
        dailyCompletionState.value
    }

    var isDailyProgressImplicit: Bool {
        dailyCompletionState.isImplicitlyComplete
    }

    var activeListProgressPercent: Int {
        Int((activeListProgress * 100).rounded())
    }

    var activeListProgress: Double {
        isMorningMode ? morningProgress : dailyProgress
    }

    var activeListProgressIsImplicit: Bool {
        isMorningMode ? isMorningProgressImplicit : isDailyProgressImplicit
    }

    var activeListTitle: String {
        isMorningMode ? "Morning Routine" : "Daily Tasks"
    }

    var sortedDailyTasks: [DailyTask] {
        dailyTasks.sorted { lhs, rhs in
            if lhs.isBumpable != rhs.isBumpable {
                return lhs.isBumpable == false
            }

            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func updateNewTaskTitle(_ value: String) {
        newTaskTitle = value
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
            HomeModel.normalizedDay($0.date, calendar: calendar)
        }

        let dailyByDay = Dictionary(grouping: weeklyDaily) {
            HomeModel.normalizedDay($0.date, calendar: calendar)
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

    private func refreshDailyTaskStreak(
        through endDay: Date,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        guard let startRaw = calendar.date(byAdding: .day, value: -streakLookbackDays, to: endDay) else {
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
        let today = HomeModel.normalizedDay(now, calendar: calendar)
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

        let todayMorningEntries: [MorningRoutineEntry]
        let todayDailyTasks: [DailyTask]

        if HomeModel.isToday(selectedDay, now: now, calendar: calendar) {
            todayMorningEntries = morningEntries
            todayDailyTasks = dailyTasks
        } else {
            todayMorningEntries = fetchMorningEntries(for: today, context: context)
            todayDailyTasks = fetchDailyTasks(for: today, context: context)
        }

        let todayMorningCompletion = HomeModel.morningCompletion(entries: todayMorningEntries).value
        let todayDailyCompletion = HomeModel.dailyCompletion(tasks: todayDailyTasks).value

        isNeverMissTwiceMorningRisk = yesterdayMorningCompletion < 1.0 && todayMorningCompletion < 1.0
        isNeverMissTwiceDailyRisk = yesterdayDailyCompletion < 1.0 && todayDailyCompletion < 1.0
    }

    private func canComplete(day: Date) -> Bool {
        HomeModel.isToday(day, now: now)
    }

    private func canManage(day: Date) -> Bool {
        !HomeModel.isPastDay(day, now: now)
    }

    private func loadMorningSettings() {
        let modeRaw = defaults.string(forKey: AppSettings.morningModeKey) ?? AppSettings.defaultMorningMode.rawValue
        morningModeSelection = modeRaw == AppSettings.MorningMode.sinceWakeUp.rawValue ? .sinceWakeUp : .cutoff

        let cutoffMinutes = defaults.object(forKey: AppSettings.morningCutoffMinutesKey) as? Int ?? AppSettings.defaultMorningCutoffMinutes
        let wakeMinutes = defaults.object(forKey: AppSettings.wakeUpMinutesKey) as? Int ?? AppSettings.defaultWakeUpMinutes
        let duration = defaults.object(forKey: AppSettings.morningWindowDurationMinutesKey) as? Int ?? AppSettings.defaultMorningWindowDurationMinutes

        morningCutoffTime = AppSettings.dateComponents(fromMinutes: cutoffMinutes)
        wakeUpTime = AppSettings.dateComponents(fromMinutes: wakeMinutes)
        morningWindowDurationMinutes = min(240, max(15, duration))
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

    private var morningCompletionState: HomeModel.CompletionState {
        HomeModel.morningCompletion(entries: morningEntries)
    }

    private var dailyCompletionState: HomeModel.CompletionState {
        HomeModel.dailyCompletion(tasks: dailyTasks)
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
