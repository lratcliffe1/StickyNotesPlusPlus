import SwiftUI

/// Home header summary card showing streak metrics and recent progress.
struct HomeHeaderCard: View {
    let morningStreakCount: Int
    let dailyTaskStreakCount: Int
    let isMorningStreakFrozen: Bool
    let isDailyTaskStreakFrozen: Bool
    /// The evening streak, shown only while the evening list is in use.
    var eveningStreakCount: Int = 0
    var isEveningStreakFrozen: Bool = false
    var showsEveningStreak: Bool = false
    let sevenDayProgress: [HomeModel.DayProgress]
    let selectedDay: Date
    /// "N bumps in 7 days" under the streaks (the ring's days); hidden at 0.
    var bumpsInSevenDays: Int = 0
    /// Today (Home's clock, which the screenshot harness fixes).
    var today: Date = Date()
    /// Today's lists still undecided (`DayMark.openListsToday`): in progress, not missed.
    var todayOpenLists: Set<ListKind> = Set(ListKind.allCases)
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
                        VStack(alignment: .leading, spacing: showsEveningStreak ? 1 : 6) {
                            StreakValue(
                                icon: "sun.max.fill",
                                value: morningStreakCount,
                                isFrozen: isMorningStreakFrozen,
                                tint: .yellow,
                                name: "Morning"
                            )
                            StreakValue(
                                icon: "flame.fill",
                                value: dailyTaskStreakCount,
                                isFrozen: isDailyTaskStreakFrozen,
                                tint: .orange,
                                name: "Daily"
                            )
                            if showsEveningStreak {
                                StreakValue(
                                    icon: "moon.fill",
                                    value: eveningStreakCount,
                                    isFrozen: isEveningStreakFrozen,
                                    tint: .indigo,
                                    name: "Evening"
                                )
                            }
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
                                        isToday: calendar.isDate(day.date, inSameDayAs: today),
                                        todayKey: HomeModel.dayKey(for: today, calendar: calendar),
                                        todayOpenLists: todayOpenLists,
                                        diameter: metrics.daySize
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(height: showsEveningStreak ? 64 : 60)

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
        .accessibilityValue(accessibilitySummary)
    }

    /// The streaks (and bumps) VoiceOver reads on the header button.
    private var accessibilitySummary: String {
        var parts = [
            StreakValue.spoken("Morning", morningStreakCount, isMorningStreakFrozen),
            StreakValue.spoken("Daily", dailyTaskStreakCount, isDailyTaskStreakFrozen),
        ]
        if showsEveningStreak {
            parts.append(StreakValue.spoken("Evening", eveningStreakCount, isEveningStreakFrozen))
        }
        if bumpsInSevenDays > 0 {
            parts.append(bumpsText)
        }
        return parts.joined(separator: ", ")
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
    /// "Morning", "Daily" or "Evening", for VoiceOver.
    let name: String

    static func spoken(_ name: String, _ value: Int, _ isFrozen: Bool) -> String {
        "\(name) streak \(value)\(isFrozen ? ", frozen" : "")"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isFrozen ? AnyShapeStyle(Color(red: 0.10, green: 0.37, blue: 0.57)) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 14, alignment: .leading)

            if isFrozen {
                // Frozen reads by shape, not only the blue: a snowflake after the count.
                Image(systemName: "snowflake")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(name, value, isFrozen))
    }
}

/// One ring day: the same segmented circle as the calendar (lists in use, evening included), or,
/// after today, a plain day with a dot when something is planned.
private struct DayProgressCell: View {
    let day: HomeModel.DayProgress
    let isSelected: Bool
    let isToday: Bool
    let todayKey: String
    let todayOpenLists: Set<ListKind>
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: max(2, diameter * 0.14)) {
            circle
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .top) {
                    // Above the circle, not on it, so it never hides a segment's shape (step 5).
                    if day.hasBump {
                        BumpBadge(diameter: diameter * 0.9)
                            .offset(y: -(BumpBadge.size(for: diameter * 0.9) + 1))
                    }
                }
                .background {
                    if isSelected {
                        Circle()
                            .fill(AppTheme.selectedDayTint)
                            .padding(-2)
                    }
                }

            Text(label)
                .font(.system(size: max(7, diameter * 0.33)))
                .foregroundStyle(isSelected || isToday ? .primary : .secondary)
                .fontWeight(isSelected || isToday ? .bold : .regular)
                .underline(isToday)
        }
        .frame(width: max(diameter + 2, 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var circle: some View {
        if day.isFuture {
            Circle()
                .fill(Color.secondary)
                .frame(width: max(3, diameter * 0.2), height: max(3, diameter * 0.2))
                .opacity(day.isPlanned ? 1 : 0)
        } else {
            // The day's ✓ (every list done, by the streak's verdict) or × (a miss) in the middle.
            SegmentedDayRing(
                segments: day.segments, openLists: isToday ? todayOpenLists : [],
                lineWidth: max(3, diameter * 0.22), showsGlyph: true
            )
        }
    }

    private var label: String {
        day.date.formatted(.dateTime.weekday(.narrow))
    }

    private var accessibilityLabel: String {
        let label = CalendarRules.accessibilityLabel(
            dayKey: day.dayKey,
            todayKey: todayKey,
            segments: day.segments,
            hasBump: day.hasBump,
            isPlanned: day.isPlanned,
            todayOpenLists: todayOpenLists,
            calendar: .current
        )
        return isSelected ? "Selected, \(label)" : label
    }
}
