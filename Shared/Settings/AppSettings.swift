import Foundation

/// Shared settings keys/defaults and time-conversion helpers used by app and widget.
enum AppSettings {
    enum MorningMode: String {
        case cutoff
        case sinceWakeUp
    }

    static let morningModeKey = "morning_mode"
    static let morningCutoffMinutesKey = "morning_cutoff_minutes"
    static let wakeUpMinutesKey = "wake_up_minutes"
    static let morningWindowDurationMinutesKey = "morning_window_duration_minutes"

    static let defaultMorningMode: MorningMode = .cutoff
    static let defaultMorningCutoffMinutes = 9 * 60
    static let defaultWakeUpMinutes = 7 * 60
    static let defaultMorningWindowDurationMinutes = 90

    static func minutesFromMidnight(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return max(0, min(1_439, (hour * 60) + minute))
    }

    static func dateComponents(fromMinutes minutes: Int) -> DateComponents {
        let clamped = max(0, min(1_439, minutes))
        return DateComponents(hour: clamped / 60, minute: clamped % 60)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: Date())
        let clamped = max(0, min(1_439, minutes))
        return calendar.date(byAdding: .minute, value: clamped, to: startOfDay) ?? startOfDay
    }
}
