import SwiftUI

/// Reusable split-circle progress indicator for morning vs daily completion.
struct DiagonalSplitCircle: View {
    let morning: HomeModel.CompletionState
    let daily: HomeModel.CompletionState
    let completionTickDiameter: CGFloat?
    let completionTickColor: Color

    init(
        morning: HomeModel.CompletionState,
        daily: HomeModel.CompletionState,
        completionTickDiameter: CGFloat? = nil,
        completionTickColor: Color = .primary
    ) {
        self.morning = morning
        self.daily = daily
        self.completionTickDiameter = completionTickDiameter
        self.completionTickColor = completionTickColor
    }

    private enum CompletionSide {
        case morning
        case daily
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.progressCircleBase)

            Rectangle()
                .fill(progressColor(for: morning))
                .clipShape(DiagonalHalf(topLeftToBottomRightUpper: true))

            Rectangle()
                .fill(progressColor(for: daily))
                .clipShape(DiagonalHalf(topLeftToBottomRightUpper: false))
        }
        .clipShape(Circle())
        .overlay {
            DiagonalLine()
                .stroke(AppTheme.progressCircleDivider, lineWidth: 1)
        }
        .overlay {
            Circle()
                .stroke(AppTheme.progressCircleStroke, lineWidth: 1)
        }
        .overlay {
            if let diameter = completionTickDiameter {
                completionTickOverlay(diameter: diameter)
            }
        }
    }

    private func progressColor(for state: HomeModel.CompletionState) -> Color {
        let clamped = min(max(state.value, 0), 1)
        let base = Color(
            hue: 0.02 + (0.30 * clamped),
            saturation: 0.82,
            brightness: 0.94
        )

        // Nothing counted that day: plain grey, neither progress nor a miss.
        if state.isNeutral {
            return Color.gray.opacity(0.55)
        }
        return base
    }

    @ViewBuilder
    private func completionTickOverlay(diameter: CGFloat) -> some View {
        ZStack {
            if isMorningCompleted {
                completionTick(for: .morning, diameter: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if isDailyCompleted {
                completionTick(for: .daily, diameter: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    private var isMorningCompleted: Bool {
        morning.isComplete
    }

    private var isDailyCompleted: Bool {
        daily.isComplete
    }

    private func completionTick(for side: CompletionSide, diameter: CGFloat) -> some View {
        let tickSize = max(4, diameter * 0.24)
        let inset = diameter * 0.20
        let offsetX = side == .morning ? -inset : inset
        let offsetY = side == .morning ? inset : -inset

        return Image(systemName: "checkmark")
            .font(.system(size: tickSize, weight: .black))
            .foregroundStyle(completionTickColor)
            .offset(x: offsetX, y: offsetY)
    }
}

private struct DiagonalHalf: Shape {
    let topLeftToBottomRightUpper: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if topLeftToBottomRightUpper {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

private struct DiagonalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
