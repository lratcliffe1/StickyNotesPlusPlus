import Foundation

/// One task from `tasks.json`, checked and with its defaults filled in (`docs/VAULT-API.md`).
struct VaultTask: Equatable {
    let id: String
    let title: String
    let list: ListKind
    /// The day it appears on, as the file says (the app moves a past day to today).
    let dayKey: String
    let deadlineDayKey: String?
    let bumpLimit: BumpLimit

    /// What the app last imported for this task, to tell a change in the file from an edit made in
    /// the app. The day isn't in it: a past day always moves to today.
    var fingerprint: String {
        [title, list.rawValue, deadlineDayKey ?? "-", bumpLimit.kind.rawValue, String(bumpLimit.storedDays)]
            .joined(separator: "|")
    }
}

/// One entry of `tasks.json`'s optional `done` (fix round 2): a task finished in a Claude session
/// and deleted from Now.md, which the app ticks on `dayKey` at `doneAt` instead of removing.
struct VaultDone: Equatable {
    let id: String
    /// The Munich day of `doneAt`, the day the tick counts for.
    let dayKey: String
    let doneAt: Date
}

/// Reads `tasks.json`. Unknown fields are ignored; a higher `version`, invalid JSON or an invalid
/// task makes the whole file unusable, so a bad file never removes anything. An invalid `done`
/// entry is only ignored on its own: `tasks` still reconciles.
enum VaultTasksFile {
    static let supportedVersion = 1

    /// The contract's days (`dayKey`, `done`'s window) are Munich days, wherever the phone is.
    static var munichCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }
    static let maxTitleLength = 80
    static let maxUpToDays = 14

    enum Decoded: Equatable {
        /// The tasks, and the valid `done` entries: at most one per id (the latest `doneAt`),
        /// none for an id that is also in `tasks`, in file order.
        case tasks([VaultTask], done: [VaultDone])
        /// `version` is higher than this app reads.
        case newerVersion(Int)
        /// Not valid JSON, or not the shape the contract describes (the reason is for the log only).
        case invalid(String)
    }

    private struct File: Decodable {
        let version: Int
        let tasks: [RawTask]
    }

    private struct RawTask: Decodable {
        let id: String
        let title: String
        let list: String?
        let dayKey: String
        let deadlineDayKey: String?
        let bumpLimit: RawBumpLimit?
    }

    private struct RawBumpLimit: Decodable {
        let kind: String
        let days: Int?
    }

    private struct VersionOnly: Decodable {
        let version: Int
    }

    /// `done`, read on its own and leniently: a missing or malformed `done` is no entries, and an
    /// entry that isn't an object with the three fields is skipped (`RawDone` never throws).
    private struct DoneOnly: Decodable {
        let done: [RawDone]?
    }

    private struct RawDone: Decodable {
        let id: String?
        let dayKey: String?
        let doneAt: String?

        private enum CodingKeys: String, CodingKey {
            case id, dayKey, doneAt
        }

        init(from decoder: Decoder) {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            id = (try? container?.decodeIfPresent(String.self, forKey: .id)) ?? nil
            dayKey = (try? container?.decodeIfPresent(String.self, forKey: .dayKey)) ?? nil
            doneAt = (try? container?.decodeIfPresent(String.self, forKey: .doneAt)) ?? nil
        }
    }

    static func decode(_ data: Data) -> Decoded {
        // The version first, so a newer file whose shape changed still reads as "newer".
        guard let version = try? JSONDecoder().decode(VersionOnly.self, from: data) else {
            return .invalid("no version")
        }
        guard version.version <= supportedVersion else { return .newerVersion(version.version) }
        guard version.version >= 1 else { return .invalid("version \(version.version)") }

        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            return .invalid("shape")
        }

        var seen = Set<String>()
        var tasks: [VaultTask] = []
        for raw in file.tasks {
            guard isValidID(raw.id) else { return .invalid("id") }
            guard seen.insert(raw.id).inserted else { return .invalid("duplicate id") }
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .invalid("empty title") }
            guard isValidDayKey(raw.dayKey) else { return .invalid("dayKey") }
            if let deadline = raw.deadlineDayKey, !isValidDayKey(deadline) { return .invalid("deadlineDayKey") }

            tasks.append(VaultTask(
                id: raw.id,
                title: String(title.prefix(maxTitleLength)),
                list: raw.list.flatMap(ListKind.init(rawValue:)) ?? .day,
                dayKey: raw.dayKey,
                deadlineDayKey: raw.deadlineDayKey,
                bumpLimit: bumpLimit(raw.bumpLimit, deadline: raw.deadlineDayKey)
            ))
        }
        return .tasks(tasks, done: doneEntries(in: data, excluding: seen))
    }

    /// The valid `done` entries: a valid id that isn't in `tasks`, a real `dayKey` and an ISO 8601
    /// `doneAt` with an offset. Anything else is skipped on its own. Latest `doneAt` per id.
    private static func doneEntries(in data: Data, excluding taskIDs: Set<String>) -> [VaultDone] {
        guard let raw = (try? JSONDecoder().decode(DoneOnly.self, from: data))?.done else { return [] }
        var entries: [VaultDone] = []
        var index: [String: Int] = [:]
        for item in raw {
            guard let id = item.id, isValidID(id), !taskIDs.contains(id),
                  let dayKey = item.dayKey, isValidDayKey(dayKey),
                  let doneAt = item.doneAt.flatMap(parseTimestamp) else { continue }
            let entry = VaultDone(id: id, dayKey: dayKey, doneAt: doneAt)
            if let at = index[id] {
                if doneAt > entries[at].doneAt { entries[at] = entry }
            } else {
                index[id] = entries.count
                entries.append(entry)
            }
        }
        return entries
    }

    /// `2026-10-12T10:40:00+02:00` (or `Z`), with or without fractional seconds.
    static func parseTimestamp(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// The contract's limits. Missing or unreadable: until the deadline if there is one, else up
    /// to 3 days. `untilDeadline` without a deadline falls back the same way.
    private static func bumpLimit(_ raw: RawBumpLimit?, deadline: String?) -> BumpLimit {
        let fallback: BumpLimit = deadline.map { .untilDeadline(dayKey: $0) } ?? .upToDays(3)
        guard let raw else { return fallback }
        switch BumpLimit.Kind(rawValue: raw.kind) {
        case .cantBump?:
            return .cantBump
        case .upToDays?:
            guard let days = raw.days else { return .upToDays(3) }
            return .upToDays(min(maxUpToDays, max(1, days)))
        case .untilDeadline?:
            return fallback
        case .endOfWeek?:
            return .endOfWeek
        case .unlimited?:
            return .unlimited
        case nil:
            return fallback
        }
    }

    /// `[a-z0-9-]{1,64}`.
    static func isValidID(_ id: String) -> Bool {
        guard (1...64).contains(id.unicodeScalars.count) else { return false }
        return id.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }

    private static let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    /// `YYYY-MM-DD`, a real date.
    static func isValidDayKey(_ key: String) -> Bool {
        guard key.count == 10, let ymd = DayMath.parse(key) else { return false }
        guard (1...12).contains(ymd.month), ymd.year >= 2000 else { return false }
        let days = DayMath(calendar: Calendar(identifier: .gregorian)).daysInMonth(year: ymd.year, month: ymd.month)
        return (1...days).contains(ymd.day)
    }
}
