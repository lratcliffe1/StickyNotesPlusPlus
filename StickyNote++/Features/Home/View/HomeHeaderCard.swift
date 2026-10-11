import SwiftUI

/// Home header summary card showing streak metrics and recent progress.
struct HomeHeaderCard: View {
    let morningStreakCount: Int
    let dailyTaskStreakCount: Int
    let isMorningStreakFrozen: Bool
    let isDailyTaskStreakFrozen: Bool
    let sevenDayProgress: [HomeModel.DayProgress]
    let selectedDay: Date
    /// "N bumps in 7 days" under the streaks (the ring's days); hidden at 0.
    var bumpsInSevenDays: Int = 0
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { proxy in
                    let metrics = headerMetrics(for: proxy.size.width)

                    HStack(alignment: .center, spacing: metrics.horizontalSpacing) {
                        VStack(alignment: .leading, spacing: 6) {
                            StreakValue(
                                icon: "sun.max.fill",
                                value: morningStreakCount,
                                isFrozen: isMorningStreakFrozen,
                                tint: .yellow
                            )
                            StreakValue(
                                icon: "flame.fill",
                                value: dailyTaskStreakCount,
                                isFrozen: isDailyTaskStreakFrozen,
                                tint: .orange
                            )
                        }
                        .frame(width: metrics.streakWidth, alignment: .leading)

                        HStack(spacing: metrics.daySpacing) {
                            if sevenDayProgress.isEmpty {
                                ForEach(0..<7, id: \.self) { _ in
                                    Circle()
                                        .fill(AppTheme.progressCircleBase)
                                        .frame(width: metrics.daySize, height: metrics.daySize)
                                }
                            } else {
                                ForEach(sevenDayProgress) { day in
                                    DayProgressCell(
                                        day: day,
                                        isSelected: calendar.isDate(day.date, inSameDayAs: selectedDay),
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
                .frame(height: 60)

                if bumpsInSevenDays > 0 {
                    Label(bumpsText, systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0.05)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open calendar")
        .accessibilityValue(bumpsInSevenDays > 0 ? bumpsText : "")
    }

    private var bumpsText: String {
        "\(bumpsInSevenDays) \(bumpsInSevenDays == 1 ? "bump" : "bumps") in 7 days"
    }

    private func headerMetrics(for width: CGFloat) -> HeaderMetrics {
        let horizontalSpacing: CGFloat = 0
        let streakWidth = max(56, min(74, width * 0.21))
        let rowAvailable = max(120, width - streakWidth - horizontalSpacing)
        let daySpacing = max(1, min(3, rowAvailable * 0.012))
        let daySize = max(15, min(22, (rowAvailable - (daySpacing * 6)) / 7))

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
    let isFrozen: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            if isFrozen {
                Text("\(value)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color(red: 0.10, green: 0.37, blue: 0.57))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 14)
            } else {
                Text("\(value)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 14, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DayProgressCell: View {
    let day: HomeModel.DayProgress
    let isSelected: Bool
    let isToday: Bool
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: max(2, diameter * 0.14)) {
            DiagonalSplitCircle(
                morning: day.morning,
                daily: day.daily,
                completionTickDiameter: diameter
            )
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .topTrailing) {
                if day.hasBump {
                    BumpBadge(diameter: diameter)
                        .offset(x: diameter * 0.22, y: -diameter * 0.22)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(.primary, lineWidth: 2)
                } else if isToday {
                    Circle()
                        .stroke(.secondary, lineWidth: 1)
                }
            }

            Text(label)
                .font(.system(size: max(7, diameter * 0.33)))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fontWeight(isSelected ? .bold : .regular)
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
        let selectedPrefix = isSelected ? "Selected, " : ""
        let todayPrefix = isToday ? "Today, " : ""
        let bumped = day.hasBump ? ", bumped" : ""
        return "\(selectedPrefix)\(todayPrefix)\(day.date.formatted(date: .abbreviated, time: .omitted)), morning \(morningPercent) percent, daily \(dailyPercent) percent, \(completionSummary)\(bumped)"
    }

    private var isMorningCompleted: Bool {
        day.morning.isComplete
    }

    private var isDailyCompleted: Bool {
        day.daily.isComplete
    }

    private var completionSummary: String {
        switch (isMorningCompleted, isDailyCompleted) {
        case (true, true):
            return "morning and daily complete"
        case (true, false):
            return "morning complete only"
        case (false, true):
            return "daily complete only"
        case (false, false):
            return "not complete"
        }
    }
}
