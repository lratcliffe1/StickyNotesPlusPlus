import SwiftUI

struct HomeNeverMissTwiceBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.badge.clock")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(
            cornerRadius: 14,
            fill: AnyShapeStyle(AppTheme.cardSurface),
            shadowOpacity: 0.02
        )
        .accessibilityElement(children: .combine)
    }
}
