#if DEBUG
import Foundation
import SwiftData
import os

/// Test-only launch mode used by the screenshot workflow (`scripts/screenshots.sh`).
///
/// Launch with `-uiScenario <morning|daily|empty>` and optionally `-uiScreen <home|calendar|settings>`.
/// The app then runs on an in-memory store seeded with fixed sample data, at a fixed time of day,
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
                seedHistory(today: today, missYesterday: scenario.missesYesterday, context: context, calendar: calendar)
                seedToday(scenario: scenario, today: today, context: context, calendar: calendar)
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

    /// Twelve past days: routine done by 07:50 on all but two days, and three tasks a day, mostly done.
    /// With `missYesterday`, yesterday's routine and tasks are left unfinished.
    private static func seedHistory(today: Date, missYesterday: Bool, context: ModelContext, calendar: Calendar) {
        for (order, title) in routineTitles.enumerated() {
            context.insert(MorningRoutineTemplateItem(title: title, sortOrder: order))
        }

        for daysAgo in 1...12 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let missedThisDay = missYesterday && daysAgo == 1
            let routineMissed = daysAgo == 5 || daysAgo == 9 || missedThisDay
            for (order, title) in routineTitles.enumerated() {
                let done = !routineMissed || order < 3
                context.insert(
                    MorningRoutineEntry(
                        date: day,
                        titleSnapshot: title,
                        sortOrderSnapshot: order,
                        isCompleted: done,
                        completedAt: done ? at(hour: 7, minute: 30 + order * 3, on: day, calendar: calendar) : nil
                    )
                )
            }

            let tasks = ["Reply to emails", "Write for 30 minutes", "Stretch"]
            for (order, title) in tasks.enumerated() {
                let done = !missedThisDay && (daysAgo != 3 || order == 0)
                context.insert(
                    DailyTask(
                        date: day,
                        title: title,
                        isCompleted: done,
                        completedAt: done ? at(hour: 18, minute: order * 10, on: day, calendar: calendar) : nil,
                        sortOrder: order
                    )
                )
            }
        }
    }

    private static func seedToday(scenario: Scenario, today: Date, context: ModelContext, calendar: Calendar) {
        let routineDoneCount = (scenario == .daily) ? routineTitles.count : 2
        for (order, title) in routineTitles.enumerated() {
            let done = order < routineDoneCount
            context.insert(
                MorningRoutineEntry(
                    date: today,
                    titleSnapshot: title,
                    sortOrderSnapshot: order,
                    isCompleted: done,
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
            context.insert(
                DailyTask(
                    date: today,
                    title: task.title,
                    isCompleted: task.done,
                    completedAt: task.done ? at(hour: 9, minute: 30, on: today, calendar: calendar) : nil,
                    sortOrder: order,
                    bumpCount: task.bumps
                )
            )
        }
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
