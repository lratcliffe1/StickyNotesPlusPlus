import Foundation
import SwiftData
import XCTest

/// Guards the versioned schema: V1 is pinned, and stores opened before versioning still open.
final class SchemaVersionTests: XCTestCase {
    /// Step 2a: the app opens the store as V2, reached from V1 by one lightweight stage.
    func testAppSchemaIsVersionTwo() {
        XCTAssertEqual(StickyNotesSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(StickyNotesSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(StickyNotesMigrationPlan.schemas.map { $0.versionIdentifier }, [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0)])
        XCTAssertEqual(StickyNotesMigrationPlan.stages.count, 1)
        XCTAssertEqual(SharedPersistence.appSchema().entities.count, StickyNotesSchemaV2.models.count)
        XCTAssertEqual(Set(SharedPersistence.appSchema().entities.map(\.name)), Set(Schema(versionedSchema: StickyNotesSchemaV2.self).entities.map(\.name)))
    }

    /// V1 points at the live model classes, so editing a model silently changes V1.
    /// If this fails, do not update the expectation: add a V2 and a migration stage instead.
    func testVersionOneShapeIsPinned() {
        let expected: [String: Set<String>] = [
            "MorningRoutineTemplateItem": ["id", "title", "sortOrder", "targetHour", "targetMinute"],
            "MorningRoutineEntry": [
                "id", "date", "dayKey", "titleSnapshot", "sortOrderSnapshot",
                "targetHour", "targetMinute", "isCompleted", "completedAt",
            ],
            "DailyTask": [
                "id", "date", "dayKey", "title", "isCompleted", "completedAt",
                "sortOrder", "bumpCount", "isBumpable", "bumpedTaskID",
            ],
            "DayRecord": ["date", "dayKey", "morningCompletion", "dailyCompletion"],
        ]

        let schema = Schema(versionedSchema: StickyNotesSchemaV1.self)
        var actual: [String: Set<String>] = [:]
        for entity in schema.entities {
            actual[entity.name] = Set(entity.attributes.map(\.name))
            XCTAssertTrue(entity.relationships.isEmpty, "\(entity.name) gained a relationship")
        }
        XCTAssertEqual(actual, expected)
    }

    /// V2 = the four V1 entities, unchanged, plus Item and Occurrence. Pinned like V1:
    /// if this fails, add a V3 and a stage instead of updating the expectation.
    func testVersionTwoShapeIsPinned() {
        let expected: [String: Set<String>] = [
            "MorningRoutineTemplateItem": ["id", "title", "sortOrder", "targetHour", "targetMinute"],
            "MorningRoutineEntry": [
                "id", "date", "dayKey", "titleSnapshot", "sortOrderSnapshot",
                "targetHour", "targetMinute", "isCompleted", "completedAt",
            ],
            "DailyTask": [
                "id", "date", "dayKey", "title", "isCompleted", "completedAt",
                "sortOrder", "bumpCount", "isBumpable", "bumpedTaskID",
            ],
            "DayRecord": ["date", "dayKey", "morningCompletion", "dailyCompletion"],
            "Item": [
                "id", "listRaw", "title", "sortOrder", "repeatKindRaw", "repeatInterval", "repeatWeekdayMask",
                "startDayKey", "endDayKey", "defaultBumpLimitRaw", "defaultBumpLimitDays", "createdAt",
            ],
            "Occurrence": [
                "id", "itemID", "listRaw", "dayKey", "title", "sortOrder", "stateRaw", "completedAt", "createdAt",
                "bumpLimitRaw", "bumpLimitDays", "deadlineDayKey", "bumpedFromID", "bumpedToID", "bumpCount",
                "firstAddedDayKey", "firstAddedTitle", "scheduledDayKey", "periodEndDayKey",
            ],
        ]

        let schema = Schema(versionedSchema: StickyNotesSchemaV2.self)
        var actual: [String: Set<String>] = [:]
        for entity in schema.entities {
            actual[entity.name] = Set(entity.attributes.map(\.name))
            XCTAssertTrue(entity.relationships.isEmpty, "\(entity.name) gained a relationship")
        }
        XCTAssertEqual(actual, expected)
    }

    /// The phone's store was created before versioning existed. It must open through the plan.
    func testStoreCreatedBeforeVersioningReopensThroughMigrationPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaVersionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Legacy.store")

        do {
            let unversioned = Schema([
                MorningRoutineTemplateItem.self,
                MorningRoutineEntry.self,
                DailyTask.self,
                DayRecord.self,
            ])
            let container = try ModelContainer(
                for: unversioned,
                configurations: [ModelConfiguration(schema: unversioned, url: storeURL)]
            )
            let context = ModelContext(container)
            context.insert(DailyTask(date: Date(timeIntervalSince1970: 1_760_000_000), title: "Written before versioning"))
            try context.save()
        }

        let schema = SharedPersistence.appSchema()
        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: StickyNotesMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let tasks = try ModelContext(reopened).fetch(FetchDescriptor<DailyTask>())
        XCTAssertEqual(tasks.map(\.title), ["Written before versioning"])
    }
}
