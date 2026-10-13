#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import os

/// Test-only launch mode used by the screenshot workflow (`scripts/screenshots.sh`).
///
/// Launch with `-uiScenario <morning|lateMorning|noon|daily|evening|empty|missedYesterday|missedTwice|states|statesMorning|fills>`,
/// optionally `-uiScreen <home|calendar|settings|editLists|itemEditor|repeatPicker|bump|addOptions|deadline|vaultLink>`,
/// `-uiList <morning|day|evening>` (the list Home shows, or Edit Lists' segment),
/// `-uiMorningEnds <setTime|doneOrSkipped>` (default setTime, 09:00) and `-uiEvening <on|off>`
/// (default on, 21:00): the settings, which today's rules are stored from; `-uiTodayKeeps HH:MM`
/// (today already stored at that set time) and `-uiAppearance <light|dark>`. `-uiDay <±N>` opens
/// Home on the day N days from today (e.g. `+3`, a future day with a planned task), and
/// `-uiCalendarMonth <±N>` opens the calendar N months from the current one. `-uiOnlyLists
/// <morning,day,evening>` keeps only those lists' seed data (the calendar with one or two segments).
/// `-uiVault <off|updated|rejected|session>` sets up the vault link with a fake GitHub and an in-memory token
/// (`UITestHarness+Vault.swift`).
/// The app then runs on an in-memory store seeded with fixed sample data (V2 items and occurrences;
/// the V1 tables stay empty, so the one-time backfill finds nothing), at a fixed time of day,
/// with its own settings suite, and the app skips opening the shared on-disk store entirely,
/// so real data and settings are never touched. It fixes the time of day only: dates are still
/// relative to the real today, because some views read `Date()` directly. Debug builds only.
enum UITestHarness {
    enum Scenario: String {
        /// 08:15, two of six routine items done: the morning list is showing.
        case morning
        /// 10:30, the same morning, still unfinished: past a 09:00 set time (day list), but still
        /// the morning list when it ends "when everything's done or skipped".
        case lateMorning
        /// 12:30, the same morning, still unfinished: the day list in either mode.
        case noon
        /// 14:00, routine finished at 07:40: the daily list, including a twice-bumped task.
        case daily
        /// 21:30, the same day as `daily`: the evening list (one done, one skipped, one open).
        case evening
        /// 14:00, nothing set up at all.
        case empty
        /// 08:15, both lists missed yesterday, morning still saveable: two "Missed yesterday" lines.
        case missedYesterday
        /// 14:00, both lists missed yesterday and this morning's routine unfinished past the cutoff:
        /// "Missed twice" for the morning, "Missed yesterday" for the daily tasks.
        case missedTwice
        /// 14:00, only the day list (one-offs), one state a day for the greyscale shapes (step 5):
        /// 6 days ago done, 5 partly done, 4 missed, 3 nothing due, 2 and 1 done with a bump (↻),
        /// today nothing done yet, with "Buy an alarm clock" bumped twice ("↻2").
        case states
        /// 10:30, only the morning list (three daily items), past its 09:00 set time: 6 days ago
        /// done, 5 done late (after 09:00), 4 partly done, 3 missed, 2 all skipped (nothing due),
        /// yesterday done, today all done late, at 09:20 (85% filled with ×).
        case statesMorning
        /// 14:00, only the day list (one-offs), arcs filled by the share done (fix round 1): 6 days
        /// ago 1 of 6, 5 days ago 4 of 6, 4 days ago 1 of 20 (the minimum sliver), 3 days ago all
        /// done, 2 days ago 9 of 10 (a miss, capped at 85%), yesterday nothing done, today 4 of 6
        /// so far, with a ticked "Must do" and a ticked "Due …" task.
        case fills

        var missesYesterday: Bool { self == .missedYesterday || self == .missedTwice }

        /// The morning routine is finished today (07:40).
        var routineFinished: Bool { self == .daily || self == .evening }

        var time: (hour: Int, minute: Int) {
            switch self {
            case .morning, .missedYesterday: return (8, 15)
            case .lateMorning, .statesMorning: return (10, 30)
            case .noon: return (12, 30)
            case .daily, .empty, .missedTwice, .states, .fills: return (14, 0)
            case .evening: return (21, 30)
            }
        }
    }

    /// What opens at launch. Menus and long-press menus can't be opened from launch arguments, so
    /// `addOptions` shows the add menu's result (options set, summary under the field) and
    /// `deadline` the sheet its "Deadline…" opens.
    enum Screen: String {
        case home
        case calendar
        case settings
        /// Settings → Edit Lists, on `-uiList` (default morning).
        case editLists
        /// Edit Lists → the item editor for the weekly "Gym" (day list).
        case itemEditor
        /// The same, with its repeat picker pushed.
        case repeatPicker
        /// The bump sheet for "Buy an alarm clock" (bumped twice, up to 3 days).
        case bump
        /// The add field with a title typed and a deadline + "until deadline" chosen.
        case addOptions
        /// The add menu's deadline sheet.
        case deadline
        /// Settings → Vault link (with `-uiVault`).
        case vaultLink
    }

    struct Configuration {
        let container: ModelContainer
        let viewModel: HomeViewModel
        let initialDestination: HomeInitialDestination
        let editListsLaunch: EditListsLaunch?
        let initialSheet: HomeSheet?
        /// `-uiAppearance dark|light`: forced in the app, so a shot never races the simulator's
        /// own appearance switch.
        let colorScheme: ColorScheme?
        /// The calendar's first month, as months after the current one.
        let calendarMonthOffset: Int
        let vault: VaultSync
    }

    static let routineTitles = ["Cold shower", "Hang", "Teeth", "Floss", "Water", "Outside"]
    /// The history day nobody opened (no rows; the routine was due).
    static let unopenedDaysAgo = 3
    /// The evening list has been in use since this many days ago (three segments from then on).
    static let eveningDaysAgo = 2
    /// The one-off planned ahead ("Book the hut"), this many days from today.
    static let plannedDaysAhead = 3

    /// Built once per launch: `nil` unless the app was started with `-uiScenario`.
    @MainActor static let current: Configuration? = configuration()

    @MainActor
    static func configuration(from arguments: [String] = ProcessInfo.processInfo.arguments) -> Configuration? {
        guard let scenario = value(after: "-uiScenario", in: arguments).flatMap(Scenario.init(rawValue:)) else {
            return nil
        }
        let screen = value(after: "-uiScreen", in: arguments).flatMap(Screen.init(rawValue:)) ?? .home
        let list = value(after: "-uiList", in: arguments).flatMap(ListKind.init(rawValue:))

        let suiteName = "uitest-harness"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        // The settings today's rules are stored from (the first refresh stores them).
        if let ends = value(after: "-uiMorningEnds", in: arguments).flatMap(DayRules.MorningEnd.init(rawValue:)) {
            defaults.set(ends.rawValue, forKey: AppSettings.morningEndKey)
        }
        if let evening = value(after: "-uiEvening", in: arguments) {
            defaults.set(evening != "off", forKey: AppSettings.eveningEnabledKey)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now = at(hour: scenario.time.hour, minute: scenario.time.minute, on: today, calendar: calendar)
        // `-uiTodayKeeps HH:MM`: today already stored "at a set time" then (first read wins), so a
        // different morning setting shows Settings' "applies from tomorrow" line.
        if let kept = value(after: "-uiTodayKeeps", in: arguments) {
            let parts = kept.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                let rules = DayRules(
                    morningEnd: .setTime, morningEndMinutes: parts[0] * 60 + parts[1],
                    eveningStartMinutes: AppSettings.currentRules(in: defaults).eveningStartMinutes
                )
                DayRulesStore.record(rules, for: key(today), in: defaults)
            }
        }
        let colorScheme: ColorScheme? = switch value(after: "-uiAppearance", in: arguments) {
        case "dark": .dark
        case "light": .light
        default: nil
        }

        do {
            let config = ModelConfiguration(schema: SharedPersistence.appSchema(), isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: SharedPersistence.appSchema(),
                migrationPlan: StickyNotesMigrationPlan.self,
                configurations: [config]
            )
            let context = container.mainContext
            var alarmClock: Occurrence?
            if scenario == .states {
                alarmClock = seedStates(today: today, context: context, calendar: calendar)
            } else if scenario == .statesMorning {
                seedStatesMorning(today: today, context: context, calendar: calendar)
            } else if scenario == .fills {
                seedFills(today: today, context: context, calendar: calendar)
            } else if scenario != .empty {
                let items = seedHistory(today: today, missYesterday: scenario.missesYesterday, context: context, calendar: calendar)
                alarmClock = seedToday(scenario: scenario, items: items, today: today, now: now, context: context, calendar: calendar)
            }
            if let only = value(after: "-uiOnlyLists", in: arguments) {
                let kept = Set(only.split(separator: ",").map(String.init))
                for item in try context.fetch(FetchDescriptor<Item>()) where !kept.contains(item.listRaw) {
                    context.delete(item)
                }
                for row in try context.fetch(FetchDescriptor<Occurrence>()) where !kept.contains(row.listRaw) {
                    context.delete(row)
                }
            }
            try context.save()

            let vaultState = value(after: "-uiVault", in: arguments).flatMap(VaultState.init(rawValue:)) ?? .off
            let vault = makeVault(state: vaultState, defaults: defaults, now: now, context: context, calendar: calendar)

            let viewModel = HomeViewModel(
                defaults: defaults,
                repository: SwiftDataHomeRepository(defaults: defaults),
                reloadWidget: {}
            )
            viewModel.nowOverride = now
            if let offset = value(after: "-uiDay", in: arguments).flatMap({ Int($0) }), offset != 0,
               let day = calendar.date(byAdding: .day, value: offset, to: today) {
                viewModel.selectedDay = day
                viewModel.isFollowingToday = false
            }
            let calendarMonthOffset = value(after: "-uiCalendarMonth", in: arguments).flatMap { Int($0) } ?? 0

            var destination = HomeInitialDestination.home
            var editListsLaunch: EditListsLaunch?
            var initialSheet: HomeSheet?
            switch screen {
            case .home:
                if let list {
                    viewModel.manualListFlip = .untilLeft(contextualList(for: list))
                }
            case .calendar:
                destination = .calendar
            case .settings:
                destination = .settings
            case .vaultLink:
                destination = .settings
                vault.opensLinkScreenOnAppear = true
            case .editLists:
                editListsLaunch = EditListsLaunch(list: list ?? .morning)
            case .itemEditor, .repeatPicker:
                editListsLaunch = EditListsLaunch(list: list ?? .day, openItemTitle: "Gym", showsRepeat: screen == .repeatPicker)
            case .bump:
                initialSheet = alarmClock.map { HomeSheet.bump($0.id) }
            case .addOptions, .deadline:
                viewModel.manualListFlip = .untilLeft(.daily)
                viewModel.newTaskTitle = "Renew passport photos"
                viewModel.newTaskOptions = OneOffOptions(
                    deadlineDayKey: key(calendar.date(byAdding: .day, value: 4, to: today) ?? today),
                    limitChoice: .untilDeadline
                )
                if screen == .deadline {
                    initialSheet = .deadline
                }
            }
            return Configuration(
                container: container,
                viewModel: viewModel,
                initialDestination: destination,
                editListsLaunch: editListsLaunch,
                initialSheet: initialSheet,
                colorScheme: colorScheme,
                calendarMonthOffset: calendarMonthOffset,
                vault: vault
            )
        } catch {
            AppLogger.persistence.error("UITestHarness setup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Twelve past days of history on the V2 model: the six routine items (repeating daily) done by
    /// 07:50 on all but two days, and three one-off tasks a day, mostly done. Two days exercise the
    /// new streak rules without changing what's on screen: 8 days ago one routine item was skipped
    /// (the rest done, so still complete), and 6 days ago "Stretch" was bumped to the next day and
    /// done there. 3 days ago nobody opened the app: no rows at all, while the daily routine was due,
    /// so the ring shows that morning as a 0% miss and its day half as neutral grey.
    /// With `missYesterday`, yesterday's routine and tasks are left unfinished.
    private static func seedHistory(today: Date, missYesterday: Bool, context: ModelContext, calendar: Calendar) -> [Item] {
        guard let firstDay = calendar.date(byAdding: .day, value: -12, to: today) else { return [] }
        let items = routineTitles.enumerated().map { order, title in
            Item(
                list: .morning,
                title: title,
                sortOrder: order,
                repeatRule: .daily,
                startDayKey: key(firstDay),
                createdAt: firstDay
            )
        }
        for item in items {
            context.insert(item)
        }
        var stretchToBump: Occurrence?

        for daysAgo in 1...12 {
            guard daysAgo != unopenedDaysAgo else { continue }
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let dayKey = key(day)
            let missedThisDay = missYesterday && daysAgo == 1
            let routineMissed = daysAgo == 5 || daysAgo == 9 || missedThisDay
            for (order, item) in items.enumerated() {
                let done = !routineMissed || order < 3
                let skipped = daysAgo == 8 && order == items.count - 1
                context.insert(
                    routineOccurrence(
                        item: item,
                        dayKey: dayKey,
                        state: skipped ? .skipped : (done ? .done : .open),
                        completedAt: done && !skipped ? at(hour: 7, minute: 30 + order * 3, on: day, calendar: calendar) : nil
                    )
                )
            }

            let tasks = ["Reply to emails", "Write for 30 minutes", "Stretch"]
            for (order, title) in tasks.enumerated() {
                let done = !missedThisDay
                let task = Occurrence(
                    list: .day,
                    dayKey: dayKey,
                    title: title,
                    sortOrder: order,
                    state: done ? .done : .open,
                    completedAt: done ? at(hour: 18, minute: order * 10, on: day, calendar: calendar) : nil,
                    createdAt: at(hour: 7, minute: order, on: day, calendar: calendar)
                )
                context.insert(task)
                if daysAgo == 6 && title == "Stretch" {
                    stretchToBump = task
                }
            }
        }

        if let stretchToBump {
            seedBump(of: stretchToBump, today: today, context: context, calendar: calendar)
        }
        return items
    }

    /// The `states` scenario: day-list one-offs only, so every day is a one-list circle (with its
    /// ✓ or × badge in the calendar). Earlier days are done, from 12 days ago. Returns today's
    /// "Buy an alarm clock" (bumped from 2 days ago, so those two days carry the ↻).
    private static func seedStates(today: Date, context: ModelContext, calendar: Calendar) -> Occurrence {
        // Per day: (done, open) one-offs. 3 days ago has no rows: nothing due.
        var plan: [Int: (done: Int, open: Int)] = [6: (2, 0), 5: (1, 2), 4: (0, 2), 2: (1, 0), 1: (1, 0)]
        for daysAgo in 7...12 {
            plan[daysAgo] = (2, 0)
        }
        let titles = ["Reply to emails", "Write for 30 minutes", "Stretch"]
        for (daysAgo, counts) in plan {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            for order in 0..<(counts.done + counts.open) {
                let done = order < counts.done
                context.insert(
                    Occurrence(
                        list: .day,
                        dayKey: key(day),
                        title: titles[order % titles.count],
                        sortOrder: order,
                        state: done ? .done : .open,
                        completedAt: done ? at(hour: 18, minute: order * 10, on: day, calendar: calendar) : nil,
                        createdAt: at(hour: 7, minute: order, on: day, calendar: calendar)
                    )
                )
            }
        }
        context.insert(
            Occurrence(
                list: .day,
                dayKey: key(today),
                title: "Post the parcel",
                sortOrder: 0,
                createdAt: at(hour: 7, minute: 0, on: today, calendar: calendar),
                bumpLimit: .defaultForNewOneOffs
            )
        )
        return seedAlarmClockChain(today: today, context: context, calendar: calendar)
    }

    /// The `statesMorning` scenario: three daily morning items from 12 days ago, one state a day
    /// over the last week (see `Scenario.statesMorning`); earlier days done on time.
    private static func seedStatesMorning(today: Date, context: ModelContext, calendar: Calendar) {
        guard let firstDay = calendar.date(byAdding: .day, value: -12, to: today) else { return }
        let items = ["Cold shower", "Teeth", "Water"].enumerated().map { order, title in
            Item(list: .morning, title: title, sortOrder: order, repeatRule: .daily, startDayKey: key(firstDay), createdAt: firstDay)
        }
        for item in items {
            context.insert(item)
        }
        enum Morning { case onTime, late, partly, missed, skipped }
        var plan: [Int: Morning] = [6: .onTime, 5: .late, 4: .partly, 3: .missed, 2: .skipped, 1: .onTime, 0: .late]
        for daysAgo in 7...12 {
            plan[daysAgo] = .onTime
        }
        for (daysAgo, morning) in plan {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            for (order, item) in items.enumerated() {
                let state: OccurrenceState
                switch morning {
                case .onTime, .late: state = .done
                case .partly: state = order == 0 ? .done : .open
                case .missed: state = .open
                case .skipped: state = .skipped
                }
                let hour = morning == .late ? 9 : 7
                context.insert(
                    routineOccurrence(
                        item: item,
                        dayKey: key(day),
                        state: state,
                        completedAt: state == .done ? at(hour: hour, minute: 20 + order * 3, on: day, calendar: calendar) : nil
                    )
                )
            }
        }
    }

    /// The `fills` scenario: day-list one-offs only, one share done a day (see `Scenario.fills`);
    /// earlier days done.
    private static func seedFills(today: Date, context: ModelContext, calendar: Calendar) {
        var plan: [Int: (done: Int, open: Int)] = [6: (1, 5), 5: (4, 2), 4: (1, 19), 3: (6, 0), 2: (9, 1), 1: (0, 3)]
        for daysAgo in 7...12 {
            plan[daysAgo] = (2, 0)
        }
        let titles = ["Reply to emails", "Write for 30 minutes", "Stretch", "Call the bank", "Water the plants", "Tidy the desk"]
        for (daysAgo, counts) in plan {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            for order in 0..<(counts.done + counts.open) {
                let done = order < counts.done
                context.insert(
                    Occurrence(
                        list: .day,
                        dayKey: key(day),
                        title: titles[order % titles.count],
                        sortOrder: order,
                        state: done ? .done : .open,
                        completedAt: done ? at(hour: 18, minute: order, on: day, calendar: calendar) : nil,
                        createdAt: at(hour: 7, minute: order, on: day, calendar: calendar)
                    )
                )
            }
        }
        // Today, 4 of 6 done: a ticked "Must do" and a ticked "Due …" keep their notes.
        let dueDay = key(calendar.date(byAdding: .day, value: 2, to: today) ?? today)
        let todays: [(title: String, done: Bool, limit: BumpLimit, deadline: String?)] = [
            ("Post the parcel", true, .cantBump, nil),
            ("Renew the parking permit", true, .defaultForNewOneOffs, dueDay),
            ("Reply to emails", true, .defaultForNewOneOffs, nil),
            ("Write for 30 minutes", true, .defaultForNewOneOffs, nil),
            ("Stretch", false, .defaultForNewOneOffs, nil),
            ("Call the bank", false, .defaultForNewOneOffs, nil),
        ]
        for (order, task) in todays.enumerated() {
            context.insert(
                Occurrence(
                    list: .day,
                    dayKey: key(today),
                    title: task.title,
                    sortOrder: order,
                    state: task.done ? .done : .open,
                    completedAt: task.done ? at(hour: 9, minute: order * 5, on: today, calendar: calendar) : nil,
                    createdAt: at(hour: 7, minute: order, on: today, calendar: calendar),
                    bumpLimit: task.limit,
                    deadlineDayKey: task.deadline
                )
            )
        }
    }

    /// "Buy an alarm clock": first added 2 days ago and bumped each day since, so today's row is
    /// "↻2" with one of its three bumps left. Returns today's row.
    private static func seedAlarmClockChain(today: Date, context: ModelContext, calendar: Calendar) -> Occurrence {
        let title = "Buy an alarm clock"
        let firstDay = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let firstKey = key(firstDay)
        var previous: Occurrence?
        var row: Occurrence?
        for (bumps, daysAgo) in [2, 1, 0].enumerated() {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let isToday = daysAgo == 0
            let next = Occurrence(
                list: .day,
                dayKey: key(day),
                title: title,
                sortOrder: 3,
                state: isToday ? .open : .bumped,
                completedAt: isToday ? nil : at(hour: 21, minute: 0, on: day, calendar: calendar),
                createdAt: at(hour: 7, minute: 2, on: firstDay, calendar: calendar),
                bumpLimit: .defaultForNewOneOffs,
                bumpedFromID: previous?.id,
                bumpCount: bumps,
                firstAddedDayKey: firstKey,
                firstAddedTitle: title
            )
            context.insert(next)
            previous?.bumpedToID = next.id
            previous = next
            row = next
        }
        return row ?? Occurrence(list: .day, dayKey: key(today), title: title)
    }

    /// 6 days ago, "Stretch" was bumped (done for that day) and finished the next day.
    private static func seedBump(of stretch: Occurrence, today: Date, context: ModelContext, calendar: Calendar) {
        guard
            let fromDay = calendar.date(byAdding: .day, value: -6, to: today),
            let toDay = calendar.date(byAdding: .day, value: -5, to: today)
        else { return }
        let fromKey = key(fromDay)

        let moved = Occurrence(
            list: .day,
            dayKey: key(toDay),
            title: "Stretch",
            sortOrder: 3,
            state: .done,
            completedAt: at(hour: 19, minute: 0, on: toDay, calendar: calendar),
            createdAt: at(hour: 17, minute: 0, on: fromDay, calendar: calendar),
            bumpedFromID: stretch.id,
            bumpCount: 1,
            firstAddedDayKey: fromKey,
            firstAddedTitle: "Stretch"
        )
        context.insert(moved)
        stretch.state = .bumped
        stretch.completedAt = at(hour: 17, minute: 0, on: fromDay, calendar: calendar)
        stretch.bumpedToID = moved.id
    }

    /// Today's rows, plus the items added today: an evening routine (one done, one skipped, one open)
    /// and two repeating day-list items, so all three lists and Edit Lists have content. Today also
    /// has a bump ("Call the dentist"), so "N bumps this week" and today's ↻ always show.
    /// Returns "Buy an alarm clock" (the bump sheet's row).
    @discardableResult
    private static func seedToday(
        scenario: Scenario,
        items: [Item],
        today: Date,
        now: Date,
        context: ModelContext,
        calendar: Calendar
    ) -> Occurrence {
        let todayKey = key(today)
        let routineDoneCount = scenario.routineFinished ? items.count : 2
        for (order, item) in items.enumerated() {
            let done = order < routineDoneCount
            context.insert(
                routineOccurrence(
                    item: item,
                    dayKey: todayKey,
                    state: done ? .done : .open,
                    completedAt: done ? at(hour: 7, minute: 20 + order * 4, on: today, calendar: calendar) : nil
                )
            )
        }

        // Added to the morning list at 10:00, after its 09:00 cutoff, and ticked at 10:05: a bonus
        // row (fix round 1). The morning stays done on time; the row says it doesn't count.
        if scenario.routineFinished {
            let vitamins = Item(
                list: .morning, title: "Vitamins", sortOrder: items.count, repeatRule: .daily,
                startDayKey: todayKey, createdAt: at(hour: 10, minute: 0, on: today, calendar: calendar)
            )
            context.insert(vitamins)
            let row = ListService.makeOccurrence(
                for: vitamins, scheduledOn: todayKey, on: todayKey,
                now: at(hour: 10, minute: 0, on: today, calendar: calendar), calendar: calendar
            )
            row.state = .done
            row.completedAt = at(hour: 10, minute: 5, on: today, calendar: calendar)
            context.insert(row)
        }

        let tasks: [(title: String, done: Bool)] = [
            ("Read 20 pages", true),
            ("Send the hut emails", false),
            ("Plan the week", false),
        ]
        for (order, task) in tasks.enumerated() {
            context.insert(
                Occurrence(
                    list: .day,
                    dayKey: todayKey,
                    title: task.title,
                    sortOrder: order < 2 ? order : 4,
                    state: task.done ? .done : .open,
                    completedAt: task.done ? at(hour: 9, minute: 30, on: today, calendar: calendar) : nil,
                    createdAt: at(hour: 7, minute: order, on: today, calendar: calendar),
                    bumpLimit: .defaultForNewOneOffs
                )
            )
        }
        let alarmClock = seedAlarmClockChain(today: today, context: context, calendar: calendar)

        // Bumped today: today's row is "Bumped to tomorrow", tomorrow's copy is open.
        let dentist = Occurrence(
            list: .day,
            dayKey: todayKey,
            title: "Call the dentist",
            sortOrder: 2,
            state: .bumped,
            completedAt: at(hour: 7, minute: 45, on: today, calendar: calendar),
            createdAt: at(hour: 7, minute: 5, on: today, calendar: calendar)
        )
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let dentistTomorrow = Occurrence(
            list: .day,
            dayKey: key(tomorrow),
            title: "Call the dentist",
            sortOrder: 0,
            createdAt: at(hour: 7, minute: 45, on: today, calendar: calendar),
            bumpedFromID: dentist.id,
            bumpCount: 1,
            firstAddedDayKey: todayKey,
            firstAddedTitle: "Call the dentist"
        )
        dentist.bumpedToID = dentistTomorrow.id
        context.insert(dentist)
        context.insert(dentistTomorrow)

        // A one-off planned ahead, for Home on a future day and the calendar's dot.
        if let ahead = calendar.date(byAdding: .day, value: plannedDaysAhead, to: today) {
            context.insert(
                Occurrence(
                    list: .day,
                    dayKey: key(ahead),
                    title: "Book the hut",
                    sortOrder: 0,
                    createdAt: at(hour: 7, minute: 10, on: today, calendar: calendar)
                )
            )
        }

        // Added today, so they have no history to judge.
        let dayItems = [
            Item(list: .day, title: "Check Now.md", sortOrder: 0, repeatRule: .daily, startDayKey: todayKey, createdAt: now),
            Item(
                list: .day,
                title: "Gym",
                sortOrder: 1,
                repeatRule: .weekly(on: [
                    calendar.component(.weekday, from: today),
                    calendar.component(.weekday, from: calendar.date(byAdding: .day, value: 3, to: today) ?? today),
                ]),
                startDayKey: todayKey,
                createdAt: now
            ),
        ]
        // The evening routine started two days ago and was done both evenings.
        let eveningStart = calendar.date(byAdding: .day, value: -eveningDaysAgo, to: today) ?? today
        let eveningItems = [
            Item(list: .evening, title: "Tidy the kitchen", sortOrder: 0, repeatRule: .daily, startDayKey: key(eveningStart), createdAt: eveningStart),
            Item(list: .evening, title: "Lay out tomorrow's clothes", sortOrder: 1, repeatRule: .daily, startDayKey: key(eveningStart), createdAt: eveningStart),
            Item(list: .evening, title: "Read in bed", sortOrder: 2, repeatRule: .daily, startDayKey: key(eveningStart), createdAt: eveningStart),
        ]
        for item in dayItems + eveningItems {
            context.insert(item)
        }
        for daysAgo in 1...eveningDaysAgo {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            for item in eveningItems {
                let row = ListService.makeOccurrence(for: item, scheduledOn: key(day), on: key(day), now: day, calendar: calendar)
                row.state = .done
                row.completedAt = at(hour: 21, minute: 40, on: day, calendar: calendar)
                context.insert(row)
            }
        }
        // The evening rows exist whatever today's weekday: tidy done, clothes skipped, reading open.
        let eveningStates: [OccurrenceState] = [.done, .skipped, .open]
        for (item, state) in zip(eveningItems, eveningStates) {
            let row = ListService.makeOccurrence(for: item, scheduledOn: todayKey, on: todayKey, now: now, calendar: calendar)
            row.state = state
            row.completedAt = state == .done ? now : nil
            context.insert(row)
        }
        return alarmClock
    }

    private static func contextualList(for list: ListKind) -> HomeModel.ContextualList {
        switch list {
        case .morning: return .morning
        case .day: return .daily
        case .evening: return .evening
        }
    }

    private static func routineOccurrence(item: Item, dayKey: String, state: OccurrenceState, completedAt: Date?) -> Occurrence {
        Occurrence(
            itemID: item.id,
            list: .morning,
            dayKey: dayKey,
            title: item.title,
            sortOrder: item.sortOrder,
            state: state,
            completedAt: completedAt,
            bumpLimit: .unlimited,
            scheduledDayKey: dayKey,
            periodEndDayKey: dayKey
        )
    }

    private static func key(_ day: Date) -> String {
        HomeModel.dayKey(for: day)
    }

    private static func at(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
#endif
