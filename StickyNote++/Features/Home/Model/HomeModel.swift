import Foundation

enum HomeModel {
    enum MorningMode: Equatable {
        case cutoff(time: DateComponents)
        case sinceWakeUp(wakeUpTime: DateComponents, durationMinutes: Int)
    }

    enum ContextualList {
        case morning
        case daily
    }

    struct CompletionState: Equatable {
        let value: Double
        let isImplicitlyComplete: Bool
    }

    struct StreakState: Equatable {
        let count: Int
        let isFrozen: Bool
    }

    struct DayProgress: Identifiable, Equatable {
        let date: Date
        let morning: CompletionState
        let daily: CompletionState

        var id: Date { date }
    }

    static func normalizedDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isToday(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        normalizedDay(day, calendar: calendar) == normalizedDay(now, calendar: calendar)
    }

    static func isPastDay(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        normalizedDay(day, calendar: calendar) < normalizedDay(now, calendar: calendar)
    }

    static func morningDeadline(
        for day: Date,
        mode: MorningMode,
        calendar: Calendar = .current
    ) -> Date {
        let normalized = normalizedDay(day, calendar: calendar)

        switch mode {
        case let .cutoff(time):
            let hour = time.hour ?? 9
            let minute = time.minute ?? 0
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: normalized) ?? normalized
        case let .sinceWakeUp(wakeUpTime, durationMinutes):
            let hour = wakeUpTime.hour ?? 7
            let minute = wakeUpTime.minute ?? 0
            let wakeUp = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: normalized) ?? normalized
            return calendar.date(byAdding: .minute, value: max(durationMinutes, 0), to: wakeUp) ?? wakeUp
        }
    }

    static func shouldShowMorningList(
        for selectedDay: Date,
        morningEntries: [MorningRoutineEntry],
        mode: MorningMode,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isToday(selectedDay, now: now, calendar: calendar) else { return false }
        guard morningCompletion(entries: morningEntries).value < 1.0 else { return false }
        return now < morningDeadline(for: selectedDay, mode: mode, calendar: calendar)
    }

    static func morningCompletion(entries: [MorningRoutineEntry]) -> CompletionState {
        guard !entries.isEmpty else {
            return CompletionState(value: 1.0, isImplicitlyComplete: true)
        }

        let done = entries.filter { $0.isCompleted }.count
        return CompletionState(
            value: Double(done) / Double(entries.count),
            isImplicitlyComplete: false
        )
    }

    static func dailyCompletion(tasks: [DailyTask]) -> CompletionState {
        guard !tasks.isEmpty else {
            return CompletionState(value: 1.0, isImplicitlyComplete: true)
        }

        let done = tasks.filter { $0.isCompleted }.count
        return CompletionState(
            value: Double(done) / Double(tasks.count),
            isImplicitlyComplete: false
        )
    }

    static func qualifiesForMorningStreak(
        day: Date,
        entries: [MorningRoutineEntry],
        mode: MorningMode,
        calendar: Calendar = .current
    ) -> Bool {
        guard !entries.isEmpty else { return false }
        guard morningCompletion(entries: entries).value >= 1.0 else { return false }

        let deadline = morningDeadline(for: day, mode: mode, calendar: calendar)
        if let latestKnownCompletion = entries.compactMap(\.completedAt).max() {
            return latestKnownCompletion <= deadline
        }

        // Legacy rows can be completed without timestamps; avoid forcing streak to zero.
        return true
    }

    static func morningStreak(
        through anchorDay: Date,
        entriesByDay: [Date: [MorningRoutineEntry]],
        mode: MorningMode,
        calendar: Calendar = .current
    ) -> Int {
        morningStreakState(
            through: anchorDay,
            entriesByDay: entriesByDay,
            mode: mode,
            calendar: calendar
        ).count
    }

    static func morningStreakState(
        through anchorDay: Date,
        entriesByDay: [Date: [MorningRoutineEntry]],
        mode: MorningMode,
        calendar: Calendar = .current
    ) -> StreakState {
        let anchor = normalizedDay(anchorDay, calendar: calendar)
        let earliestTrackedDay = entriesByDay.keys.min().map {
            normalizedDay($0, calendar: calendar)
        } ?? anchor

        return streakState(
            through: anchor,
            earliestTrackedDay: earliestTrackedDay,
            calendar: calendar
        ) { day in
            qualifiesForMorningStreak(
                day: day,
                entries: entriesByDay[day] ?? [],
                mode: mode,
                calendar: calendar
            )
        }
    }

    static func qualifiesForDailyStreak(tasks: [DailyTask]) -> Bool {
        guard !tasks.isEmpty else { return false }
        return dailyCompletion(tasks: tasks).value >= 1.0
    }

    static func dailyStreak(
        through anchorDay: Date,
        tasksByDay: [Date: [DailyTask]],
        calendar: Calendar = .current
    ) -> Int {
        dailyStreakState(
            through: anchorDay,
            tasksByDay: tasksByDay,
            calendar: calendar
        ).count
    }

    static func dailyStreakState(
        through anchorDay: Date,
        tasksByDay: [Date: [DailyTask]],
        calendar: Calendar = .current
    ) -> StreakState {
        let anchor = normalizedDay(anchorDay, calendar: calendar)
        let earliestTrackedDay = tasksByDay.keys.min().map {
            normalizedDay($0, calendar: calendar)
        } ?? anchor

        return streakState(
            through: anchor,
            earliestTrackedDay: earliestTrackedDay,
            calendar: calendar
        ) { day in
            qualifiesForDailyStreak(tasks: tasksByDay[day] ?? [])
        }
    }

    private static func streakState(
        through anchorDay: Date,
        earliestTrackedDay: Date,
        calendar: Calendar = .current,
        isComplete: (Date) -> Bool
    ) -> StreakState {
        let anchor = normalizedDay(anchorDay, calendar: calendar)
        let start = min(normalizedDay(earliestTrackedDay, calendar: calendar), anchor)
        var streakCount = 0
        var isFrozenToday = false
        var cursor = start

        while cursor < anchor {
            let completed = isComplete(cursor)

            if completed {
                streakCount = max(1, streakCount + 1)
                isFrozenToday = false
            } else if isFrozenToday {
                streakCount = 0
                isFrozenToday = false
            } else if streakCount > 0 {
                isFrozenToday = true
            } else {
                isFrozenToday = false
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = normalizedDay(next, calendar: calendar)
        }

        let completedAnchorDay = isComplete(anchor)
        if completedAnchorDay {
            return StreakState(
                count: max(1, streakCount + 1),
                isFrozen: false
            )
        }

        if isFrozenToday {
            return StreakState(count: streakCount, isFrozen: streakCount > 0)
        }

        if streakCount > 0 {
            return StreakState(count: streakCount, isFrozen: false)
        }

        return StreakState(count: 0, isFrozen: false)
    }
}
