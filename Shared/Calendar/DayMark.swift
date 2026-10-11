import Foundation

/// How one list's part of a day is drawn: the greyscale shape vocabulary (DECISIONS.md, 2026-10-11
/// evening, "5: greyscale"). Colours stay; the shape carries the meaning, so every state reads on
/// Liam's greyscale phone:
///
/// | Mark | Fill | Day glyph |
/// |---|---|---|
/// | done | filled | ✓ |
/// | doneLate | filled | × |
/// | partlyDone | half-filled | × |
/// | inProgress (today) | half-filled | none |
/// | missed | empty | × |
/// | notYet (today) | empty | none |
/// | nothingDue | dashed outline | none |
///
/// Bumped days carry the separate ↻ badge. Pure, so the test target can pin every case; the app
/// draws it with `SegmentedDayRing`.
enum DayMark: Equatable, CaseIterable {
    /// Everything counted was done (or bumped) in time: the streak's "complete".
    case done
    /// Everything was done, but after the morning's cutoff: a miss for the streak.
    case doneLate
    /// A decided day with some, not all, done: a miss.
    case partlyDone
    /// Today, some done so far: not decided yet.
    case inProgress
    /// A decided day with nothing done: a miss.
    case missed
    /// Today, nothing done yet: not a miss yet.
    case notYet
    /// Nothing counted that day (nothing due, or all skipped): neither progress nor a miss.
    case nothingDue

    /// The shape of one segment.
    enum Fill: Equatable {
        case full
        /// Exactly half the segment, whatever the share done, so it never reads as empty or full.
        case half
        case empty
        case dashed
    }

    /// The glyph a whole day carries (in the ring's middle, or a badge on a one-list calendar day).
    enum Glyph: Equatable {
        case check
        case cross
    }

    var fill: Fill {
        switch self {
        case .done, .doneLate: return .full
        case .partlyDone, .inProgress: return .half
        case .missed, .notYet: return .empty
        case .nothingDue: return .dashed
        }
    }

    /// The day was decided and counts as a miss for the streak.
    var isMiss: Bool {
        switch self {
        case .doneLate, .partlyDone, .missed: return true
        case .done, .inProgress, .notYet, .nothingDue: return false
        }
    }

    /// The mark for one list on one day, from its look (`ListRules.dayLooks`; nil when nothing
    /// counted). Today isn't decided until it's done: it's in progress (half) if anything is done,
    /// otherwise not yet (a plain outline, not ×), except that everything done after the cutoff
    /// is already decided.
    static func mark(for look: ListRules.DayLook?, isToday: Bool) -> DayMark {
        guard let look, !look.completion.isNeutral else { return .nothingDue }
        switch look.status {
        case .neutral:
            return .nothingDue
        case .complete:
            return .done
        case .missed:
            let value = look.completion.value
            if value >= 1 { return .doneLate }
            if value > 0 { return isToday ? .inProgress : .partlyDone }
            return isToday ? .notYet : .missed
        }
    }

    /// The glyph for a whole day: ✓ when every list in use is done, × when any list is a miss,
    /// otherwise none (nothing due, or today still open). No segments, no glyph.
    static func glyph(for marks: [DayMark]) -> Glyph? {
        guard !marks.isEmpty else { return nil }
        if marks.allSatisfy({ $0 == .done }) { return .check }
        if marks.contains(where: \.isMiss) { return .cross }
        return nil
    }

    /// One list's state in words, for VoiceOver.
    static func words(for look: ListRules.DayLook?, isToday: Bool) -> String {
        let percent = Int(((look?.completion.value ?? 0) * 100).rounded())
        switch mark(for: look, isToday: isToday) {
        case .done: return "done"
        case .doneLate: return "all done after the cutoff, missed"
        case .partlyDone: return "\(percent) percent done, missed"
        case .inProgress: return "\(percent) percent done so far"
        case .missed: return "missed"
        case .notYet: return "nothing done yet"
        case .nothingDue: return "nothing due"
        }
    }
}
