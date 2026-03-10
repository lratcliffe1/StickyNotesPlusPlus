import Foundation
import SwiftData
import XCTest

/// Tests for shared daily-task creation semantics used by Home and Settings.
final class DailyTaskMutationServiceTests: XCTestCase {
    func testCreateTaskTrimsTitleAndSetsBumpability() throws {
        let context = try makeInMemoryContext()
        let day = Date(timeIntervalSince1970: 1_700_100_000)

        let task = try DailyTaskMutationService.createTask(
            for: day,
            title: "  Test Task  ",
            mustHappenToday: true,
            context: context,
            saveImmediately: true
        )

        XCTAssertEqual(task.title, "Test Task")
        XCTAssertFalse(task.isBumpable)
        XCTAssertEqual(task.sortOrder, -1)
    }

    func testCreateTaskInsertAtTopUsesLowerSortOrder() throws {
        let context = try makeInMemoryContext()
        let day = Date(timeIntervalSince1970: 1_700_100_000)

        _ = try DailyTaskMutationService.createTask(
            for: day,
            title: "First",
            mustHappenToday: false,
            context: context,
            saveImmediately: true
        )
        let topTask = try DailyTaskMutationService.createTask(
            for: day,
            title: "Top",
            mustHappenToday: true,
            context: context,
            saveImmediately: true
        )

        XCTAssertEqual(topTask.sortOrder, -1)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = SharedPersistence.appSchema()
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
