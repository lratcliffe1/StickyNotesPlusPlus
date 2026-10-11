import Foundation
import SwiftData

/// Version 1 of the store: the models as they shipped before versioning was added.
///
/// V1 points at the live V1 model classes. V2 only *adds* entities and leaves these four exactly
/// as they are, so they can stay shared. If one of them ever has to change, first copy the V1
/// classes into this enum as nested types (so V1 keeps describing the old store), then change the
/// live class in a new version with its own stage. Never edit a shipped version in place.
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

/// Version 2 (step 2a): the four V1 models unchanged, plus `Item` and `Occurrence`.
/// The V1 tables stay in the store, untouched; `V2Backfill` copies their rows across once.
enum StickyNotesSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            MorningRoutineTemplateItem.self,
            MorningRoutineEntry.self,
            DailyTask.self,
            DayRecord.self,
            Item.self,
            Occurrence.self,
        ]
    }
}

/// Ordered list of store versions and the stages between them.
enum StickyNotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [StickyNotesSchemaV1.self, StickyNotesSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Adding entities only, so SwiftData can do it alone. The row copy is `V2Backfill`.
    static var migrateV1toV2: MigrationStage {
        .lightweight(fromVersion: StickyNotesSchemaV1.self, toVersion: StickyNotesSchemaV2.self)
    }
}
