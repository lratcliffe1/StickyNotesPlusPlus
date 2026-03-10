import SwiftUI
import UIKit

/// Shared sticky-note color palette used by app theming components.
enum StickyNotePalette {
    static var stickyNoteBackground: LinearGradient {
        LinearGradient(
            colors: [
                dynamicColor(
                    light: UIColor(red: 1.00, green: 0.97, blue: 0.78, alpha: 1.0),
                    dark: UIColor(red: 0.33, green: 0.28, blue: 0.13, alpha: 1.0)
                ),
                dynamicColor(
                    light: UIColor(red: 0.99, green: 0.93, blue: 0.67, alpha: 1.0),
                    dark: UIColor(red: 0.22, green: 0.19, blue: 0.09, alpha: 1.0)
                ),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let cardSurface = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.74),
        dark: UIColor.white.withAlphaComponent(0.12)
    )

    static let cardBorder = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.82),
        dark: UIColor.white.withAlphaComponent(0.20)
    )

    static let chipSurface = dynamicColor(
        light: UIColor.white.withAlphaComponent(0.82),
        dark: UIColor.white.withAlphaComponent(0.16)
    )

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}
