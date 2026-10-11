import Foundation
import SwiftData
import XCTest

/// Guards the versioned schema: the app's schema is V1 and a store opens through the migration plan.
final class SchemaVersionTests: XCTestCase {
    func testAppSchemaIsVersionOne() {
        XCTAssertEqual(StickyNotesSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(StickyNotesMigrationPlan.schemas.count, 1)
        XCTAssertEqual(SharedPersistence.appSchema().entities.count, StickyNotesSchemaV1.models.count)
    }

    func testStoreOpensThroughMigrationPlanAndRoundTrips() throws {
        let schema = SharedPersistence.appSchema()
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StickyNotesMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)

        context.insert(DailyTask(date: Date(timeIntervalSince1970: 1_760_000_000), title: "Round trip"))
        try context.save()

        let tasks = try context.fetch(FetchDescriptor<DailyTask>())
        XCTAssertEqual(tasks.map(\.title), ["Round trip"])
    }
}
