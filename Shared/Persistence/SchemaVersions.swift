import Foundation
import SwiftData

/// Version 1 of the store: the models as they shipped before versioning was added.
///
/// When the models change, add `StickyNotesSchemaV2` with the new definitions, copy these
/// model classes into this enum as nested types (so V1 keeps describing the old store), and
/// add a stage to `StickyNotesMigrationPlan`. Never edit a shipped version in place.
enum StickyNotesSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            MorningRoutineTemplateItem.self,
            MorningRoutineEntry.self,
            DailyTask.self,
            DayRecord.self,
        ]
    }
}

/// Ordered list of store versions and the stages between them. Empty until V2 exists.
enum StickyNotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [StickyNotesSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
