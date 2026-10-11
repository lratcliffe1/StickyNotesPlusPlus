import XCTest

/// The greyscale shape vocabulary (step 5): every day look, past and today, maps to one shape, and
/// on a one-list day every mark differs from every other by shape (fill + glyph) alone.
final class DayMarkTests: XCTestCase {
    private func look(_ status: DayStatus, _ value: Double, neutral: Bool = false) -> ListRules.DayLook {
        ListRules.DayLook(status: status, completion: .init(value: value, isNeutral: neutral))
    }

    // MARK: - State → mark

    func testNothingCountedIsNothingDueOnAnyDay() {
        for isToday in [false, true] {
            XCTAssertEqual(DayMark.mark(for: nil, isToday: isToday), .nothingDue)
            XCTAssertEqual(DayMark.mark(for: look(.neutral, 0), isToday: isToday), .nothingDue)
            XCTAssertEqual(DayMark.mark(for: look(.missed, 0, neutral: true), isToday: isToday), .nothingDue)
            XCTAssertEqual(DayMark.mark(for: look(.complete, 0, neutral: true), isToday: isToday), .nothingDue)
        }
    }

    func testCompleteIsDoneOnAnyDay() {
        XCTAssertEqual(DayMark.mark(for: look(.complete, 1), isToday: false), .done)
        XCTAssertEqual(DayMark.mark(for: look(.complete, 1), isToday: true), .done)
    }

    func testEverythingDoneAfterTheCutoffIsDoneLateOnAnyDay() {
        XCTAssertEqual(DayMark.mark(for: look(.missed, 1), isToday: false), .doneLate)
        XCTAssertEqual(DayMark.mark(for: look(.missed, 1), isToday: true), .doneLate, "a late finish is already decided")
    }

    func testSomeDoneIsPartlyDoneOnAPastDayAndInProgressToday() {
        for value in [0.01, 1.0 / 6, 0.5, 0.99] {
            XCTAssertEqual(DayMark.mark(for: look(.missed, value), isToday: false), .partlyDone, "\(value)")
            XCTAssertEqual(DayMark.mark(for: look(.missed, value), isToday: true), .inProgress, "\(value)")
        }
    }

    func testNothingDoneIsMissedOnAPastDayAndNotYetToday() {
        XCTAssertEqual(DayMark.mark(for: look(.missed, 0), isToday: false), .missed)
        XCTAssertEqual(DayMark.mark(for: look(.missed, 0), isToday: true), .notYet)
    }

    // MARK: - Mark → shape

    func testEachMarksFill() {
        XCTAssertEqual(DayMark.done.fill, .full)
        XCTAssertEqual(DayMark.doneLate.fill, .full)
        XCTAssertEqual(DayMark.partlyDone.fill, .half)
        XCTAssertEqual(DayMark.inProgress.fill, .half)
        XCTAssertEqual(DayMark.missed.fill, .empty)
        XCTAssertEqual(DayMark.notYet.fill, .empty)
        XCTAssertEqual(DayMark.nothingDue.fill, .dashed)
    }

    func testOnlyDecidedMissesAreMisses() {
        XCTAssertEqual(DayMark.allCases.filter(\.isMiss), [.doneLate, .partlyDone, .missed])
    }

    func testDayGlyph() {
        XCTAssertNil(DayMark.glyph(for: []))
        XCTAssertEqual(DayMark.glyph(for: [.done]), .check)
        XCTAssertEqual(DayMark.glyph(for: [.done, .done, .done]), .check)
        XCTAssertEqual(DayMark.glyph(for: [.missed]), .cross)
        XCTAssertEqual(DayMark.glyph(for: [.partlyDone]), .cross)
        XCTAssertEqual(DayMark.glyph(for: [.doneLate]), .cross)
        XCTAssertEqual(DayMark.glyph(for: [.done, .missed]), .cross, "any miss marks the day")
        XCTAssertNil(DayMark.glyph(for: [.nothingDue]))
        XCTAssertNil(DayMark.glyph(for: [.inProgress]))
        XCTAssertNil(DayMark.glyph(for: [.notYet]))
        XCTAssertNil(DayMark.glyph(for: [.done, .nothingDue]), "nothing due isn't done: no ✓")
        XCTAssertNil(DayMark.glyph(for: [.done, .inProgress]), "today still open")
    }

    /// On a one-list day (the 7-day ring, or a one-list calendar day) every mark is told apart by
    /// shape alone, so it reads in greyscale.
    func testEveryMarkHasItsOwnShapeOnAOneListDay() {
        struct Drawn: Hashable {
            let fill: String
            let glyph: String
        }
        let shapes = DayMark.allCases.map { Drawn(fill: "\($0.fill)", glyph: "\(String(describing: DayMark.glyph(for: [$0])))") }
        XCTAssertEqual(Set(shapes).count, DayMark.allCases.count, "\(shapes)")
    }

    // MARK: - Words

    func testWordsSayEachState() {
        XCTAssertEqual(DayMark.words(for: look(.complete, 1), isToday: false), "done")
        XCTAssertEqual(DayMark.words(for: look(.missed, 1), isToday: false), "all done after the cutoff, missed")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0.5), isToday: false), "50 percent done, missed")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0.5), isToday: true), "50 percent done so far")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0), isToday: false), "missed")
        XCTAssertEqual(DayMark.words(for: look(.missed, 0), isToday: true), "nothing done yet")
        XCTAssertEqual(DayMark.words(for: nil, isToday: false), "nothing due")
    }
}
