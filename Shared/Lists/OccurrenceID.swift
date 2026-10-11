import CryptoKit
import Foundation

/// Deterministic ids for item occurrences, so two processes creating the same occurrence (the app
/// and the widget at midnight) create the same row: `Occurrence.id` is unique, so the second insert
/// lands on the first instead of adding a duplicate.
enum OccurrenceID {
    /// A name-based UUID (version 5 layout, SHA-256) from the item and the day it was scheduled for.
    static func forItem(_ itemID: UUID, scheduledDayKey: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(itemID.uuidString)|\(scheduledDayKey)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
