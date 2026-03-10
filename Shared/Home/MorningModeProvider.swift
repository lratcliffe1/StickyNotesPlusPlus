import Foundation

/// Normalized morning-mode settings payload used by view models and widget store.
struct MorningModeSettings {
    enum Selection {
        case cutoff
        case sinceWakeUp
    }

    let selection: Selection
    let cutoffTime: DateComponents
    let wakeUpTime: DateComponents
    let windowDurationMinutes: Int

    var mode: HomeModel.MorningMode {
        switch selection {
        case .cutoff:
            return .cutoff(time: cutoffTime)
        case .sinceWakeUp:
            return .sinceWakeUp(wakeUpTime: wakeUpTime, durationMinutes: windowDurationMinutes)
        }
    }
}

enum MorningModeProvider {
    /// Single source of truth for defaults parsing + range clamping.
    static func load(from defaults: UserDefaults) -> MorningModeSettings {
        let modeRaw = defaults.string(forKey: AppSettings.morningModeKey) ?? AppSettings.defaultMorningMode.rawValue
        let selection: MorningModeSettings.Selection =
            modeRaw == AppSettings.MorningMode.sinceWakeUp.rawValue ? .sinceWakeUp : .cutoff

        let cutoffMinutes = defaults.object(forKey: AppSettings.morningCutoffMinutesKey) as? Int ?? AppSettings.defaultMorningCutoffMinutes
        let wakeMinutes = defaults.object(forKey: AppSettings.wakeUpMinutesKey) as? Int ?? AppSettings.defaultWakeUpMinutes
        let duration = defaults.object(forKey: AppSettings.morningWindowDurationMinutesKey) as? Int ?? AppSettings.defaultMorningWindowDurationMinutes

        return MorningModeSettings(
            selection: selection,
            cutoffTime: AppSettings.dateComponents(fromMinutes: cutoffMinutes),
            wakeUpTime: AppSettings.dateComponents(fromMinutes: wakeMinutes),
            windowDurationMinutes: min(240, max(15, duration))
        )
    }
}
