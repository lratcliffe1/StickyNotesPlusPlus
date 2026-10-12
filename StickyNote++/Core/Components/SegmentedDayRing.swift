import SwiftUI

/// A day's circle, shared by the 7-day ring and the calendar so the two always agree (step 4), and
/// the one place a day or list state is drawn. Use it (with `DayMark`) for any day state; never
/// colour alone.
///
/// One ring split into equal arcs, one per list in use that day, clockwise from 12 o'clock in
/// morning → day → evening order; a single list is a full ring (provisional). Each arc takes its
/// list's `DayMark` shape (step 5, greyscale): filled, partly filled from the arc's start by the
/// share done (`DayMark.fillFraction`: at least a sliver, a miss at most 85%) with a solid edge
/// where the fill stops (fix round 1), an empty outline, or a dashed outline. Colours stay, darker than a plain hue so they keep their contrast
/// in greyscale. With `showsGlyph` the day's ✓ or × sits in the middle (the 7-day ring); the
/// calendar puts its date there and adds a `DayGlyphBadge` on one-list days instead.
struct SegmentedDayRing: View {
    let segments: [DaySegment]
    /// The lists still undecided (today's, before their streak deadline: `DayMark.openListsToday`;
    /// empty on a past day): partly filled or a plain outline, never a miss.
    let openLists: Set<ListKind>
    /// The ring's thickness.
    let lineWidth: CGFloat
    let showsGlyph: Bool

    init(segments: [DaySegment], openLists: Set<ListKind> = [], lineWidth: CGFloat, showsGlyph: Bool = false) {
        self.segments = segments
        self.openLists = openLists
        self.lineWidth = lineWidth
        self.showsGlyph = showsGlyph
    }

    var body: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let span = Self.span(index: index, count: segments.count)
                arc(segment, from: span.start, to: span.end)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if showsGlyph, let glyph = DayMark.glyph(for: marks) {
                GeometryReader { proxy in
                    DayGlyphView(glyph: glyph, size: max(5, proxy.size.width * 0.3))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var marks: [DayMark] {
        segments.map { DayMark.mark(for: $0, openLists: openLists) }
    }

    @ViewBuilder
    private func arc(_ segment: DaySegment, from start: Double, to end: Double) -> some View {
        let mark = DayMark.mark(for: segment, openLists: openLists)
        let whole = RingArc(start: start, end: end, thickness: lineWidth)
        let ink = Self.fillColor(segment.look?.completion.value ?? 0)
        // From the arc's start by the share done, with a solid edge where the fill stops.
        let fraction = DayMark.fillFraction(for: segment, openLists: openLists)
        let part = RingArc(start: start, end: start + (end - start) * fraction, thickness: lineWidth)
        switch mark.fill {
        case .full:
            ZStack {
                whole.fill(ink)
                whole.stroke(Self.outline, lineWidth: 0.75)
            }
        case .partial:
            ZStack {
                whole.fill(Self.track)
                part.fill(ink)
                part.stroke(Self.outline, lineWidth: 1)
                whole.stroke(Self.outline, lineWidth: 1)
            }
        case .empty:
            ZStack {
                whole.fill(Self.track)
                whole.stroke(Self.outline, lineWidth: 1)
            }
        case .dashed:
            // Nothing counted that day for this list: neither progress nor a miss.
            whole.stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1.8, 1.8]))
        }
    }

    private static let track = Color.primary.opacity(0.06)
    private static let outline = Color.primary.opacity(0.7)

    /// Red through to green as the list gets done; darker than a plain hue so it keeps its
    /// contrast against the track in greyscale.
    static func fillColor(_ value: Double) -> Color {
        let clamped = min(max(value, 0), 1)
        return Color(hue: 0.02 + 0.30 * clamped, saturation: 0.85, brightness: 0.62)
    }

    /// Degrees, 0 at 3 o'clock, increasing clockwise on screen. Segment `index` of `count`, starting
    /// at 12 o'clock, with a small gap between segments.
    static func span(index: Int, count: Int) -> (start: Double, end: Double) {
        let share = 360.0 / Double(max(count, 1))
        let gap = count > 1 ? 14.0 : 0
        let start = -90 + share * Double(index) + gap / 2
        return (start, start + share - gap)
    }
}

/// A day's ✓ (every list done) or × (a miss): a bold symbol, so it reads in greyscale.
struct DayGlyphView: View {
    let glyph: DayMark.Glyph
    let size: CGFloat

    var body: some View {
        Image(systemName: glyph == .check ? "checkmark" : "xmark")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}

/// The ✓ or × as a small badge on a calendar day, whose middle holds the date. Shaped like the
/// ↻ `BumpBadge`, at the opposite corner.
struct DayGlyphBadge: View {
    let glyph: DayMark.Glyph
    let diameter: CGFloat

    var body: some View {
        DayGlyphView(glyph: glyph, size: max(6, diameter * 0.30))
            .frame(width: max(10, diameter * 0.52), height: max(10, diameter * 0.52))
            .background(Circle().fill(Color(uiColor: .systemBackground)))
            .overlay(Circle().stroke(Color.primary.opacity(0.7), lineWidth: 0.75))
    }
}

/// One arc of a ring: the band between two circles from `start` to `end` degrees (0 at 3 o'clock,
/// clockwise on screen). Built from points, so the direction never depends on the arc API's
/// flipped-coordinate convention.
struct RingArc: Shape {
    let start: Double
    let end: Double
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 0.5
        let inner = max(0, outer - thickness)
        let steps = max(2, Int(abs(end - start) / 3))
        func point(_ radius: CGFloat, _ step: Int) -> CGPoint {
            let radians = (start + (end - start) * Double(step) / Double(steps)) * .pi / 180
            return CGPoint(x: center.x + radius * CGFloat(cos(radians)), y: center.y + radius * CGFloat(sin(radians)))
        }
        var path = Path()
        path.move(to: point(outer, 0))
        for step in 1...steps {
            path.addLine(to: point(outer, step))
        }
        if abs(end - start) >= 359.9 {
            // A whole ring: two closed circles, the inner one the other way round (a hole under
            // the non-zero rule), so no seam is drawn at 12 o'clock.
            path.closeSubpath()
            path.move(to: point(inner, steps))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: point(inner, step))
        }
        path.closeSubpath()
        return path
    }
}
