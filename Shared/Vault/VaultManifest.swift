import CryptoKit
import SwiftData
import Foundation
import os

/// Deterministic occurrence ids for imported tasks: one row per task per day, so the app and the
/// widget importing the same task for the same day land on the same row (`Occurrence.id` is
/// unique), a past day's row is never reused, and a task back in the file for a later day gets a
/// new row.
///
/// The bonus rule (`ListRules.isBonus`) recognises an imported row by this: a one-off with a
/// name-based (version 5) id. Every other one-off gets a random (version 4) `UUID()`; keep it so.
enum VaultTaskID {
    /// Whether `id` has the name-based (version 5) layout these ids use.
    static func isNameBased(_ id: UUID) -> Bool {
        id.uuid.6 & 0xF0 == 0x50
    }

    /// A name-based UUID of `"vault-task:<id>:<dayKey>"`: the version 5 layout, hashed with
    /// SHA-256 like `OccurrenceID` (the name space is the prefix).
    static func occurrenceID(for taskID: String, dayKey: String) -> UUID {
        let digest = SHA256.hash(data: Data("vault-task:\(taskID):\(dayKey)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// The tasks the app has imported: `tasks.json` id → its rows by day, plus what the file said at
/// the last import (`VaultTask.fingerprint`). Kept in the App Group defaults (shared with the
/// widget), not the store, so no schema changes. Read and written only under `VaultFileLock`
/// when the app and widget may both reconcile, and written only after the store has saved.
struct VaultManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// The task's rows: `dayKey` → occurrence id. A day whose row is gone from the store was
        /// deleted in the app.
        var rows: [String: UUID] = [:]
        /// What the file said at the last import; an edit made in the app lasts until this changes.
        var fingerprint: String?
        /// The day of the task's latest done, skipped or bumped row, or of a row deleted in the
        /// app: the task is settled from then on, unless the file schedules it again (below).
        var settledOn: String?
        /// The latest settling among rows trimmed from `rows` (older than 62 days), so trimming
        /// never unsettles a task that is still listed.
        var settledOnTrimmed: String?
        /// The latest explicit scheduling: the future day the file gives it (moving it earlier moves
        /// this too), or the day it came back to the file after being gone. A settling on or after
        /// it wins; one before it doesn't.
        var scheduledFor: String?
        /// The first day the task was seen missing from the file (nil while it is listed). An entry
        /// is forgotten 62 days after that, never while the task is listed.
        var absentSince: String?
        /// Fix round 2. The days whose `done` entry has been applied (`tasks.json`'s `done`), so
        /// the same entry arriving on every fetch for a week changes nothing after the first time,
        /// and a vault tick un-ticked in the app isn't ticked again. Kept for 7 days. Optional, so a
        /// manifest written before fix round 2 still reads.
        var doneApplied: [String]?
        /// Fix round 2. `dayKey` → the row the vault ticked (or added done) for a `done` entry. Such
        /// rows count as done everywhere, but are left out of `vaultTasksDone`: they are already
        /// deleted from Now.md.
        var tickedByVault: [String: UUID]?
        /// Fix round 2. `dayKey` → the later day the file moved the task to, for today's open row
        /// left skipped when the task moved: Home shows it as "Moved to <day>", with no actions.
        /// Kept in step with the task's earliest later row on every reconcile; "" when it has none
        /// any more ("No longer planned").
        var movedTo: [String: String]?

        init(rows: [String: UUID] = [:], fingerprint: String? = nil, settledOn: String? = nil,
             settledOnTrimmed: String? = nil, scheduledFor: String? = nil, absentSince: String? = nil,
             doneApplied: [String]? = nil, tickedByVault: [String: UUID]? = nil, movedTo: [String: String]? = nil) {
            self.rows = rows
            self.fingerprint = fingerprint
            self.settledOn = settledOn
            self.settledOnTrimmed = settledOnTrimmed
            self.scheduledFor = scheduledFor
            self.absentSince = absentSince
            self.doneApplied = doneApplied
            self.tickedByVault = tickedByVault
            self.movedTo = movedTo
        }

        /// The row on `dayKey` is today's row left behind when the task moved later.
        func isMovedRow(_ row: Occurrence) -> Bool {
            movedTo?[row.dayKey] != nil && rows[row.dayKey] == row.id && row.state == .skipped
        }
    }

    var entries: [String: Entry] = [:]

    static let storageKey = "vault_manifest_v2"

    /// The manifest; empty when there is none yet; nil when one is stored but can't be read (the
    /// reconcile then rebuilds it from the store, `ListService.rebuildVaultManifest`).
    static func load(from defaults: UserDefaults) -> VaultManifest? {
        guard let data = defaults.data(forKey: storageKey) else { return VaultManifest() }
        do {
            return try JSONDecoder().decode(VaultManifest.self, from: data)
        } catch {
            AppLogger.vault.error("Vault manifest unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(to defaults: UserDefaults) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            defaults.set(try encoder.encode(self), forKey: Self.storageKey)
        } catch {
            AppLogger.vault.error("Vault manifest not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Every row id the manifest knows.
    var allRowIDs: [UUID] {
        entries.values.flatMap { $0.rows.values }
    }

    /// Rows left behind when their task moved later (`Entry.movedTo`): row id → the day it moved
    /// to. Home reads it to show "Moved to <day>". Only rows still skipped are moved rows.
    var movedRowDays: [UUID: String] {
        var days: [UUID: String] = [:]
        for entry in entries.values {
            for (day, to) in entry.movedTo ?? [:] {
                if let id = entry.rows[day] { days[id] = to }
            }
        }
        return days
    }

    /// Every row the vault ticked for a `done` entry.
    var tickedByVaultIDs: Set<UUID> {
        Set(entries.values.flatMap { ($0.tickedByVault ?? [:]).values })
    }
}
