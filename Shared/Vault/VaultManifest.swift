import CryptoKit
import Foundation
import os

/// Deterministic occurrence ids for imported tasks, so the app and the widget importing the same
/// task land on the same row (`Occurrence.id` is unique).
enum VaultTaskID {
    /// A name-based UUID of `"vault-task:" + id`: the version 5 layout, hashed with SHA-256 like
    /// `OccurrenceID` (the name space is the prefix).
    static func occurrenceID(for taskID: String) -> UUID {
        let digest = SHA256.hash(data: Data("vault-task:\(taskID)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// The tasks the app has imported: `tasks.json` id → its occurrence, plus what was last imported
/// (`VaultTask.fingerprint`). Kept in the App Group defaults (shared with the widget), not the
/// store, so no schema changes. Written only after the store has saved.
struct VaultManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var occurrenceID: UUID
        /// What the file said at the last import; an edit made in the app lasts until this changes.
        var fingerprint: String?
    }

    var entries: [String: Entry] = [:]

    static let storageKey = "vault_manifest_v1"

    static func load(from defaults: UserDefaults) -> VaultManifest {
        guard let data = defaults.data(forKey: storageKey) else { return VaultManifest() }
        do {
            return try JSONDecoder().decode(VaultManifest.self, from: data)
        } catch {
            AppLogger.vault.error("Vault manifest unreadable: \(error.localizedDescription, privacy: .public)")
            return VaultManifest()
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
}
