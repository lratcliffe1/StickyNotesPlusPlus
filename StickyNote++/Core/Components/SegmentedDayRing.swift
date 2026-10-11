import SwiftUI

/// A day's circle, shared by the 7-day ring and the calendar so the two always agree (step 4).
///
/// One ring split into equal arcs, one per list in use that day, clockwise from 12 o'clock in
/// morning → day → evening order; a single list is a full ring (provisional). Each arc fills along
/// its length as far as that list's completion (`ListRules.dayLooks`), so progress reads as length,
/// not only hue: done is a full arc, missed with nothing done an empty outlined arc, and nothing
/// counted a dashed outline. Step 5 adds the full greyscale shape vocabulary.
struct SegmentedDayRing: View {
    let segments: [DaySegment]
    /// The ring's thickness.
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                let span = Self.span(index: index, count: segments.count)
                arc(segment, from: span.start, to: span.end)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func arc(_ segment: DaySegment, from start: Double, to end: Double) -> some View {
        let whole = RingArc(start: start, end: end, thickness: lineWidth)
        if let look = segment.look {
            let value = min(max(look.completion.value, 0), 1)
            ZStack {
                whole.fill(Color.primary.opacity(0.08))
                if value > 0 {
                    RingArc(start: start, end: start + (end - start) * value, thickness: lineWidth)
                        .fill(Self.fillColor(value))
                }
                whole.stroke(Color.primary.opacity(0.55), lineWidth: 0.75)
            }
        } else {
            // Nothing counted that day for this list: neither progress nor a miss.
            whole.stroke(Color.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 0.9, dash: [1.6, 1.6]))
        }
    }

    /// Red through to green as the list gets done; darker than a plain hue so it keeps its
    /// contrast against the track in greyscale.
    static func fillColor(_ value: Double) -> Color {
        Color(hue: 0.02 + 0.30 * value, saturation: 0.85, brightness: 0.70)
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
