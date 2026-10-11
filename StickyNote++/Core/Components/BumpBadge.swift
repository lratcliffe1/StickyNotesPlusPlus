import SwiftUI

/// The small ↻ mark on a ring cell or calendar day that had something bumped (DECISIONS.md, 2b).
/// A shape, not a colour, so it reads in greyscale: a bold arrow on a solid disc with an outline.
struct BumpBadge: View {
    let diameter: CGFloat

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: max(6, diameter * 0.34), weight: .black))
            .foregroundStyle(.primary)
            .frame(width: max(10, diameter * 0.56), height: max(10, diameter * 0.56))
            .background(Circle().fill(Color(uiColor: .systemBackground)))
            .overlay(Circle().stroke(Color.primary.opacity(0.7), lineWidth: 0.75))
            .accessibilityHidden(true)
    }
}

extension View {
    /// A long-press menu only when `isEnabled` (read-only days get none).
    @ViewBuilder
    func contextMenu<MenuItems: View>(isEnabled: Bool, @ViewBuilder menuItems: () -> MenuItems) -> some View {
        if isEnabled {
            contextMenu(menuItems: menuItems)
        } else {
            self
        }
    }
}
