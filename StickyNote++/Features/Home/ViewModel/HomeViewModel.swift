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
    // UI state
    @Published var selectedDay: Date = HomeModel.normalizedDay(Date())
    /// Today's (or the selected day's) morning-list occurrences, in display order.
    @Published var morningEntries: [Occurrence] = []
    /// The day list's occurrences, in display order.
    @Published var dailyTasks: [Occurrence] = []
    /// The evening list's occurrences, in display order.
    @Published var eveningEntries: [Occurrence] = []
    @Published var newTaskTitle: String = ""
    /// The add field's options menu: must happen today, deadline, bump limit. Reset after each add.
    @Published var newTaskOptions = OneOffOptions()
    /// The sheet on screen: bump, edit, or the add menu's deadline picker.
    @Published var activeSheet: HomeSheet?

    @Published var contextualList: HomeModel.ContextualList = .daily
    @Published var isReadOnly: Bool = false
    @Published var morningStreakCount: Int = 0
    @Published var dailyTaskStreakCount: Int = 0
    @Published var isMorningStreakFrozen: Bool = false
    @Published var isDailyTaskStreakFrozen: Bool = false
    /// The evening list has its own streak; the header doesn't show it yet.
    @Published var eveningStreakCount: Int = 0
    @Published var isEveningStreakFrozen: Bool = false
    @Published var sevenDayProgress: [HomeModel.DayProgress] = []
    /// Bump actions on the ring's seven days, all lists ("N bumps in 7 days"; hidden at 0).
    @Published var bumpsInSevenDays: Int = 0
    /// Items behind today's rows that have ended (deleted or replaced by a repeat change): their
    /// rows get no Edit… or Delete.
    @Published var endedItemIDs: Set<UUID> = []
    /// The add menu's options from before "Until Deadline" was picked with no deadline, restored
    /// if the deadline sheet is cancelled.
    var optionsBeforeDeadlinePick: OneOffOptions?
    @Published var isNeverMissTwiceMorningRisk: Bool = false
    @Published var isNeverMissTwiceDailyRisk: Bool = false
    /// When Home next needs a refresh on its own (the morning's end, the evening's start or
    /// midnight). HomeView sleeps until it.
    @Published var nextClockBoundary: Date = .distantFuture

    /// Every stored day's flip-time rules, re-read on each refresh.
    var dayRulesHistory = DayRulesHistory()
    /// The list the time and what's done pick, before any manual flip.
    var automaticContextualList: HomeModel.ContextualList = .daily
    var nowOverride: Date?
    let defaults: UserDefaults
    let repository: HomeRepository
    let reloadWidget: () -> Void
    /// Adds a one-off to the day list: (day, title, the add menu's options, context).
    let createDailyTask: (Date, String, OneOffOptions, ModelContext) throws -> Occurrence?
    var manualContextualListOverride: HomeModel.ContextualList?
    /// True while the user is on "today", so Home moves with the clock; false once they pick another day.
    var isFollowingToday = true
    let progressWindowDays = 7

    var now: Date {
        nowOverride ?? Date()
    }

    init(
        defaults: UserDefaults? = nil,
        repository: HomeRepository? = nil,
        reloadWidget: (() -> Void)? = nil,
        createDailyTask: ((Date, String, OneOffOptions, ModelContext) throws -> Occurrence?)? = nil
    ) {
        self.defaults = defaults ?? SharedPersistence.sharedDefaults
        self.repository = repository ?? SwiftDataHomeRepository()
        self.reloadWidget = reloadWidget ?? TaskWidgetReloader.reloadTopTasksWidget
        self.createDailyTask = createDailyTask ?? { day, title, options, context in
            try ListService.addOneOff(
                list: .day,
                dayKey: HomeModel.dayKey(for: day),
                title: title,
                options: options,
                context: context
            )
        }
    }

    // MARK: - Public API

    func refresh(context: ModelContext) {
        // Today's rules (first read wins), the one-time V1 copy, then today's occurrences
        // (whichever day is on screen).
        prepareStore(context: context)
        loadDayRules()

        let calendar = Calendar.current
        let day = HomeModel.normalizedDay(selectedDay, calendar: calendar)
        selectedDay = day

        let dayKey = HomeModel.dayKey(for: day, calendar: calendar)
        morningEntries = fetchOccurrences(on: dayKey, list: .morning, context: context)
        dailyTasks = fetchOccurrences(on: dayKey, list: .day, context: context)
        eveningEntries = fetchOccurrences(on: dayKey, list: .evening, context: context)
        endedItemIDs = (try? ListService.endedItemIDs(among: morningEntries + dailyTasks + eveningEntries, context: context)) ?? []

        recalculateDerivedState(context: context)
        // A fixed clock (the screenshot harness) never reaches a boundary.
        nextClockBoundary = nowOverride == nil ? todaysRules.nextBoundary(after: now, calendar: calendar) : .distantFuture
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

    /// The scheduled boundary has come (the morning's end, the evening's start or midnight): on
    /// today, the automatic list takes over again, so a flip made earlier doesn't hide the evening.
    func handleClockBoundary(context: ModelContext) {
        if isFollowingToday {
            manualContextualListOverride = nil
        }
        handleClockChange(context: context)
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

    /// Cycles morning → day → evening → morning. The automatic choice (by time) is unchanged.
    func flipStickyNoteList() {
        let nextList = contextualList.next
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

    var isMorningProgressNeutral: Bool {
        morningCompletionState.isNeutral
    }

    var dailyProgress: Double {
        dailyCompletionState.value
    }

    var isDailyProgressNeutral: Bool {
        dailyCompletionState.isNeutral
    }

    var activeListProgressPercent: Int {
        Int((activeListProgress * 100).rounded())
    }

    /// The occurrences of the list on screen.
    var activeEntries: [Occurrence] {
        switch contextualList {
        case .morning: return morningEntries
        case .daily: return dailyTasks
        case .evening: return eveningEntries
        }
    }

    var activeListProgress: Double {
        ListRules.completion(activeEntries).value
    }

    /// Nothing counted on the list (empty, or all skipped): no fill and "—", never 100%.
    var activeListProgressIsNeutral: Bool {
        ListRules.completion(activeEntries).isNeutral
    }

    /// "40%", or "—" when there's nothing to count.
    var activeListProgressText: String {
        activeListProgressIsNeutral ? "—" : "\(activeListProgressPercent)%"
    }

    var activeListTitle: String {
        Self.title(of: contextualList)
    }

    /// What the flip button shows next, for its accessibility label.
    var nextListTitle: String {
        Self.title(of: contextualList.next)
    }

    static func title(of list: HomeModel.ContextualList) -> String {
        switch list {
        case .morning: return "Morning Routine"
        case .daily: return "Daily Tasks"
        case .evening: return "Evening Routine"
        }
    }

    /// Retype to bump (Settings → Bumping), on by default.
    var retypeToBump: Bool {
        AppSettings.retypeToBump(in: defaults)
    }

    /// Whether Edit… and Delete apply to this row: one-offs always; a recurring row only while its
    /// item hasn't ended.
    func canEditOrDelete(_ occurrence: Occurrence) -> Bool {
        guard let itemID = occurrence.itemID else { return true }
        return !endedItemIDs.contains(itemID)
    }

    /// After the deadline sheet closes: if "Until Deadline" was picked but no deadline was set,
    /// the bump limit goes back to what it was.
    func revertUnsetDeadlineChoice() {
        defer { optionsBeforeDeadlinePick = nil }
        guard newTaskOptions.limitChoice == .untilDeadline, newTaskOptions.deadlineDayKey == nil else { return }
        let previous = optionsBeforeDeadlinePick ?? OneOffOptions()
        newTaskOptions.limitChoice = previous.limitChoice
        newTaskOptions.days = previous.days
    }

    /// Opens the bump sheet for one of today's rows (the widget's bump with Retype to bump on),
    /// if it can still be bumped.
    func openBumpSheet(for id: UUID, context: ModelContext) {
        guard
            let occurrence = occurrence(id: id, context: context),
            occurrence.dayKey == HomeModel.dayKey(for: now),
            canBump(occurrence)
        else { return }
        activeSheet = .bump(id)
    }

    /// A row on screen, or any occurrence in the store.
    func occurrence(id: UUID, context: ModelContext) -> Occurrence? {
        if let row = (morningEntries + dailyTasks + eveningEntries).first(where: { $0.id == id }) {
            return row
        }
        return try? ListService.occurrence(id: id, context: context)
    }

    var sortedDailyTasks: [Occurrence] {
        dailyTasks
    }

    /// Whether this occurrence may move to tomorrow (its bump limit, or its repeat's period end).
    func canBump(_ occurrence: Occurrence) -> Bool {
        ListService.canBump(occurrence)
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
        todaysRules.morningDeadline(on: now)
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

    /// Re-reads every day's stored rules. Today's are normally stored by `prepareStore`; if that
    /// failed, today goes by the settings as they are.
    func loadDayRules() {
        var history = DayRulesStore.history(in: defaults)
        let todayKey = HomeModel.dayKey(for: now)
        if history.stored[todayKey] == nil {
            history.stored[todayKey] = AppSettings.currentRules(in: defaults)
        }
        dayRulesHistory = history
    }

    /// Today's flip-time rules (the real today, whichever day is on screen).
    var todaysRules: DayRules {
        dayRulesHistory.rules(for: HomeModel.dayKey(for: now))
    }

    var morningCompletionState: HomeModel.CompletionState {
        ListRules.completion(morningEntries)
    }

    var dailyCompletionState: HomeModel.CompletionState {
        ListRules.completion(dailyTasks)
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
