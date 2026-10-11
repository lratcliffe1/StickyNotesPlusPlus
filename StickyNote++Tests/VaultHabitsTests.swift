import Foundation
import SwiftData
import XCTest

/// habits/YYYY-MM.json: built from the app's own rules, merged with the file in the vault.
final class VaultHabitsTests: XCTestCase {
    private let munich = TestCalendars.munich
    private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    private func rows(_ states: [OccurrenceState], on day: String = "2026-10-12") -> [VaultHabits.RowFacts] {
        states.map { VaultHabits.RowFacts(dayKey: day, state: $0) }
    }

    private func look(_ status: DayStatus) -> ListRules.DayLook {
        ListRules.DayLook(status: status, completion: HomeModel.CompletionState(value: 1, isNeutral: false))
    }

    // MARK: - One list on one day

    func testListEntryCountsAndStatus() {
        let entry = VaultHabits.listEntry(rows: rows([.done, .done, .skipped, .bumped, .open]), look: look(.missed), isToday: false)
        XCTAssertEqual(entry, .object([
            "status": .string("missed"), "done": .int(2), "skipped": .int(1), "bumped": .int(1), "total": .int(5),
        ]))
        XCTAssertEqual(VaultHabits.listEntry(rows: rows([.done]), look: look(.complete), isToday: false)?["status"], .string("complete"))
    }

    func testTodayIsOpenUntilItIsComplete() {
        XCTAssertEqual(VaultHabits.listEntry(rows: rows([.done, .open]), look: look(.missed), isToday: true)?["status"], .string("open"))
        XCTAssertEqual(VaultHabits.listEntry(rows: rows([.done]), look: look(.complete), isToday: true)?["status"], .string("complete"))
    }

    func testNothingCountedIsNeutralAndAnUnusedListIsLeftOut() {
        XCTAssertEqual(VaultHabits.listEntry(rows: rows([.skipped, .skipped]), look: nil, isToday: false)?["status"], .string("neutral"))
        XCTAssertNil(VaultHabits.listEntry(rows: [], look: nil, isToday: false))
        // A day nobody opened, judged a miss by what was due: no rows, still missed.
        XCTAssertEqual(VaultHabits.listEntry(rows: [], look: look(.missed), isToday: false)?["status"], .string("missed"))
    }

    // MARK: - The month document

    func testDocumentKeepsTheMonthThroughTheDayAndOmitsUnusedLists() throws {
        let doneAt = TestCalendars.date("2026-10-12", 10, 2)
        let document = VaultHabits.document(
            month: "2026-10",
            through: "2026-10-12",
            todayKey: "2026-10-12",
            lists: [
                .morning: VaultHabits.ListInput(
                    rowsByDay: ["2026-09-30": rows([.done], on: "2026-09-30"), "2026-10-11": rows([.done], on: "2026-10-11"),
                                "2026-10-12": rows([.done, .open]), "2026-10-13": rows([.open], on: "2026-10-13")],
                    looks: ["2026-10-11": look(.complete), "2026-10-12": look(.missed)]
                ),
                .day: VaultHabits.ListInput(rowsByDay: [:], looks: [:]),
            ],
            streaks: [.morning: 12, .day: 3],
            vaultTasksDone: ["2026-10-12": [VaultHabits.DoneTask(id: "deel-chase", title: "Chase Deel", doneAt: doneAt)]],
            updatedAt: TestCalendars.date("2026-10-12", 21, 40),
            timeZone: berlin
        )
        XCTAssertEqual(document["version"], .int(1))
        XCTAssertEqual(document["month"], .string("2026-10"))
        XCTAssertEqual(document["updatedAt"], .string("2026-10-12T21:40:00+02:00"))
        XCTAssertEqual(document["streaks"], .object(["morning": .int(12), "day": .int(3), "evening": .int(0)]))

        let days = try XCTUnwrap(document["days"]?.objectValue)
        XCTAssertEqual(Set(days.keys), ["2026-10-11", "2026-10-12"], "September and days after the 12th are left out")
        XCTAssertEqual(days["2026-10-12"]?["morning"]?["status"], .string("open"))
        XCTAssertNil(days["2026-10-12"]?["day"], "a list not in use is omitted")
        XCTAssertNil(days["2026-10-12"]?["evening"])
        XCTAssertEqual(days["2026-10-12"]?["vaultTasksDone"], .array([.object([
            "id": .string("deel-chase"), "title": .string("Chase Deel"), "doneAt": .string("2026-10-12T10:02:00+02:00"),
        ])]))
        XCTAssertEqual(days["2026-10-11"]?["vaultTasksDone"], .array([]))
    }

    // MARK: - Merging with the vault's copy

    func testMergeKeepsOtherDaysAndUnknownFieldsAndOurDaysWin() throws {
        let existing = Data("""
        { "version": 1, "month": "2026-10", "updatedAt": "old", "note": "kept",
          "streaks": { "morning": 1 },
          "days": { "2026-10-01": { "morning": { "status": "complete" } },
                    "2026-10-12": { "morning": { "status": "open" } } } }
        """.utf8)
        let ours = JSONValue.object([
            "version": .int(1), "month": .string("2026-10"), "updatedAt": .string("new"),
            "streaks": .object(["morning": .int(12)]),
            "days": .object(["2026-10-12": .object(["morning": .object(["status": .string("complete")])])]),
        ])
        let merged = VaultHabits.merge(ours, into: existing)
        XCTAssertEqual(merged["note"], .string("kept"))
        XCTAssertEqual(merged["updatedAt"], .string("new"))
        XCTAssertEqual(merged["streaks"], .object(["morning": .int(12)]))
        XCTAssertEqual(merged["days"]?["2026-10-01"]?["morning"]?["status"], .string("complete"), "the file's other days stay")
        XCTAssertEqual(merged["days"]?["2026-10-12"]?["morning"]?["status"], .string("complete"), "the app's days win")
    }

    func testMergeReplacesAMissingOrUnreadableFile() {
        let ours = JSONValue.object(["version": .int(1)])
        XCTAssertEqual(VaultHabits.merge(ours, into: nil), ours)
        XCTAssertEqual(VaultHabits.merge(ours, into: Data("not json".utf8)), ours)
        XCTAssertEqual(VaultHabits.merge(ours, into: Data("[1, 2]".utf8)), ours)
    }

    func testEncodingIsSortedAndKeepsIntegers() throws {
        let data = try VaultHabits.encode(.object(["b": .int(12), "a": .double(1.5), "c": .bool(true)]))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"b\" : 12"), text)
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"a\"")).lowerBound, try XCTUnwrap(text.range(of: "\"b\"")).lowerBound)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data)["b"], .int(12))
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testCommitMessage() {
        XCTAssertEqual(VaultHabits.commitMessage(for: "2026-10-12"), "StickyNotes: habits 2026-10-12")
    }

    // MARK: - From the store, with the app's rules

    func testDocumentFromTheStoreUsesTheAppsOwnRules() throws {
        let context = try StoreTestSupport.makeContext()
        let (defaults, suiteName) = StoreTestSupport.makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = TestCalendars.date("2026-10-14", 22)

        // Morning: a daily item from the 12th, done by 07:00 except on the 13th (10:00: after the 09:00 cutoff).
        let water = Item(list: .morning, title: "Water", sortOrder: 0, repeatRule: .daily, startDayKey: "2026-10-12")
        context.insert(water)
        for (day, hour) in [("2026-10-12", 7), ("2026-10-13", 10), ("2026-10-14", 7)] {
            context.insert(Occurrence(
                itemID: water.id, list: .morning, dayKey: day, title: "Water", state: .done,
                completedAt: TestCalendars.date(day, hour), scheduledDayKey: day, periodEndDayKey: day
            ))
        }
        // Day: the 12th done, the 13th left open, today one done and one open.
        context.insert(Occurrence(list: .day, dayKey: "2026-10-12", title: "A", state: .done, completedAt: TestCalendars.date("2026-10-12", 12)))
        context.insert(Occurrence(list: .day, dayKey: "2026-10-13", title: "B"))
        context.insert(Occurrence(list: .day, dayKey: "2026-10-14", title: "C", state: .done, completedAt: TestCalendars.date("2026-10-14", 12)))
        context.insert(Occurrence(list: .day, dayKey: "2026-10-14", title: "D"))
        try context.save()
        // An imported task, ticked today.
        try ListService.reconcileVaultTasks(
            [VaultTask(id: "deel", title: "Chase Deel", list: .day, dayKey: "2026-10-14", deadlineDayKey: nil, bumpLimit: .upToDays(3))],
            now: now, calendar: munich, context: context, defaults: defaults
        )
        let imported = try XCTUnwrap(try ListService.occurrence(id: VaultTaskID.occurrenceID(for: "deel"), context: context))
        try ListService.complete(imported, at: TestCalendars.date("2026-10-14", 15), context: context)

        let document = try ListService.vaultHabitsDocument(through: "2026-10-14", now: now, calendar: munich, context: context, defaults: defaults)
        let days = try XCTUnwrap(document["days"]?.objectValue)
        XCTAssertEqual(days["2026-10-12"]?["morning"]?["status"], .string("complete"))
        XCTAssertEqual(days["2026-10-13"]?["morning"]?["status"], .string("missed"), "done after the morning's cutoff")
        XCTAssertEqual(days["2026-10-14"]?["morning"]?["status"], .string("complete"))
        XCTAssertEqual(days["2026-10-12"]?["day"]?["status"], .string("complete"))
        XCTAssertEqual(days["2026-10-13"]?["day"]?["status"], .string("missed"))
        XCTAssertEqual(days["2026-10-14"]?["day"]?["status"], .string("open"))
        XCTAssertEqual(days["2026-10-14"]?["day"]?["done"], .int(2))
        XCTAssertEqual(days["2026-10-14"]?["day"]?["total"], .int(3))
        XCTAssertNil(days["2026-10-14"]?["evening"])
        XCTAssertEqual(days["2026-10-14"]?["vaultTasksDone"]?.arrayCount, 1)
        XCTAssertEqual(days["2026-10-14"]?["vaultTasksDone"], .array([.object([
            "id": .string("deel"), "title": .string("Chase Deel"), "doneAt": .string("2026-10-14T15:00:00+02:00"),
        ])]))

        let history = DayRulesStore.history(in: defaults)
        let morningStreak = try ListService.streakState(for: .morning, through: "2026-10-14", history: history, context: context, calendar: munich)
        XCTAssertEqual(document["streaks"]?["morning"], .int(morningStreak.count), "the same streak Home shows")
    }
}

private extension JSONValue {
    var arrayCount: Int? {
        if case let .array(values) = self { return values.count }
        return nil
    }
}
