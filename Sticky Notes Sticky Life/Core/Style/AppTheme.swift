import SwiftUI

enum AppTheme {
    static let pageBackground = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.97, blue: 1.00),
            Color(red: 0.88, green: 0.92, blue: 0.98),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let stickyNoteBackground = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.97, blue: 0.78),
            Color(red: 0.99, green: 0.93, blue: 0.67),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardSurface = Color.white.opacity(0.74)
    static let cardBorder = Color.white.opacity(0.82)
    static let chipSurface = Color.white.opacity(0.82)
    static let selectedDayTint = Color.blue.opacity(0.18)
    static let todayStroke = Color.blue.opacity(0.82)
}

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fill: AnyShapeStyle
    let border: Color
    let borderWidth: CGFloat
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: borderWidth)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: 12, y: 5)
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = 16,
        fill: AnyShapeStyle = AnyShapeStyle(AppTheme.cardSurface),
        border: Color = AppTheme.cardBorder,
        borderWidth: CGFloat = 1,
        shadowOpacity: Double = 0.08
    ) -> some View {
        modifier(
            GlassCardModifier(
                cornerRadius: cornerRadius,
                fill: fill,
                border: border,
                borderWidth: borderWidth,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
