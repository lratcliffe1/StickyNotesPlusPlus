import Foundation
import XCTest

/// tasks.json decoding (docs/VAULT-API.md), deterministic ids and path encoding.
final class VaultTasksFileTests: XCTestCase {
    private func decode(_ json: String) -> VaultTasksFile.Decoded {
        VaultTasksFile.decode(Data(json.utf8))
    }

    private func tasks(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> [VaultTask] {
        guard case let .tasks(tasks) = decode(json) else {
            XCTFail("expected tasks, got \(decode(json))", file: file, line: line)
            return []
        }
        return tasks
    }

    func testDecodesTheContractExample() {
        let decoded = tasks("""
        {
          "version": 1,
          "generatedAt": "2026-10-12T05:00:12Z",
          "sourceCommit": "a63a378f",
          "tasks": [
            { "id": "deel-chase-victoria", "title": "Chase Deel if no answers (case #7612521)", "list": "day",
              "dayKey": "2026-10-14", "deadlineDayKey": "2026-10-14", "bumpLimit": { "kind": "untilDeadline" } },
            { "id": "tmb-huts-booking", "title": "Book TMB huts Days 1–5 (opens today)", "list": "day",
              "dayKey": "2026-10-15", "bumpLimit": { "kind": "cantBump" } }
          ]
        }
        """)
        XCTAssertEqual(decoded, [
            VaultTask(id: "deel-chase-victoria", title: "Chase Deel if no answers (case #7612521)", list: .day,
                      dayKey: "2026-10-14", deadlineDayKey: "2026-10-14", bumpLimit: .untilDeadline(dayKey: "2026-10-14")),
            VaultTask(id: "tmb-huts-booking", title: "Book TMB huts Days 1–5 (opens today)", list: .day,
                      dayKey: "2026-10-15", deadlineDayKey: nil, bumpLimit: .cantBump),
        ])
    }

    func testUnknownFieldsAreIgnored() {
        let decoded = tasks("""
        { "version": 1, "somethingNew": { "a": [1, 2] }, "tasks": [
          { "id": "a", "title": "A", "dayKey": "2026-10-14", "priority": "high", "bumpLimit": { "kind": "endOfWeek", "extra": true } }
        ] }
        """)
        XCTAssertEqual(decoded.map(\.id), ["a"])
        XCTAssertEqual(decoded.first?.bumpLimit, .endOfWeek)
    }

    func testDefaults() {
        let decoded = tasks("""
        { "version": 1, "tasks": [
          { "id": "no-limit", "title": "No limit", "dayKey": "2026-10-14" },
          { "id": "deadline-only", "title": "Deadline", "dayKey": "2026-10-14", "deadlineDayKey": "2026-10-16" },
          { "id": "until-without-deadline", "title": "X", "dayKey": "2026-10-14", "bumpLimit": { "kind": "untilDeadline" } },
          { "id": "up-to-99", "title": "X", "dayKey": "2026-10-14", "bumpLimit": { "kind": "upToDays", "days": 99 } },
          { "id": "up-to-0", "title": "X", "dayKey": "2026-10-14", "bumpLimit": { "kind": "upToDays", "days": 0 } },
          { "id": "unknown-kind", "title": "X", "dayKey": "2026-10-14", "bumpLimit": { "kind": "someday" } },
          { "id": "evening", "title": "X", "list": "evening", "dayKey": "2026-10-14", "bumpLimit": { "kind": "unlimited" } },
          { "id": "unknown-list", "title": "X", "list": "afternoon", "dayKey": "2026-10-14" }
        ] }
        """)
        let byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        XCTAssertEqual(byID["no-limit"]?.list, .day, "list defaults to day")
        XCTAssertEqual(byID["no-limit"]?.bumpLimit, .upToDays(3), "no deadline: up to 3 days")
        XCTAssertEqual(byID["deadline-only"]?.bumpLimit, .untilDeadline(dayKey: "2026-10-16"), "a deadline: until it")
        XCTAssertEqual(byID["until-without-deadline"]?.bumpLimit, .upToDays(3))
        XCTAssertEqual(byID["up-to-99"]?.bumpLimit, .upToDays(14), "clamped to 1–14")
        XCTAssertEqual(byID["up-to-0"]?.bumpLimit, .upToDays(1))
        XCTAssertEqual(byID["unknown-kind"]?.bumpLimit, .upToDays(3))
        XCTAssertEqual(byID["evening"]?.list, .evening)
        XCTAssertEqual(byID["evening"]?.bumpLimit, .unlimited)
        XCTAssertEqual(byID["unknown-list"]?.list, .day)
    }

    func testBadJSONIsInvalid() {
        guard case .invalid = decode("{ \"version\": 1, \"tasks\": [ ") else { return XCTFail("bad JSON") }
        guard case .invalid = decode("[]") else { return XCTFail("not an object") }
        guard case .invalid = decode("{ \"tasks\": [] }") else { return XCTFail("no version") }
        guard case .invalid = decode("{ \"version\": 1 }") else { return XCTFail("no tasks") }
        guard case .invalid = decode("{ \"version\": 0, \"tasks\": [] }") else { return XCTFail("version 0") }
    }

    func testABadTaskMakesTheWholeFileInvalid() {
        let bad = [
            #"{ "id": "Has Caps", "title": "X", "dayKey": "2026-10-14" }"#,
            #"{ "id": "", "title": "X", "dayKey": "2026-10-14" }"#,
            #"{ "id": "a", "title": "   ", "dayKey": "2026-10-14" }"#,
            #"{ "id": "a", "title": "X", "dayKey": "14.10.2026" }"#,
            #"{ "id": "a", "title": "X", "dayKey": "2026-02-30" }"#,
            #"{ "id": "a", "title": "X", "dayKey": "2026-10-14", "deadlineDayKey": "soon" }"#,
            #"{ "id": "a", "title": "X" }"#,
        ]
        for task in bad {
            guard case .invalid = decode("{ \"version\": 1, \"tasks\": [\(task)] }") else {
                return XCTFail("should be invalid: \(task)")
            }
        }
        let duplicate = #"{ "version": 1, "tasks": [ { "id": "a", "title": "X", "dayKey": "2026-10-14" }, { "id": "a", "title": "Y", "dayKey": "2026-10-15" } ] }"#
        guard case .invalid = decode(duplicate) else { return XCTFail("duplicate ids") }
    }

    func testANewerVersionIsReportedNotRead() {
        XCTAssertEqual(decode(#"{ "version": 2, "tasks": [] }"#), .newerVersion(2))
        XCTAssertEqual(decode(#"{ "version": 3, "entirelyNewShape": true }"#), .newerVersion(3))
    }

    func testLongTitlesAreCutTo80AndTrimmed() {
        let long = String(repeating: "x", count: 100)
        let decoded = tasks(#"{ "version": 1, "tasks": [ { "id": "a", "title": "  \#(long)  ", "dayKey": "2026-10-14" } ] }"#)
        XCTAssertEqual(decoded.first?.title.count, 80)
    }

    func testIDRules() {
        XCTAssertTrue(VaultTasksFile.isValidID("deel-chase-7612521"))
        XCTAssertTrue(VaultTasksFile.isValidID(String(repeating: "a", count: 64)))
        XCTAssertFalse(VaultTasksFile.isValidID(String(repeating: "a", count: 65)))
        XCTAssertFalse(VaultTasksFile.isValidID("under_score"))
        XCTAssertFalse(VaultTasksFile.isValidID("ümlaut"))
    }

    // MARK: - Deterministic ids

    func testOccurrenceIDsAreDeterministicAndDistinct() {
        let first = VaultTaskID.occurrenceID(for: "deel-chase-victoria")
        XCTAssertEqual(first, VaultTaskID.occurrenceID(for: "deel-chase-victoria"))
        XCTAssertNotEqual(first, VaultTaskID.occurrenceID(for: "tmb-huts-booking"))
        // Version 5 layout: the version nibble is 5, the variant bits are 10.
        let text = first.uuidString
        XCTAssertEqual(Array(text)[14], "5")
        XCTAssertTrue("89AB".contains(Array(text)[19]))
    }

    // MARK: - Paths

    func testPathEncoding() {
        XCTAssertEqual(VaultAPI.encodedPath("7 Projects/StickyNotes/tasks.json"), "7%20Projects/StickyNotes/tasks.json")
        XCTAssertEqual(VaultAPI.encodedPath(VaultAPI.habitsPath(month: "2026-10")), "7%20Projects/StickyNotes/habits/2026-10.json")
        XCTAssertEqual(
            VaultAPI.contentsURL(for: VaultAPI.tasksPath)?.absoluteString,
            "https://api.github.com/repos/lratcliffe1/Obsidian/contents/7%20Projects/StickyNotes/tasks.json"
        )
        XCTAssertEqual(VaultAPI.encodedPath("a b/c#d/é"), "a%20b/c%23d/%C3%A9")
    }
}
