import Foundation

/// A JSON value, so the habits file can be merged without losing anything the app doesn't know.
/// Integers stay integers.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case let .object(object) = self { return object }
        return nil
    }
}

/// Builds and merges `habits/YYYY-MM.json` (`docs/VAULT-API.md`). Pure: the store reads are in
/// `ListService.vaultHabitsDocument`.
enum VaultHabits {
    static let version = 1

    /// What the file needs from one row.
    struct RowFacts: Equatable {
        let dayKey: String
        let state: OccurrenceState

        init(dayKey: String, state: OccurrenceState) {
            self.dayKey = dayKey
            self.state = state
        }

        init(_ row: some OccurrenceFacts) {
            self.init(dayKey: row.dayKey, state: row.state)
        }
    }

    /// One list's rows and day looks for the month.
    struct ListInput {
        var rowsByDay: [String: [RowFacts]]
        var looks: [String: ListRules.DayLook]
    }

    struct DoneTask: Equatable {
        let id: String
        let title: String
        let doneAt: Date?
    }

    /// One list on one day, or nil when the list wasn't in use that day (no rows, nothing missed).
    /// The status is the app's own (`ListRules.dayLooks`); today is `open` until it's complete.
    static func listEntry(rows: [RowFacts], look: ListRules.DayLook?, isToday: Bool) -> JSONValue? {
        guard !rows.isEmpty || look != nil else { return nil }
        let status: String
        switch look?.status {
        case .complete?: status = "complete"
        case .missed?: status = isToday ? "open" : "missed"
        case .neutral?, nil:
            let anyOpen = rows.contains(where: { $0.state == .open })
            status = isToday && anyOpen ? "open" : "neutral"
        }
        return .object([
            "status": .string(status),
            "done": .int(rows.filter { $0.state == .done }.count),
            "skipped": .int(rows.filter { $0.state == .skipped }.count),
            "bumped": .int(rows.filter { $0.state == .bumped }.count),
            "total": .int(rows.count),
        ])
    }

    /// The app's month document: each day from the 1st through `through` that has anything.
    static func document(
        month: String,
        through endKey: String,
        todayKey: String,
        lists: [ListKind: ListInput],
        streaks: [ListKind: Int],
        vaultTasksDone: [String: [DoneTask]],
        updatedAt: Date,
        timeZone: TimeZone
    ) -> JSONValue {
        var dayKeys = Set<String>(vaultTasksDone.keys)
        for input in lists.values {
            dayKeys.formUnion(input.rowsByDay.keys)
            dayKeys.formUnion(input.looks.keys)
        }

        var days: [String: JSONValue] = [:]
        for key in dayKeys where key.hasPrefix(month) && key <= endKey {
            var day: [String: JSONValue] = [:]
            for list in ListKind.allCases {
                let input = lists[list]
                if let entry = listEntry(rows: input?.rowsByDay[key] ?? [], look: input?.looks[key], isToday: key == todayKey) {
                    day[list.rawValue] = entry
                }
            }
            let done = vaultTasksDone[key] ?? []
            guard !day.isEmpty || !done.isEmpty else { continue }
            day["vaultTasksDone"] = .array(done.map { task in
                var object: [String: JSONValue] = ["id": .string(task.id), "title": .string(task.title)]
                if let doneAt = task.doneAt {
                    object["doneAt"] = .string(timestamp(doneAt, timeZone: timeZone))
                }
                return .object(object)
            })
            days[key] = .object(day)
        }

        var streakObject: [String: JSONValue] = [:]
        for list in ListKind.allCases {
            streakObject[list.rawValue] = .int(streaks[list] ?? 0)
        }
        return .object([
            "version": .int(version),
            "month": .string(month),
            "updatedAt": .string(timestamp(updatedAt, timeZone: timeZone)),
            "streaks": .object(streakObject),
            "days": .object(days),
        ])
    }

    /// The existing file with the app's document merged in: the app's days win, the file's other
    /// days and any fields the app doesn't know are kept. An unreadable file is replaced.
    static func merge(_ ours: JSONValue, into existing: Data?) -> JSONValue {
        guard
            let existing,
            let theirs = try? JSONDecoder().decode(JSONValue.self, from: existing),
            var merged = theirs.objectValue,
            let oursObject = ours.objectValue
        else { return ours }

        var days = merged["days"]?.objectValue ?? [:]
        for (key, value) in oursObject["days"]?.objectValue ?? [:] {
            days[key] = value
        }
        for (key, value) in oursObject where key != "days" {
            merged[key] = value
        }
        merged["days"] = .object(days)
        return .object(merged)
    }

    /// Whether the vault's file already holds `merged`, apart from `updatedAt` (so a write whose
    /// answer was lost isn't committed again).
    static func sameIgnoringUpdatedAt(_ merged: JSONValue, _ existing: Data) -> Bool {
        guard
            var theirs = (try? JSONDecoder().decode(JSONValue.self, from: existing))?.objectValue,
            var ours = merged.objectValue
        else { return false }
        theirs["updatedAt"] = nil
        ours["updatedAt"] = nil
        return theirs == ours
    }

    /// Pretty, sorted keys, so each commit's diff is just the days that changed.
    static func encode(_ value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    /// `2026-10-12T21:40:03+02:00`, in the app's time zone.
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func commitMessage(for dayKey: String) -> String {
        "StickyNotes: habits \(dayKey)"
    }
}
