import SwiftUI

struct DiagonalSplitCircle: View {
    let morning: HomeModel.CompletionState
    let daily: HomeModel.CompletionState

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
    }

    private func progressColor(for state: HomeModel.CompletionState) -> Color {
        let clamped = min(max(state.value, 0), 1)
        let base = Color(
            hue: 0.02 + (0.30 * clamped),
            saturation: 0.82,
            brightness: 0.94
        )

        if state.isImplicitlyComplete {
            return Color.gray.opacity(0.55)
        }
        return base
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
