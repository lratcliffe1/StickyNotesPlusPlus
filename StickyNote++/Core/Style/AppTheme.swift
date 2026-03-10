import SwiftUI
import UIKit

/// Centralized app color, material, and visual constants for consistent styling.
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

    static let stickyNoteBackground = StickyNotePalette.stickyNoteBackground
    static let cardSurface = StickyNotePalette.cardSurface
    static let cardBorder = StickyNotePalette.cardBorder
    static let chipSurface = StickyNotePalette.chipSurface
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
