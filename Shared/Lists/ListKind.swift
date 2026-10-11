import Foundation

/// The three lists. The raw values are stored in the database: never rename them.
enum ListKind: String, CaseIterable, Codable {
    case morning
    case day
    case evening
}

/// What happened to an occurrence on its day. The raw values are stored: never rename them.
enum OccurrenceState: String, CaseIterable, Codable {
    case open
    case done
    case skipped
    case bumped

    /// A bumped occurrence counts as done for the day it was bumped from (DECISIONS.md).
    var countsAsDone: Bool {
        self == .done || self == .bumped
    }

    /// How far along a row is; used to pick which duplicate to keep (done > bumped > skipped > open).
    var progressRank: Int {
        switch self {
        case .open: return 0
        case .skipped: return 1
        case .bumped: return 2
        case .done: return 3
        }
    }
}

/// How far an occurrence may be bumped (DECISIONS.md, "Bump limits, per item").
enum BumpLimit: Hashable {
    case cantBump
    /// Up to N bumps in total along the chain.
    case upToDays(Int)
    /// May move to any day up to and including the deadline.
    case untilDeadline(dayKey: String)
    /// May move to any day up to the last day of the calendar week it was first added in.
    case endOfWeek
    case unlimited

    /// What a one-off created from step 2a onwards gets unless the caller says otherwise.
    static let defaultForNewOneOffs: BumpLimit = .upToDays(3)

    /// Stored kind names. Never rename them.
    enum Kind: String {
        case cantBump
        case upToDays
        case untilDeadline
        case endOfWeek
        case unlimited
    }

    var kind: Kind {
        switch self {
        case .cantBump: return .cantBump
        case .upToDays: return .upToDays
        case .untilDeadline: return .untilDeadline
        case .endOfWeek: return .endOfWeek
        case .unlimited: return .unlimited
        }
    }

    /// The day count stored alongside the kind (0 unless `upToDays`).
    var storedDays: Int {
        if case let .upToDays(days) = self { return days }
        return 0
    }

    /// The deadline stored alongside the kind (nil unless `untilDeadline`).
    var storedDeadlineDayKey: String? {
        if case let .untilDeadline(dayKey) = self { return dayKey }
        return nil
    }

    /// Rebuilds a limit from its stored parts. Anything unreadable falls back to `cantBump`,
    /// the safe choice: a broken row never lets work slide.
    init(kindRaw: String, days: Int, deadlineDayKey: String?) {
        switch Kind(rawValue: kindRaw) {
        case .cantBump?, nil:
            self = .cantBump
        case .upToDays?:
            self = .upToDays(max(0, days))
        case .untilDeadline?:
            if let deadlineDayKey, !deadlineDayKey.isEmpty {
                self = .untilDeadline(dayKey: deadlineDayKey)
            } else {
                self = .cantBump
            }
        case .endOfWeek?:
            self = .endOfWeek
        case .unlimited?:
            self = .unlimited
        }
    }
}
