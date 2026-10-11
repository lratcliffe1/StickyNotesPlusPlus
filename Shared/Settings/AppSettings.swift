import Foundation

/// Shared settings keys/defaults and time-conversion helpers used by app and widget.
/// Everything lives in the App Group defaults, so the widget reads what Settings wrote.
enum AppSettings {
    // MARK: - Morning and evening (step 3)

    /// "How the morning ends": a `DayRules.MorningEnd` raw value.
    static let morningEndKey = "morning_end"
    /// The morning's set time, in minutes after midnight (the old cutoff key, kept).
    static let morningCutoffMinutesKey = "morning_cutoff_minutes"
    static let eveningEnabledKey = "evening_enabled"
    static let eveningStartMinutesKey = "evening_start_minutes"

    /// On upgrade: at a set time, 09:00, today's behaviour (provisional: Liam to confirm).
    static let defaultMorningEnd: DayRules.MorningEnd = .setTime
    static let defaultMorningCutoffMinutes = DayRules.legacyCutoffMinutes
    static let defaultEveningEnabled = true
    static let defaultEveningStartMinutes = DayRules.defaultEveningStartMinutes

    /// The rules the settings describe right now. Days store these when first read.
    static func currentRules(in defaults: UserDefaults) -> DayRules {
        migrateWakeUpWindowIfNeeded(in: defaults)
        let end = defaults.string(forKey: morningEndKey).flatMap(DayRules.MorningEnd.init(rawValue:)) ?? defaultMorningEnd
        let endMinutes = defaults.object(forKey: morningCutoffMinutesKey) as? Int ?? defaultMorningCutoffMinutes
        let eveningOn = defaults.object(forKey: eveningEnabledKey) as? Bool ?? defaultEveningEnabled
        let eveningMinutes = defaults.object(forKey: eveningStartMinutesKey) as? Int ?? defaultEveningStartMinutes
        return DayRules(
            morningEnd: end,
            morningEndMinutes: endMinutes,
            eveningStartMinutes: eveningOn ? eveningMinutes : nil
        )
    }

    // MARK: - The removed wake-up window

    /// Keys of the removed "since wake-up" mode, read once to migrate and then deleted.
    static let legacyMorningModeKey = "morning_mode"
    static let legacyWakeUpMinutesKey = "wake_up_minutes"
    static let legacyWindowDurationMinutesKey = "morning_window_duration_minutes"

    /// The wake-up-window mode is gone. A saved one becomes "At a set time" at wake-up + duration
    /// (the duration clamped to 15–240 minutes, as before); a saved cutoff mode keeps its time.
    /// The old keys are then removed, so this runs once; running it again is harmless.
    static func migrateWakeUpWindowIfNeeded(in defaults: UserDefaults) {
        guard let mode = defaults.string(forKey: legacyMorningModeKey) else { return }
        if mode == "sinceWakeUp" {
            let wake = defaults.object(forKey: legacyWakeUpMinutesKey) as? Int ?? 7 * 60
            let duration = min(240, max(15, defaults.object(forKey: legacyWindowDurationMinutesKey) as? Int ?? 90))
            defaults.set(DayRules.MorningEnd.setTime.rawValue, forKey: morningEndKey)
            defaults.set(DayRules.clamped(wake + duration), forKey: morningCutoffMinutesKey)
        }
        // The new values are written before the old keys go, so an interrupted run just repeats.
        defaults.removeObject(forKey: legacyMorningModeKey)
        defaults.removeObject(forKey: legacyWakeUpMinutesKey)
        defaults.removeObject(forKey: legacyWindowDurationMinutesKey)
    }

    // MARK: - Bumping

    /// Retype to bump (DECISIONS.md, 2b): on by default, the bump sheet's title field starts empty.
    static let retypeToBumpKey = "retype_to_bump"
    static let defaultRetypeToBump = true

    static func retypeToBump(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: retypeToBumpKey) as? Bool ?? defaultRetypeToBump
    }

    // MARK: - Time helpers

    static func minutesFromMidnight(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return max(0, min(1_439, (hour * 60) + minute))
    }

    static func dateComponents(fromMinutes minutes: Int) -> DateComponents {
        let clamped = DayRules.clamped(minutes)
        return DateComponents(hour: clamped / 60, minute: clamped % 60)
    }

    /// Today at `minutes` after midnight (wall-clock, so a DST day shows the right time).
    static func date(fromMinutes minutes: Int, on day: Date = Date(), calendar: Calendar = .current) -> Date {
        DayRules.time(minutes, on: day, calendar: calendar)
    }
}
