import XCTest

/// The greyscale shape vocabulary (step 5): every day look, decided or still open today, maps to
/// one shape, driven by the streak status first; on a one-list day every mark differs from every
/// other by shape (fill + glyph) alone.
final class DayMarkTests: XCTestCase {
    private func look(_ status: DayStatus, _ value: Double, neutral: Bool = false) -> ListRules.DayLook {
        ListRules.DayLook(status: status, completion: .init(value: value, isNeutral: neutral))
    }

    // MARK: - State → mark

    func testNothingCountedIsNothingDueOpenOrDecided() {
        for isOpen in [false, true] {
            XCTAssertEqual(DayMark.mark(for: nil, isOpen: isOpen), .nothingDue)
            XCTAssertEqual(DayMark.mark(for: look(.neutral, 0), isOpen: isOpen), .nothingDue)
            XCTAssertEqual(DayMark.mark(for: look(.missed, 0, neutral: true), isOpen: isOpen), .nothingDue)
            XCTAssertEqual(DayMark.mark(for: look(.complete, 0, neutral: true), isOpen: isOpen), .nothingDue)
        }
    }

    func testCompleteIsDoneOpenOrDecided() {
        XCTAssertEqual(DayMark.mark(for: look(.complete, 1), isOpen: false), .done)
        XCTAssertEqual(DayMark.mark(for: look(.complete, 1), isOpen: true), .done)
    }

    /// The step 4 review: a morning finished after its cutoff is `.missed` at 100%. Status comes
    /// first, so it's a miss (half-filled, ×), never the filled "done".
    func testEverythingDoneAfterTheCutoffIsAMissNotDone() {
        XCTAssertEqual(DayMark.mark(for: look(.missed, 1), isOpen: false), .partlyDone)
        XCTAssertEqual(DayMark.mark(for: look(.missed, 1), isOpen: true), .partlyDone, "a late finish is already decided")
        XCTAssertNotEqual(DayMark.mark(for: look(.missed, 1), isOpen: false).fill, DayMark.done.fill)
    }

    func testSomeDoneIsPartlyDoneWhenDecidedAndInProgressWhileOpen() {
        for value in [0.01, 1.0 / 6, 0.5, 0.99] {
            XCTAssertEqual(DayMark.mark(for: look(.missed, value), isOpen: false), .partlyDone, "\(value)")
            XCTAssertEqual(DayMark.mark(for: look(.missed, value), isOpen: true), .inProgress, "\(value)")
        }
    }

    func testNothingDoneIsMissedWhenDecidedAndNotYetWhileOpen() {
        XCTAssertEqual(DayMark.mark(for: look(.missed, 0), isOpen: false), .missed)
        XCTAssertEqual(DayMark.mark(for: look(.missed, 0), isOpen: true), .notYet)
    }

    func testASegmentIsOpenOnlyIfItsListIs() {
        let partly = look(.missed, 0.5)
        let open: Set<ListKind> = [.day, .evening]
        XCTAssertEqual(DayMark.mark(for: DaySegment(list: .morning, look: partly), openLists: open), .partlyDone)
        XCTAssertEqual(DayMark.mark(for: DaySegment(list: .day, look: partly), openLists: open), .inProgress)
        XCTAssertEqual(DayMark.mark(for: DaySegment(list: .day, look: partly), openLists: []), .partlyDone, "a past day")
    }

    // MARK: - Which lists are still open today

    func testTheMorningIsOpenUntilItsStreakDeadline() {
        let munich = TestCalendars.munich
        let setTime = DayRules(morningEnd: .setTime, morningEndMinutes: 9 * 60, eveningStartMinutes: 21 * 60)
        let noCutoff = DayRules(morningEnd: .doneOrSkipped, morningEndMinutes: 9 * 60, eveningStartMinutes: nil)
        let at = { (hour: Int, minute: Int) in TestCalendars.date("2026-10-14", hour, minute) }

        XCTAssertEqual(DayMark.openListsToday(now: at(8, 59), rules: setTime, calendar: munich), [.morning, .day, .evening])
        XCTAssertEqual(DayMark.openListsToday(now: at(9, 0), rules: setTime, calendar: munich), [.day, .evening])
        XCTAssertEqual(DayMark.openListsToday(now: at(11, 59), rules: noCutoff, calendar: munich), [.morning, .day, .evening])
        XCTAssertEqual(DayMark.openListsToday(now: at(12, 0), rules: noCutoff, calendar: munich), [.day, .evening])
        XCTAssertEqual(DayMark.openListsToday(now: at(23, 59), rules: setTime, calendar: munich), [.day, .evening])
    }

    // MARK: - Mark → shape

    func testEachMarksFill() {
        XCTAssertEqual(DayMark.done.fill, .full)
        XCTAssertEqual(DayMark.partlyDone.fill, .half)
        XCTAssertEqual(DayMark.inProgress.fill, .half)
        XCTAssertEqual(DayMark.missed.fill, .empty)
        XCTAssertEqual(DayMark.notYet.fill, .empty)
        XCTAssertEqual(DayMark.nothingDue.fill, .dashed)
    }

    func testOnlyDecidedMissesAreMisses() {
        XCTAssertEqual(DayMark.allCases.filter(\.isMiss), [.partlyDone, .missed])
    }

    func testDayGlyph() {
        XCTAssertNil(DayMark.glyph(for: []))
        XCTAssertEqual(DayMark.glyph(for: [.done]), .check)
        XCTAssertEqual(DayMark.glyph(for: [.done, .done, .done]), .check)
        XCTAssertEqual(DayMark.glyph(for: [.missed]), .cross)
        XCTAssertEqual(DayMark.glyph(for: [.partlyDone]), .cross)
        XCTAssertEqual(DayMark.glyph(for: [.done, .missed]), .cross, "any miss marks the day")
        XCTAssertEqual(DayMark.glyph(for: [.nothingDue, .partlyDone]), .cross)
        XCTAssertNil(DayMark.glyph(for: [.nothingDue]), "nothing done: no ✓")
        XCTAssertNil(DayMark.glyph(for: [.nothingDue, .nothingDue]))
        XCTAssertNil(DayMark.glyph(for: [.inProgress]))
        XCTAssertNil(DayMark.glyph(for: [.notYet]))
        XCTAssertNil(DayMark.glyph(for: [.done, .inProgress]), "a list still open today")
        XCTAssertNil(DayMark.glyph(for: [.done, .notYet]))
    }

    /// The step 4 review: a list with nothing due doesn't take the ✓ away, so a day before the
    /// evening list existed, or with nothing on the day list, still gets it.
    func testNothingDueKeepsTheDaysCheck() {
        XCTAssertEqual(DayMark.glyph(for: [.done, .nothingDue]), .check)
        XCTAssertEqual(DayMark.glyph(for: [.nothingDue, .done, .nothingDue]), .check)
        XCTAssertEqual(DayMark.glyph(for: [.done, .done, .nothingDue]), .check)
    }

    /// On a one-list day (the 7-day ring, or a one-list calendar day) every mark is told apart by
    /// shape alone, so it reads in greyscale. In progress and not yet are today only, where the
    /// missing × separates them from the decided partly done and missed.
    func testEveryMarkHasItsOwnShapeOnAOneListDay() {
        struct Drawn: Hashable {
            let fill: String
            let glyph: String
        }
        let shapes = DayMark.allCases.map { Drawn(fill: "\($0.fill)", glyph: String(describing: DayMark.glyph(for: [$0]))) }
        XCTAssertEqual(Set(shapes).count, DayMark.allCases.count, "\(shapes)")
    }

    // MARK: - Words

    func testWordsSayEachState() {
        XCTAssertEqual(DayMark.words(for: look(.complete, 1), isOpen: false), "done")
        XCTAssertEqual(DayMark.words(for: look(.missed, 1), isOpen: false), "all done after the cutoff, missed")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0.5), isOpen: false), "50 percent done, missed")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0.5), isOpen: true), "50 percent done so far")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0), isOpen: false), "missed")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0), isOpen: true), "nothing done yet")
        XCTAssertEqual(DayMark.words(for: nil, isOpen: false), "nothing due")
    }

    func testTodaysLabelSaysAMorningPastItsDeadlineIsMissed() {
        var british = TestCalendars.munich
        british.locale = Locale(identifier: "en_GB")
        let partly = look(.missed, 0.5)
        let segments = [DaySegment(list: .morning, look: partly), DaySegment(list: .day, look: partly)]
        XCTAssertEqual(
            CalendarRules.accessibilityLabel(dayKey: "2026-10-14", todayKey: "2026-10-14", segments: segments,
                                             hasBump: false, isPlanned: false, todayOpenLists: [.day, .evening],
                                             calendar: british),
            "Today, Wednesday 14 October: morning 50 percent done, missed, day 50 percent done so far"
        )
    }
}
