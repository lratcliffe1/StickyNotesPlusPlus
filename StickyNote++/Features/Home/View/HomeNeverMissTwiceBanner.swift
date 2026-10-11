import SwiftUI

/// Never-miss-twice warnings on Home, one line per list at risk.
/// Readable in greyscale: the warning icon and bold text carry the meaning, not the colour.
struct HomeNeverMissTwiceBanner: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(line)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
