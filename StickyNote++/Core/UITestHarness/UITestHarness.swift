#if DEBUG
import Foundation
import SwiftData
import os

/// Test-only launch mode used by the screenshot workflow (`scripts/screenshots.sh`).
///
/// Launch with `-uiScenario <morning|daily|empty|missedYesterday|missedTwice>` and optionally
/// `-uiScreen <home|calendar|settings>`.
/// The app then runs on an in-memory store seeded with fixed sample data (V2 items and occurrences;
/// the V1 tables stay empty, so the one-time backfill finds nothing), at a fixed time of day,
/// with its own settings suite, and the app skips opening the shared on-disk store entirely,
/// so real data and settings are never touched. It fixes the time of day only: dates are still
/// relative to the real today, because some views read `Date()` directly. Debug builds only.
enum UITestHarness {
    enum Scenario: String {
        /// 08:15, two of six routine items done: the morning list is showing.
        case morning
        /// 14:00, routine finished at 07:40: the daily list, including a twice-bumped task.
        case daily
        /// 14:00, nothing set up at all.
        case empty
        /// 08:15, both lists missed yesterday, morning still saveable: two "Missed yesterday" lines.
        case missedYesterday
        /// 14:00, both lists missed yesterday and this morning's routine unfinished past the cutoff:
        /// "Missed twice" for the morning, "Missed yesterday" for the daily tasks.
        case missedTwice

        var missesYesterday: Bool { self == .missedYesterday || self == .missedTwice }
    }

    struct Configuration {
        let container: ModelContainer
        let viewModel: HomeViewModel
        let initialDestination: HomeInitialDestination
    }

    static let routineTitles = ["Cold shower", "Hang", "Teeth", "Floss", "Water", "Outside"]
    /// The history day nobody opened (no rows; the routine was due).
    static let unopenedDaysAgo = 3

    /// Built once per launch: `nil` unless the app was started with `-uiScenario`.
    @MainActor static let current: Configuration? = configuration()

    @MainActor
    static func configuration(from arguments: [String] = ProcessInfo.processInfo.arguments) -> Configuration? {
        guard let scenario = value(after: "-uiScenario", in: arguments).flatMap(Scenario.init(rawValue:)) else {
            return nil
        }
        let destination = value(after: "-uiScreen", in: arguments)
            .flatMap(HomeInitialDestination.init(rawValue:)) ?? .home

        let suiteName = "uitest-harness"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let now: Date
        switch scenario {
        case .morning, .missedYesterday:
            now = at(hour: 8, minute: 15, on: today, calendar: calendar)
        case .daily, .empty, .missedTwice:
            now = at(hour: 14, minute: 0, on: today, calendar: calendar)
        }

        do {
            let config = ModelConfiguration(schema: SharedPersistence.appSchema(), isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: SharedPersistence.appSchema(),
                migrationPlan: StickyNotesMigrationPlan.self,
                configurations: [config]
            )
            let context = container.mainContext
            if scenario != .empty {
                let items = seedHistory(today: today, missYesterday: scenario.missesYesterday, context: context, calendar: calendar)
                seedToday(scenario: scenario, items: items, today: today, context: context, calendar: calendar)
            }
            try context.save()

            let viewModel = HomeViewModel(
                defaults: defaults,
                repository: SwiftDataHomeRepository(defaults: defaults),
                reloadWidget: {}
            )
            viewModel.nowOverride = now
            return Configuration(container: container, viewModel: viewModel, initialDestination: destination)
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

    private static func seedToday(scenario: Scenario, items: [Item], today: Date, context: ModelContext, calendar: Calendar) {
        let todayKey = key(today)
        let routineDoneCount = (scenario == .daily) ? items.count : 2
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

        let tasks: [(title: String, done: Bool, bumps: Int)] = [
            ("Read 20 pages", true, 0),
            ("Send the hut emails", false, 0),
            ("Buy an alarm clock", false, 2),
            ("Plan the week", false, 0),
        ]
        for (order, task) in tasks.enumerated() {
            let firstAdded = calendar.date(byAdding: .day, value: -task.bumps, to: today) ?? today
            context.insert(
                Occurrence(
                    list: .day,
                    dayKey: todayKey,
                    title: task.title,
                    sortOrder: order,
                    state: task.done ? .done : .open,
                    completedAt: task.done ? at(hour: 9, minute: 30, on: today, calendar: calendar) : nil,
                    createdAt: at(hour: 7, minute: order, on: today, calendar: calendar),
                    bumpLimit: .defaultForNewOneOffs,
                    bumpCount: task.bumps,
                    firstAddedDayKey: key(firstAdded)
                )
            )
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
