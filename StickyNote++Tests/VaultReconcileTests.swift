import Foundation
import SwiftData
import XCTest

/// Reconciling tasks.json into the store (docs/VAULT-API.md, "App reconciliation"), on an in-memory
/// V2 store. Today is Wednesday 14.10.2026 in Munich.
final class VaultReconcileTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let today = "2026-10-14"
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        context = try StoreTestSupport.makeContext()
        (defaults, suiteName) = StoreTestSupport.makeDefaults()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        context = nil
        defaults = nil
    }

    private var now: Date { TestCalendars.date(today, 12) }

    private func task(
        _ id: String,
        _ title: String? = nil,
        list: ListKind = .day,
        day: String = "2026-10-14",
        deadline: String? = nil,
        limit: BumpLimit = .upToDays(3)
    ) -> VaultTask {
        VaultTask(id: id, title: title ?? id, list: list, dayKey: day, deadlineDayKey: deadline, bumpLimit: limit)
    }

    @discardableResult
    private func reconcile(_ tasks: [VaultTask], at date: Date? = nil) throws -> ListService.VaultReconcileResult {
        try ListService.reconcileVaultTasks(tasks, now: date ?? now, calendar: munich, context: context, defaults: defaults)
    }

    private func row(_ id: String) throws -> Occurrence? {
        try ListService.occurrence(id: VaultTaskID.occurrenceID(for: id), context: context)
    }

    private func allRows() throws -> [Occurrence] {
        try StoreTestSupport.all(Occurrence.self, in: context)
    }

    // MARK: - New

    func testNewTasksAreAddedAsOneOffsWithDerivedIDs() throws {
        let result = try reconcile([
            task("deel", "Chase Deel", day: "2026-10-16", deadline: "2026-10-16", limit: .untilDeadline(dayKey: "2026-10-16")),
            task("huts", "Book huts", list: .morning, limit: .cantBump),
        ])
        XCTAssertEqual(result.added, ["deel", "huts"])

        let deel = try XCTUnwrap(row("deel"))
        XCTAssertNil(deel.itemID, "a one-off")
        XCTAssertEqual(deel.title, "Chase Deel")
        XCTAssertEqual(deel.list, .day)
        XCTAssertEqual(deel.dayKey, "2026-10-16")
        XCTAssertEqual(deel.deadlineDayKey, "2026-10-16")
        XCTAssertEqual(deel.bumpLimit, .untilDeadline(dayKey: "2026-10-16"))
        XCTAssertEqual(deel.state, .open)

        let huts = try XCTUnwrap(row("huts"))
        XCTAssertEqual(huts.list, .morning)
        XCTAssertEqual(huts.bumpLimit, .cantBump)

        let manifest = VaultManifest.load(from: defaults)
        XCTAssertEqual(manifest.entries["deel"]?.occurrenceID, VaultTaskID.occurrenceID(for: "deel"))
        XCTAssertEqual(Set(manifest.entries.keys), ["deel", "huts"])
    }

    func testAPastDayLandsOnToday() throws {
        try reconcile([task("old", day: "2026-10-10")])
        XCTAssertEqual(try row("old")?.dayKey, today)
    }

    func testReconcilingTwiceChangesNothing() throws {
        try reconcile([task("a"), task("b", day: "2026-10-20")])
        let second = try reconcile([task("a"), task("b", day: "2026-10-20")])
        XCTAssertFalse(second.changedStore)
        XCTAssertEqual(try allRows().count, 2)
    }

    func testAnotherProcessAddingTheSameTaskLandsOnOneRow() throws {
        try reconcile([task("a")])
        // The widget's manifest write was lost: the derived id still finds the row.
        defaults.removeObject(forKey: VaultManifest.storageKey)
        let result = try reconcile([task("a")])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(try allRows().count, 1)
    }

    // MARK: - Update

    func testAnOpenNeverBumpedRowFollowsTheFile() throws {
        try reconcile([task("a", "Old title", day: "2026-10-15")])
        let result = try reconcile([
            task("a", "New title", list: .evening, day: "2026-10-17", deadline: "2026-10-18", limit: .untilDeadline(dayKey: "2026-10-18")),
        ])
        XCTAssertEqual(result.updated, ["a"])
        let row = try XCTUnwrap(row("a"))
        XCTAssertEqual(row.title, "New title")
        XCTAssertEqual(row.list, .evening)
        XCTAssertEqual(row.dayKey, "2026-10-17")
        XCTAssertEqual(row.deadlineDayKey, "2026-10-18")
        XCTAssertEqual(row.bumpLimit, .untilDeadline(dayKey: "2026-10-18"))
    }

    func testADeadlineCanBeDropped() throws {
        try reconcile([task("a", deadline: "2026-10-18", limit: .untilDeadline(dayKey: "2026-10-18"))])
        try reconcile([task("a", limit: .upToDays(3))])
        let row = try XCTUnwrap(row("a"))
        XCTAssertNil(row.deadlineDayKey)
        XCTAssertEqual(row.bumpLimit, .upToDays(3))
    }

    func testAMovedDateMovesTheRow() throws {
        try reconcile([task("a", day: "2026-10-20")])
        try reconcile([task("a", day: "2026-10-15")])
        XCTAssertEqual(try row("a")?.dayKey, "2026-10-15")
        XCTAssertEqual(try ListService.occurrences(on: "2026-10-20", list: .day, context: context).count, 0)
    }

    func testAnOpenRowLeftOnAPastDayMovesToToday() throws {
        try reconcile([task("a", day: "2026-10-13")], at: TestCalendars.date("2026-10-13", 9))
        XCTAssertEqual(try row("a")?.dayKey, "2026-10-13")
        try reconcile([task("a", day: "2026-10-13")])
        XCTAssertEqual(try row("a")?.dayKey, today)
    }

    func testAnEditMadeInTheAppLastsUntilTheFileChanges() throws {
        try reconcile([task("a", "From Now.md")])
        let row = try XCTUnwrap(row("a"))
        XCTAssertTrue(try ListService.editOneOff(row, title: "My wording", bumpLimit: .unlimited, deadlineDayKey: nil, todayKey: today, context: context))

        try reconcile([task("a", "From Now.md")])
        XCTAssertEqual(row.title, "My wording", "the file didn't change: the edit stays")
        XCTAssertEqual(row.bumpLimit, .unlimited)

        try reconcile([task("a", "Now.md reworded")])
        XCTAssertEqual(row.title, "Now.md reworded", "the file changed: it wins")
    }

    // MARK: - Ticks and bumps win

    func testDoneAndSkippedRowsAreNeverTouched() throws {
        try reconcile([task("done", "Done"), task("skipped", "Skipped")])
        let done = try XCTUnwrap(row("done"))
        try ListService.complete(done, at: now, context: context)
        let skipped = try XCTUnwrap(row("skipped"))
        skipped.state = .skipped
        try context.save()

        let changed = try reconcile([
            task("done", "Renamed", day: "2026-10-20"),
            task("skipped", "Renamed", day: "2026-10-20"),
        ])
        XCTAssertEqual(Set(changed.untouched), ["done", "skipped"])
        XCTAssertEqual(done.title, "Done")
        XCTAssertEqual(done.dayKey, today)
        XCTAssertEqual(done.state, .done)
        XCTAssertEqual(skipped.title, "Skipped")
        XCTAssertEqual(skipped.state, .skipped)

        let gone = try reconcile([])
        XCTAssertTrue(gone.removed.isEmpty, "gone from the file but ticked: kept")
        XCTAssertEqual(try allRows().count, 2)
    }

    func testABumpedRowAndItsChainAreNeverTouched() throws {
        try reconcile([task("a", "Original")])
        let original = try XCTUnwrap(row("a"))
        let copy = try XCTUnwrap(try ListService.bump(original, newTitle: "Retyped", now: now, calendar: munich, context: context))

        let result = try reconcile([task("a", "Renamed in Now.md", day: "2026-10-20")])
        XCTAssertEqual(result.untouched, ["a"])
        XCTAssertEqual(original.state, .bumped)
        XCTAssertEqual(original.title, "Original")
        XCTAssertEqual(copy.title, "Retyped")
        XCTAssertEqual(copy.dayKey, "2026-10-15")

        // Gone from Now.md: the bumped row and its open copy both stay.
        let removal = try reconcile([])
        XCTAssertTrue(removal.removed.isEmpty)
        XCTAssertEqual(try allRows().count, 2)
    }

    func testABumpedChainWhoseCopyIsDoneIsNeverTouched() throws {
        try reconcile([task("a")])
        let original = try XCTUnwrap(row("a"))
        let copy = try XCTUnwrap(try ListService.bump(original, now: now, calendar: munich, context: context))
        try ListService.complete(copy, at: TestCalendars.date("2026-10-15", 10), context: context)

        try reconcile([task("a", "Renamed")])
        try reconcile([])
        XCTAssertEqual(original.state, .bumped)
        XCTAssertEqual(copy.state, .done)
        XCTAssertEqual(try allRows().count, 2)
    }

    // MARK: - Remove

    func testAnOpenTaskGoneFromTheFileIsRemoved() throws {
        try reconcile([task("keep"), task("drop", day: "2026-10-16")])
        let result = try reconcile([task("keep")])
        XCTAssertEqual(result.removed, ["drop"])
        XCTAssertNil(try row("drop"))
        XCTAssertNotNil(try row("keep"))
        XCTAssertNil(VaultManifest.load(from: defaults).entries["drop"])
    }

    func testATaskDeletedInTheAppStaysDeleted() throws {
        try reconcile([task("a")])
        let row = try XCTUnwrap(row("a"))
        XCTAssertTrue(try ListService.deleteOneOff(row, todayKey: today, context: context))

        let result = try reconcile([task("a")])
        XCTAssertEqual(result.deletedInApp, ["a"])
        XCTAssertTrue(result.added.isEmpty)
        XCTAssertEqual(try allRows().count, 0)
    }

    func testOtherOneOffsAreNeverTouched() throws {
        let mine = try XCTUnwrap(try ListService.addOneOff(list: .day, dayKey: today, title: "Typed in the app", now: now, context: context))
        try reconcile([task("a")])
        try reconcile([])
        XCTAssertEqual(try allRows().map(\.id), [mine.id])
    }

    func testImportedTasksSortAfterExistingOneOffs() throws {
        let mine = try XCTUnwrap(try ListService.addOneOff(list: .day, dayKey: today, title: "Mine", now: now, context: context))
        try reconcile([task("a"), task("b")])
        let order = try ListService.occurrences(on: today, list: .day, context: context)
        XCTAssertEqual(order.first?.id, mine.id)
        XCTAssertEqual(Set(order.map(\.sortOrder)).count, 3, "each gets its own place")
    }

    // MARK: - Vault rows

    func testVaultOccurrenceIDsFollowBumpChains() throws {
        try reconcile([task("a")])
        let original = try XCTUnwrap(row("a"))
        let copy = try XCTUnwrap(try ListService.bump(original, now: now, calendar: munich, context: context))
        XCTAssertEqual(try ListService.vaultOccurrenceIDs(context: context, defaults: defaults), [original.id, copy.id])
    }
}
