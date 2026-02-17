import SwiftUI

struct HomeHeaderCard: View {
    let morningStreakCount: Int
    let dailyTaskStreakCount: Int
    let sevenDayProgress: [HomeModel.DayProgress]
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button {
            onTap()
        } label: {
            GeometryReader { proxy in
                let metrics = headerMetrics(for: proxy.size.width)

                HStack(alignment: .center, spacing: metrics.horizontalSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        StreakValue(
                            icon: "sun.max.fill",
                            value: morningStreakCount,
                            tint: .yellow
                        )
                        StreakValue(
                            icon: "flame.fill",
                            value: dailyTaskStreakCount,
                            tint: .orange
                        )
                    }
                    .frame(width: metrics.streakWidth, alignment: .leading)

                    HStack(spacing: metrics.daySpacing) {
                        if sevenDayProgress.isEmpty {
                            ForEach(0..<7, id: \.self) { _ in
                                Circle()
                                    .fill(.white.opacity(0.45))
                                    .frame(width: metrics.daySize, height: metrics.daySize)
                            }
                        } else {
                            ForEach(sevenDayProgress) { day in
                                DayProgressCell(
                                    day: day,
                                    isToday: calendar.isDateInToday(day.date),
                                    diameter: metrics.daySize
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 66)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open calendar")
    }

    private func headerMetrics(for width: CGFloat) -> HeaderMetrics {
        let horizontalSpacing: CGFloat = 0
        let streakWidth = max(48, min(62, width * 0.18))
        let rowAvailable = max(120, width - streakWidth - horizontalSpacing)
        let daySpacing = max(1, min(3, rowAvailable * 0.012))
        let daySize = max(15, min(24, (rowAvailable - (daySpacing * 6)) / 7))

        return HeaderMetrics(
            streakWidth: streakWidth,
            daySize: daySize,
            daySpacing: daySpacing,
            horizontalSpacing: horizontalSpacing
        )
    }
}

private struct HeaderMetrics {
    let streakWidth: CGFloat
    let daySize: CGFloat
    let daySpacing: CGFloat
    let horizontalSpacing: CGFloat
}

private struct StreakValue: View {
    let icon: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.white.opacity(0.55))
        .clipShape(Capsule())
    }
}

private struct DayProgressCell: View {
    let day: HomeModel.DayProgress
    let isToday: Bool
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: max(2, diameter * 0.14)) {
            DiagonalSplitCircle(
                morning: day.morning,
                daily: day.daily
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                if isToday {
                    Circle()
                        .stroke(.blue, lineWidth: 2)
                }
            }

            Text(label)
                .font(.system(size: max(8, diameter * 0.38)))
                .foregroundStyle(isToday ? .primary : .secondary)
                .fontWeight(isToday ? .bold : .regular)
        }
        .frame(width: max(diameter + 2, 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        day.date.formatted(.dateTime.weekday(.narrow))
    }

    private var accessibilityLabel: String {
        let morningPercent = Int((day.morning.value * 100).rounded())
        let dailyPercent = Int((day.daily.value * 100).rounded())
        let todayPrefix = isToday ? "Today, " : ""
        return "\(todayPrefix)\(day.date.formatted(date: .abbreviated, time: .omitted)), morning \(morningPercent) percent, daily \(dailyPercent) percent"
    }
}
