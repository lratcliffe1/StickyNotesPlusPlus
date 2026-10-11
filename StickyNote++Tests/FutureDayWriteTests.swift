import Foundation
import SwiftData
import XCTest

/// Nothing can be done ahead of its day (step 4 review): `ListService` refuses to complete, skip or
/// bump a row on a day after today, so a future day can't be "completed" in advance. Adding, editing
/// and deleting a future one-off still work.
final class FutureDayWriteTests: XCTestCase {
    private let munich = TestCalendars.munich
    private var context: ModelContext!

    override func setUpWithError() throws {
        context = try StoreTestSupport.makeContext()
    }

    override func tearDown() {
        context = nil
    }

    private func noon(_ key: String) -> Date {
        TestCalendars.date(key, 12)
    }

    private func oneOff(on key: String, title: String = "Book the hut") throws -> Occurrence {
        try XCTUnwrap(ListService.addOneOff(list: .day, dayKey: key, title: title, now: noon("2026-10-14"), context: context))
    }

    func testAFutureRowCantBeCompletedButAPastOneStillCan() throws {
        let future = try oneOff(on: "2026-10-16")
        XCTAssertFalse(try ListService.complete(future, at: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(future.state, .open)
        XCTAssertTrue(try ListService.complete(future, at: noon("2026-10-16"), calendar: munich, context: context), "on its day")

        let past = try oneOff(on: "2026-10-12", title: "Post")
        let endOfDay = TestCalendars.date("2026-10-12", 23, 59)
        XCTAssertTrue(try ListService.complete(past, at: endOfDay, calendar: munich, context: context), "a past day, at its end")
    }

    func testAFutureRowCantBeSkippedOrUnskipped() throws {
        let gym = Item(list: .day, title: "Gym", sortOrder: 0, repeatRule: .daily, startDayKey: "2026-10-14")
        context.insert(gym)
        let tomorrow = ListService.makeOccurrence(for: gym, scheduledOn: "2026-10-15", on: "2026-10-15", now: noon("2026-10-14"), calendar: munich)
        context.insert(tomorrow)
        try context.save()

        XCTAssertFalse(try ListService.skip(tomorrow, todayKey: "2026-10-14", context: context))
        XCTAssertEqual(tomorrow.state, .open)
        XCTAssertTrue(try ListService.skip(tomorrow, todayKey: "2026-10-15", context: context))
        XCTAssertFalse(try ListService.unskip(tomorrow, todayKey: "2026-10-14", context: context), "not from the day before either")
        XCTAssertTrue(try ListService.unskip(tomorrow, todayKey: "2026-10-15", context: context))
    }

    func testAFutureOneOffCantBeBumpedButCanBeEditedAndDeleted() throws {
        let future = try oneOff(on: "2026-10-16")
        XCTAssertNil(try ListService.bump(future, now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(future.state, .open, "a bump would count as done")

        XCTAssertTrue(try ListService.editOneOff(future, title: "Book the hut, Sunday", bumpLimit: .upToDays(3), deadlineDayKey: nil,
                                                 todayKey: "2026-10-14", context: context))
        XCTAssertEqual(future.title, "Book the hut, Sunday")
        XCTAssertTrue(try ListService.deleteOneOff(future, todayKey: "2026-10-14", context: context))
    }

    /// A recurring item's row bumped onto tomorrow waits for tomorrow: it can't be bumped again or
    /// completed today.
    func testARepeatsCopyBumpedOntoTomorrowWaitsForTomorrow() throws {
        let gym = Item(list: .day, title: "Gym", sortOrder: 0, repeatRule: .weekly(on: [4]), startDayKey: "2026-10-14")
        context.insert(gym)
        try context.save()
        try ListService.ensureOccurrences(on: "2026-10-14", context: context, now: noon("2026-10-14"), calendar: munich)
        let wednesday = try XCTUnwrap(ListService.occurrences(on: "2026-10-14", list: .day, context: context).first)

        let thursday = try XCTUnwrap(ListService.bump(wednesday, now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(thursday.dayKey, "2026-10-15")
        XCTAssertNil(try ListService.bump(thursday, now: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertFalse(try ListService.complete(thursday, at: noon("2026-10-14"), calendar: munich, context: context))
        XCTAssertEqual(thursday.state, .open)

        XCTAssertNotNil(try ListService.bump(thursday, now: noon("2026-10-15"), calendar: munich, context: context), "on its day")
    }
}
