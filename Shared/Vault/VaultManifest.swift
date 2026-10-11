import CryptoKit
import Foundation
import os

/// Deterministic occurrence ids for imported tasks: one row per task per day, so the app and the
/// widget importing the same task for the same day land on the same row (`Occurrence.id` is
/// unique), a past day's row is never reused, and a task back in the file for a later day gets a
/// new row.
enum VaultTaskID {
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
        /// The latest explicit scheduling: a future day the file gave it, or the day it came back
        /// to the file after being gone. A settling on or after it wins; one before it doesn't.
        var scheduledFor: String?
        /// The first day the task was seen missing from the file (nil while it is listed). An entry
        /// is forgotten 62 days after that, never while the task is listed.
        var absentSince: String?

        init(rows: [String: UUID] = [:], fingerprint: String? = nil, settledOn: String? = nil,
             scheduledFor: String? = nil, absentSince: String? = nil) {
            self.rows = rows
            self.fingerprint = fingerprint
            self.settledOn = settledOn
            self.scheduledFor = scheduledFor
            self.absentSince = absentSince
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
}
