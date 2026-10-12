import Foundation

/// How one list's part of a day is drawn: the greyscale shape vocabulary (DECISIONS.md, 2026-10-11
/// evening, "5: greyscale"). Colours stay; the shape carries the meaning, so every state reads on
/// Liam's greyscale phone. Driven by the look's streak status first, then its share done:
///
/// | Mark | When | Fill | Day glyph |
/// |---|---|---|---|
/// | done | complete | filled | ✓ |
/// | partlyDone | missed, something done (incl. all done after the cutoff) | partial: share done, at most 85% | × |
/// | missed | missed, nothing done | empty | × |
/// | inProgress | still open today, something done | partial: share done | none |
/// | notYet | still open today, nothing done | empty | none |
/// | nothingDue | nothing counted | dashed outline | none |
///
/// A partial arc fills from its start by the share done (`fillFraction`), with a solid edge where
/// the fill stops; any share above 0 shows at least a sliver (`minimumFill`), and a miss is never
/// drawn full (`missCap`), so a late finish at 100% keeps a visible gap beside its × (DECISIONS.md,
/// 2026-10-12, which replaces step 5's "always exactly half"). On a decided day only a filled
/// segment is done: anything less is a miss. Bumped days carry the separate ↻ badge. Pure, so the test target can pin every case; the app draws it with
/// `SegmentedDayRing`.
enum DayMark: Equatable, CaseIterable {
    /// Everything counted was done (or bumped) in time: the streak's "complete".
    case done
    /// A decided miss with something done, including everything done after the morning's cutoff.
    case partlyDone
    /// A decided miss with nothing done.
    case missed
    /// Still open today, something done so far: not decided yet.
    case inProgress
    /// Still open today, nothing done yet: not a miss yet.
    case notYet
    /// Nothing counted that day (nothing due, or all skipped): neither progress nor a miss.
    case nothingDue

    /// The shape of one segment.
    enum Fill: Equatable {
        case full
        /// Filled from the arc's start by the share done (`fillFraction`), with a solid edge where
        /// it stops: never empty, and never full.
        case partial
        case empty
        case dashed
    }

    /// The least of the arc a partial fill covers, so a small share (1 of 10) still shows in greyscale.
    static let minimumFill = 0.1
    /// The most of the arc a decided miss covers, so a miss (even all done after the cutoff) is
    /// never drawn full.
    static let missCap = 0.85

    /// The glyph a whole day carries (in the ring's middle, or a badge on a one-list calendar day).
    enum Glyph: Equatable {
        case check
        case cross
    }

    var fill: Fill {
        switch self {
        case .done: return .full
        case .partlyDone, .inProgress: return .partial
        case .missed, .notYet: return .empty
        case .nothingDue: return .dashed
        }
    }

    /// The day was decided and counts as a miss for the streak.
    var isMiss: Bool {
        self == .partlyDone || self == .missed
    }

    /// The mark for one list on one day, from its look (`ListRules.dayLooks`; nil when nothing
    /// counted). `isOpen`: the list is still undecided (today, before its streak deadline), so an
    /// unfinished list is in progress or not yet, never a miss. A list that's complete is done
    /// whenever it's drawn.
    static func mark(for look: ListRules.DayLook?, isOpen: Bool) -> DayMark {
        guard let look, !look.completion.isNeutral else { return .nothingDue }
        switch look.status {
        case .neutral:
            return .nothingDue
        case .complete:
            return .done
        case .missed:
            let somethingDone = look.completion.value > 0
            if isOpen && look.completion.value < 1 {
                return somethingDone ? .inProgress : .notYet
            }
            return somethingDone ? .partlyDone : .missed
        }
    }

    static func mark(for segment: DaySegment, openLists: Set<ListKind>) -> DayMark {
        mark(for: segment.look, isOpen: openLists.contains(segment.list))
    }

    /// How much of the arc is filled, 0...1, from its start: 1 when done; the share done when in
    /// progress (at least `minimumFill`); the share done when partly done, at least `minimumFill`
    /// and at most `missCap`; 0 when missed, not yet or nothing due.
    static func fillFraction(for look: ListRules.DayLook?, isOpen: Bool) -> Double {
        let share = min(max(look?.completion.value ?? 0, 0), 1)
        switch mark(for: look, isOpen: isOpen) {
        case .done: return 1
        case .inProgress: return max(minimumFill, share)
        case .partlyDone: return min(missCap, max(minimumFill, share))
        case .missed, .notYet, .nothingDue: return 0
        }
    }

    static func fillFraction(for segment: DaySegment, openLists: Set<ListKind>) -> Double {
        fillFraction(for: segment.look, isOpen: openLists.contains(segment.list))
    }

    /// The lists still undecided today at `now`: the day and evening lists count until midnight,
    /// the morning until its streak deadline (its set time, or 12:00 with none). The same deadline
    /// the streak uses (`ListService.deadline`).
    static func openListsToday(now: Date, rules: DayRules, calendar: Calendar = .current) -> Set<ListKind> {
        var open: Set<ListKind> = [.day, .evening]
        if now < rules.morningDeadline(on: now, calendar: calendar) {
            open.insert(.morning)
        }
        return open
    }

    /// The glyph for a whole day: ✓ when every list in use is done or had nothing due, and at
    /// least one is done; × when any list is a miss; otherwise none (nothing due at all, or a list
    /// still open today). No segments, no glyph.
    static func glyph(for marks: [DayMark]) -> Glyph? {
        if marks.contains(where: \.isMiss) { return .cross }
        if marks.contains(.done), marks.allSatisfy({ $0 == .done || $0 == .nothingDue }) { return .check }
        return nil
    }

    /// One list's state in words, for VoiceOver: the verdict first ("missed, 50 percent done"). A
    /// day's lists are joined with "; " (`CalendarRules.accessibilityLabel`), so each reads as one item.
    static func words(for look: ListRules.DayLook?, isOpen: Bool) -> String {
        let value = look?.completion.value ?? 0
        let percent = Int((value * 100).rounded())
        switch mark(for: look, isOpen: isOpen) {
        case .done: return "done"
        case .partlyDone: return value >= 1 ? "missed, all done after the cutoff" : "missed, \(percent) percent done"
        case .missed: return "missed"
        case .inProgress: return "\(percent) percent done so far"
        case .notYet: return "nothing done yet"
        case .nothingDue: return "nothing due"
        }
    }
}
