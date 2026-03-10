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
    @Published private(set) var isMorningStreakFrozen: Bool = false
    @Published private(set) var isDailyTaskStreakFrozen: Bool = false
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

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? SharedPersistence.sharedDefaults
        loadMorningSettings()
    }

    // MARK: - Public API

    func refresh(context: ModelContext) {
        loadMorningSettings()
        migrateLegacyDayKeysIfNeeded(context: context)

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
        guard canComplete(day: selectedDay) else { return }

        entry.isCompleted.toggle()
        entry.completedAt = entry.isCompleted ? now : nil
        save(context: context)
        refresh(context: context)
        TaskWidgetReloader.reloadTopTasksWidget()

        if HomeModel.isToday(selectedDay, now: now),
           HomeModel.morningCompletion(entries: morningEntries).value >= 1.0 {
            manualContextualListOverride = nil
            contextualList = .daily
        }
    }

    func toggleDailyTask(_ task: DailyTask, context: ModelContext) {
        guard canComplete(day: selectedDay) else { return }

        if task.isCompleted, let bumpedTaskID = task.bumpedTaskID {
            task.isCompleted = false
            task.completedAt = nil
            task.bumpedTaskID = nil

            if let bumpedTask = fetchDailyTask(id: bumpedTaskID, context: context) {
                context.delete(bumpedTask)
            }

            save(context: context)
            refresh(context: context)
            TaskWidgetReloader.reloadTopTasksWidget()
            return
        }

        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? now : nil
        save(context: context)
        refresh(context: context)
        TaskWidgetReloader.reloadTopTasksWidget()
    }

    @discardableResult
    func addDailyTask(context: ModelContext, mustHappenToday: Bool = false) -> Bool {
        guard canManage(day: selectedDay) else { return false }

        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        let task = DailyTask(
            date: selectedDay,
            title: title,
            isBumpable: !mustHappenToday
        )
        context.insert(task)
        newTaskTitle = ""
        save(context: context)
        refresh(context: context)
        TaskWidgetReloader.reloadTopTasksWidget()
        return true
    }

    func bumpTaskToTomorrow(
        _ task: DailyTask,
        bumpedTitle: String,
        context: ModelContext
    ) {
        guard canManage(day: selectedDay) else { return }
        guard task.isBumpable, !task.isCompleted else { return }
        guard task.bumpedTaskID == nil else { return }

        let bumpedTitle = bumpedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bumpedTitle.isEmpty else { return }

        let cal = Calendar.current
        let taskDay = HomeModel.date(fromDayKey: task.dayKey, calendar: cal)
            ?? HomeModel.normalizedDay(task.date, calendar: cal)
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
        TaskWidgetReloader.reloadTopTasksWidget()
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
        dailyTasks
    }

    func updateNewTaskTitle(_ value: String) {
        newTaskTitle = value
    }

    var neverMissTwiceBannerText: String? {
        guard isNeverMissTwiceMorningRisk || isNeverMissTwiceDailyRisk else { return nil }

        if isMorningMode, isNeverMissTwiceMorningRisk {
            return "NEVER MISS TWICE! Finish your morning todos."
        }
        if !isMorningMode, isNeverMissTwiceDailyRisk {
            return "NEVER MISS TWICE! Finish your daily todos."
        }
        if isNeverMissTwiceMorningRisk {
            return "You missed your morning todos twice, resetting tomorrow..."
        }
        return "You missed your daily todos twice, resetting tomorrow..."
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

        // Match "never miss twice" warnings to the exact same freeze semantics as streak counters.
        isNeverMissTwiceMorningRisk = morningStreakStateToday.isFrozen
        isNeverMissTwiceDailyRisk = dailyStreakStateToday.isFrozen
    }

    private func canComplete(day: Date) -> Bool {
        HomeModel.isToday(day, now: now)
    }

    private func canManage(day: Date) -> Bool {
        !HomeModel.isPastDay(day, now: now)
    }

    private func dayFromStored(
        dayKey: String,
        fallbackDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        if !dayKey.isEmpty, let parsed = HomeModel.date(fromDayKey: dayKey, calendar: calendar) {
            return HomeModel.normalizedDay(parsed, calendar: calendar)
        }

        return HomeModel.normalizedDay(fallbackDate, calendar: calendar)
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
        isMorningStreakFrozen: Bool,
        isDailyTaskStreakFrozen: Bool,
        sevenDayProgress: [HomeModel.DayProgress],
        isNeverMissTwiceMorningRisk: Bool,
        isNeverMissTwiceDailyRisk: Bool
    ) {
        self.contextualList = contextualList
        self.isReadOnly = isReadOnly
        self.morningStreakCount = morningStreakCount
        self.dailyTaskStreakCount = dailyTaskStreakCount
        self.isMorningStreakFrozen = isMorningStreakFrozen
        self.isDailyTaskStreakFrozen = isDailyTaskStreakFrozen
        self.sevenDayProgress = sevenDayProgress
        self.isNeverMissTwiceMorningRisk = isNeverMissTwiceMorningRisk
        self.isNeverMissTwiceDailyRisk = isNeverMissTwiceDailyRisk
    }
#endif
}
