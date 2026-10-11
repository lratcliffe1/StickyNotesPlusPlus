import Foundation
import os

/// Every stored day's rules, as plain values, and how a day without its own record is judged.
///
/// - A day with a record uses it.
/// - A day after the first record but without its own (nobody opened the app or widget that day)
///   uses the nearest earlier record.
/// - A day before the first record is from before this build: the old fixed 09:00 cutoff.
struct DayRulesHistory: Equatable {
    /// Rules by `dayKey`.
    var stored: [String: DayRules] = [:]

    func rules(for dayKey: String) -> DayRules {
        if let own = stored[dayKey] { return own }
        // Day keys sort as dates (`YYYY-MM-DD`).
        let earlier = stored.keys.filter { $0 < dayKey }.max()
        return earlier.flatMap { stored[$0] } ?? .legacy
    }
}

/// Reads and writes the per-day rules. They live in the App Group defaults (shared with the
/// widget) as one small JSON dictionary keyed by `dayKey`, so no store schema changes.
///
/// Writes are first-write-wins (`record`), except a settings change, which rewrites today only
/// (`overwrite`). Past days are never rewritten.
enum DayRulesStore {
    static let storageKey = "day_rules_v1"

    static func history(in defaults: UserDefaults) -> DayRulesHistory {
        DayRulesHistory(stored: decoded(from: defaults) ?? [:])
    }

    /// Stores `rules` for `dayKey` unless that day already has a record. Returns whether it wrote.
    @discardableResult
    static func record(_ rules: DayRules, for dayKey: String, in defaults: UserDefaults) -> Bool {
        guard var stored = decoded(from: defaults) else { return false }
        guard stored[dayKey] == nil else { return false }
        stored[dayKey] = rules
        return write(stored, to: defaults)
    }

    /// Replaces `dayKey`'s record (a settings change, for today only).
    @discardableResult
    static func overwrite(_ rules: DayRules, for dayKey: String, in defaults: UserDefaults) -> Bool {
        guard var stored = decoded(from: defaults) else { return false }
        guard stored[dayKey] != rules else { return false }
        stored[dayKey] = rules
        return write(stored, to: defaults)
    }

    // MARK: - Encoding

    /// nil when the data is unreadable: writers then leave it alone, so a bad read can't wipe the
    /// history (readers treat it as empty).
    private static func decoded(from defaults: UserDefaults) -> [String: DayRules]? {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: DayRules].self, from: data)
        } catch {
            AppLogger.persistence.error("Day rules unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func write(_ stored: [String: DayRules], to defaults: UserDefaults) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            defaults.set(try encoder.encode(stored), forKey: storageKey)
            return true
        } catch {
            AppLogger.persistence.error("Day rules not saved: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
