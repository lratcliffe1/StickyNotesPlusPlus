import SwiftUI
import UIKit

enum AppTheme {
    static let pageBackground = LinearGradient(
        colors: [
            Color(
                light: UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1.0),
                dark: UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
            ),
            Color(
                light: UIColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 1.0),
                dark: UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1.0)
            ),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let stickyNoteBackground = LinearGradient(
        colors: [
            Color(
                light: UIColor(red: 1.00, green: 0.97, blue: 0.78, alpha: 1.0),
                dark: UIColor(red: 0.33, green: 0.28, blue: 0.13, alpha: 1.0)
            ),
            Color(
                light: UIColor(red: 0.99, green: 0.93, blue: 0.67, alpha: 1.0),
                dark: UIColor(red: 0.22, green: 0.19, blue: 0.09, alpha: 1.0)
            ),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardSurface = Color(
        light: UIColor.white.withAlphaComponent(0.74),
        dark: UIColor.white.withAlphaComponent(0.12)
    )
    static let cardBorder = Color(
        light: UIColor.white.withAlphaComponent(0.82),
        dark: UIColor.white.withAlphaComponent(0.20)
    )
    static let chipSurface = Color(
        light: UIColor.white.withAlphaComponent(0.82),
        dark: UIColor.white.withAlphaComponent(0.16)
    )
    static let selectedDayTint = Color(
        light: UIColor.systemBlue.withAlphaComponent(0.18),
        dark: UIColor.systemBlue.withAlphaComponent(0.35)
    )
    static let todayStroke = Color(
        light: UIColor.systemBlue.withAlphaComponent(0.82),
        dark: UIColor.systemBlue.withAlphaComponent(0.72)
    )
    static let progressCircleBase = Color(
        light: UIColor.white.withAlphaComponent(0.45),
        dark: UIColor.white.withAlphaComponent(0.16)
    )
    static let progressCircleDivider = Color(
        light: UIColor.white.withAlphaComponent(0.80),
        dark: UIColor.white.withAlphaComponent(0.32)
    )
    static let progressCircleStroke = Color(
        light: UIColor.white.withAlphaComponent(0.85),
        dark: UIColor.white.withAlphaComponent(0.36)
    )
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
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
