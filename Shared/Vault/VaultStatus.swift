import Foundation
import os

/// What the vault link last did, as Settings → Vault link shows it. Kept in the App Group
/// defaults, so a fetch made by the widget or in the background shows too. Never holds the token.
struct VaultStatus: Codable, Equatable {
    enum Kind: String, Codable {
        /// No token saved.
        case notSetUp
        /// A token was just saved; the first check hasn't answered yet.
        case connected
        /// The last check worked: tasks.json read (or unchanged) and reconciled at `date`.
        case updated
        case noTasksFile
        case tokenNotAccepted
        case tokenExpired
        case offline
        /// tasks.json's version is higher than this app reads.
        case newerVersion
        /// tasks.json isn't valid JSON or breaks the contract: nothing was changed.
        case badFile
        /// Rate limited, a GitHub error, or the store couldn't save.
        case problem
    }

    var kind: Kind
    /// When this status was reached (the last successful check, for `updated`).
    var date: Date?
    /// The HTTP status behind `problem`, when there was one.
    var code: Int?

    static let notSetUp = VaultStatus(kind: .notSetUp)

    init(kind: Kind, date: Date? = nil, code: Int? = nil) {
        self.kind = kind
        self.date = date
        self.code = code
    }

    init(error: VaultError, at date: Date) {
        switch error {
        case .tokenNotAccepted: self.init(kind: .tokenNotAccepted, date: date)
        case .tokenExpired: self.init(kind: .tokenExpired, date: date)
        case .notFound: self.init(kind: .noTasksFile, date: date)
        case .offline: self.init(kind: .offline, date: date)
        case .conflict: self.init(kind: .problem, date: date, code: 409)
        case let .github(status): self.init(kind: .problem, date: date, code: status)
        case .badResponse: self.init(kind: .problem, date: date)
        }
    }

    /// Whether the line is a problem to look at (an error tint and a warning shape, never colour alone).
    var isProblem: Bool {
        switch kind {
        case .tokenNotAccepted, .tokenExpired, .newerVersion, .badFile, .problem: return true
        case .notSetUp, .connected, .updated, .noTasksFile, .offline: return false
        }
    }

    /// An SF Symbol whose shape carries the meaning (the phone is in greyscale).
    var symbolName: String {
        switch kind {
        case .notSetUp: return "link.badge.plus"
        case .connected: return "link"
        case .updated: return "checkmark.circle.fill"
        case .noTasksFile: return "doc.badge.clock"
        case .tokenNotAccepted: return "xmark.octagon.fill"
        case .tokenExpired: return "clock.badge.xmark"
        case .offline: return "wifi.slash"
        case .newerVersion: return "arrow.up.circle"
        case .badFile: return "exclamationmark.triangle.fill"
        case .problem: return "exclamationmark.triangle"
        }
    }

    /// The status line, worded as the setup note (Desktop, "StickyNotes token setup") quotes it.
    func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch kind {
        case .notSetUp: return "Not set up"
        case .connected: return "Connected"
        case .updated:
            guard let date else { return "Tasks updated" }
            return "Tasks updated \(Self.relativeTime(date, now: now, calendar: calendar))"
        case .noTasksFile: return "No tasks file yet"
        case .tokenNotAccepted: return "Token not accepted"
        case .tokenExpired: return "Token expired"
        case .offline: return "Offline"
        case .newerVersion: return "tasks.json is newer than this app"
        case .badFile: return "tasks.json couldn’t be read"
        case .problem:
            if let code { return "GitHub didn’t answer (\(code))" }
            return "GitHub didn’t answer"
        }
    }

    /// "07:02" today, "yesterday 21:40", otherwise "12 Oct 21:40".
    static func relativeTime(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday \(time)"
        }
        let day = date.formatted(.dateTime.day().month(.abbreviated))
        return "\(day) \(time)"
    }

    // MARK: - Storage

    static let storageKey = "vault_status_v1"

    static func load(from defaults: UserDefaults) -> VaultStatus? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(VaultStatus.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// When the app last sent its habits to the vault, for the Settings footer.
struct VaultHabitsStatus: Codable, Equatable {
    enum Outcome: String, Codable {
        case sent
        /// Two sha conflicts in a row: given up until tomorrow.
        case gaveUp
        case failed
    }

    var outcome: Outcome
    var date: Date
    var dayKey: String

    static let storageKey = "vault_habits_status_v1"

    static func load(from defaults: UserDefaults) -> VaultHabitsStatus? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(VaultHabitsStatus.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
