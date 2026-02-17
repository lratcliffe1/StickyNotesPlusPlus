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
        .background(.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
