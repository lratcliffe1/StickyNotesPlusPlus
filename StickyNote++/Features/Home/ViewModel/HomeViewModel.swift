import Combine
import Foundation
import SwiftData
import SwiftUI

/// Home screen orchestrator:
/// - owns observable UI state
/// - wires injected dependencies
/// - delegates storage/mutations/derived-state work to focused extensions
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

    @Published var contextualList: HomeModel.ContextualList = .daily
    @Published var isReadOnly: Bool = false
    @Published var morningStreakCount: Int = 0
    @Published var dailyTaskStreakCount: Int = 0
    @Published var isMorningStreakFrozen: Bool = false
    @Published var isDailyTaskStreakFrozen: Bool = false
    @Published var sevenDayProgress: [HomeModel.DayProgress] = []
    @Published var isNeverMissTwiceMorningRisk: Bool = false
    @Published var isNeverMissTwiceDailyRisk: Bool = false
    /// When Home next needs a refresh on its own (cutoff or midnight). HomeView sleeps until it.
    @Published var nextClockBoundary: Date = .distantFuture

    // Defaults from the implementation spec.
    var morningModeSelection: MorningModeSelection = .cutoff
    var morningCutoffTime: DateComponents = DateComponents(hour: 9, minute: 0)
    var wakeUpTime: DateComponents = DateComponents(hour: 7, minute: 0)
    var morningWindowDurationMinutes: Int = 90
    var nowOverride: Date?
    let defaults: UserDefaults
    let repository: HomeRepository
    let loadSettings: (UserDefaults) -> MorningModeSettings
    let reloadWidget: () -> Void
    let createDailyTask: (Date, String, Bool, ModelContext) throws -> DailyTask
    var manualContextualListOverride: HomeModel.ContextualList?
    /// True while the user is on "today", so Home moves with the clock; false once they pick another day.
    var isFollowingToday = true
    let streakLookbackDays = 365
    let progressWindowDays = 7

    var now: Date {
        nowOverride ?? Date()
    }

    init(
        defaults: UserDefaults? = nil,
        repository: HomeRepository? = nil,
        loadSettings: ((UserDefaults) -> MorningModeSettings)? = nil,
        reloadWidget: (() -> Void)? = nil,
        createDailyTask: ((Date, String, Bool, ModelContext) throws -> DailyTask)? = nil
    ) {
        self.defaults = defaults ?? SharedPersistence.sharedDefaults
        self.repository = repository ?? SwiftDataHomeRepository()
        self.loadSettings = loadSettings ?? MorningModeProvider.load
        self.reloadWidget = reloadWidget ?? TaskWidgetReloader.reloadTopTasksWidget
        self.createDailyTask = createDailyTask ?? { day, title, mustHappenToday, context in
            try DailyTaskMutationService.createTask(
                for: day,
                title: title,
                mustHappenToday: mustHappenToday,
                context: context,
                saveImmediately: false
            )
        }
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
        nextClockBoundary = HomeModel.nextClockBoundary(after: now, mode: morningMode, calendar: calendar)
    }

    /// Called when time may have moved on: returning to the foreground, midnight, a time-zone or
    /// clock change, or the scheduled cutoff. Follows today if the user was on today, and drops
    /// yesterday's manual list flip.
    func handleClockChange(context: ModelContext) {
        let follow = HomeModel.followClock(selectedDay: selectedDay, followingToday: isFollowingToday, now: now)
        selectedDay = follow.day
        isFollowingToday = follow.followingToday
        if follow.clearsManualList {
            manualContextualListOverride = nil
        }
        refresh(context: context)
    }

    func setSelectedDay(
        _ day: Date,
        context: ModelContext,
        preferredList: HomeModel.ContextualList? = nil
    ) {
        selectedDay = HomeModel.normalizedDay(day)
        isFollowingToday = HomeModel.isToday(selectedDay, now: now)
        manualContextualListOverride = preferredList
        refresh(context: context)
    }

    func goToToday(context: ModelContext) {
        selectedDay = HomeModel.normalizedDay(now)
        isFollowingToday = true
        manualContextualListOverride = nil
        refresh(context: context)
    }

    func flipStickyNoteList() {
        let nextList: HomeModel.ContextualList = isMorningMode ? .daily : .morning
        manualContextualListOverride = nextList
        contextualList = nextList
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

    /// One line per list at risk, the list on screen first. Empty when nothing is at risk.
    var neverMissTwiceBannerLines: [String] {
        let morningLine = Self.bannerLine(
            risk: HomeModel.streakRisk(isFrozen: isNeverMissTwiceMorningRisk, deadline: todaysMorningDeadline, now: now),
            saveable: "Missed yesterday. Don't miss twice: finish your morning routine by \(todaysMorningDeadline.formatted(date: .omitted, time: .shortened)).",
            lost: "Missed twice: your morning streak resets tomorrow."
        )
        let dailyLine = Self.bannerLine(
            risk: HomeModel.streakRisk(isFrozen: isNeverMissTwiceDailyRisk, deadline: nil, now: now),
            saveable: "Missed yesterday. Don't miss twice: finish today's tasks.",
            lost: "Missed twice: your daily-task streak resets tomorrow."
        )
        let ordered = isMorningMode ? [morningLine, dailyLine] : [dailyLine, morningLine]
        return ordered.compactMap { $0 }
    }

    private var todaysMorningDeadline: Date {
        HomeModel.morningDeadline(for: HomeModel.normalizedDay(now), mode: morningMode)
    }

    private static func bannerLine(risk: HomeModel.StreakRisk, saveable: String, lost: String) -> String? {
        switch risk {
        case .none: return nil
        case .saveable: return saveable
        case .lost: return lost
        }
    }

    func dayFromStored(
        dayKey: String,
        fallbackDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        HomeDataStore.dayFromStored(dayKey: dayKey, fallbackDate: fallbackDate, calendar: calendar)
    }

    func loadMorningSettings() {
        let settings = loadSettings(defaults)
        morningModeSelection = settings.selection == .sinceWakeUp ? .sinceWakeUp : .cutoff
        morningCutoffTime = settings.cutoffTime
        wakeUpTime = settings.wakeUpTime
        morningWindowDurationMinutes = settings.windowDurationMinutes
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

    var morningCompletionState: HomeModel.CompletionState {
        HomeModel.morningCompletion(entries: morningEntries)
    }

    var dailyCompletionState: HomeModel.CompletionState {
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
