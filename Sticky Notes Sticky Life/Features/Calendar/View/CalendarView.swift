import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \MorningRoutineEntry.date) private var morningEntries: [MorningRoutineEntry]
    @Query(sort: \DailyTask.date) private var dailyTasks: [DailyTask]

    let selectedDay: Date
    let onSelectDay: (Date) -> Void
    let onToday: () -> Void

    @State private var hasScrolledToSelection = false

    var body: some View {
        let progressLookup = dayProgressLookup

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                    ForEach(yearRange, id: \.self) { year in
                        Section {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(1...12, id: \.self) { month in
                                    monthCard(
                                        year: year,
                                        month: month,
                                        progressLookup: progressLookup
                                    )
                                        .id(monthID(year: year, month: month))
                                }
                            }
                            .padding(.horizontal, 16)
                        } header: {
                            yearHeader(year)
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .background(screenBackground.ignoresSafeArea())
            .onAppear {
                hasScrolledToSelection = false
                scrollToInitialMonth(using: proxy)
            }
            .onChange(of: yearRange) { _ in
                scrollToInitialMonth(using: proxy)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        onToday()
                    }
                    .accessibilityLabel("Go to today")
                }
            }
        }
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 1
        return value
    }

    private var selectedDayNormalized: Date {
        HomeModel.normalizedDay(selectedDay, calendar: calendar)
    }

    private var todayNormalized: Date {
        HomeModel.normalizedDay(Date(), calendar: calendar)
    }

    private var initialScrollDay: Date {
        todayNormalized
    }

    private var yearRange: [Int] {
        let currentYear = calendar.component(.year, from: todayNormalized)
        let lowerBound = currentYear - 50
        let upperBound = currentYear + 10
        let initialYear = calendar.component(.year, from: initialScrollDay)

        var minYear = min(currentYear, initialYear)
        var maxYear = max(currentYear, initialYear)

        for entry in morningEntries {
            let normalized = HomeModel.normalizedDay(entry.date, calendar: calendar)
            let year = calendar.component(
                .year,
                from: normalized
            )
            guard year >= lowerBound && year <= upperBound else { continue }
            minYear = min(minYear, year)
            maxYear = max(maxYear, year)
        }

        for task in dailyTasks {
            let normalized = HomeModel.normalizedDay(task.date, calendar: calendar)
            let year = calendar.component(
                .year,
                from: normalized
            )
            guard year >= lowerBound && year <= upperBound else { continue }
            minYear = min(minYear, year)
            maxYear = max(maxYear, year)
        }

        let paddedStart = max(1, minYear - 1)
        let paddedEnd = min(9999, maxYear + 1)
        return Array(paddedStart...paddedEnd)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { offset in
            let index = (calendar.firstWeekday - 1 + offset) % 7
            return symbols[index]
        }
    }

    private var dayProgressLookup: [Date: HomeModel.DayProgress] {
        let morningByDay = Dictionary(grouping: morningEntries) { entry in
            HomeModel.normalizedDay(entry.date, calendar: calendar)
        }
        let dailyByDay = Dictionary(grouping: dailyTasks) { task in
            HomeModel.normalizedDay(task.date, calendar: calendar)
        }

        let allDays = Set(morningByDay.keys).union(dailyByDay.keys)
        var lookup: [Date: HomeModel.DayProgress] = [:]
        lookup.reserveCapacity(allDays.count)

        for day in allDays {
            lookup[day] = HomeModel.DayProgress(
                date: day,
                morning: HomeModel.morningCompletion(entries: morningByDay[day] ?? []),
                daily: HomeModel.dailyCompletion(tasks: dailyByDay[day] ?? [])
            )
        }

        return lookup
    }

    private func yearHeader(_ year: Int) -> some View {
        Text(String(year))
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }

    private func monthCard(
        year: Int,
        month: Int,
        progressLookup: [Date: HomeModel.DayProgress]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthTitle(year: year, month: month))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthSlots(year: year, month: month)) { slot in
                    if let day = slot.date {
                        dayCell(for: day, progressLookup: progressLookup)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 1)
        }
    }

    private func dayCell(
        for date: Date,
        progressLookup: [Date: HomeModel.DayProgress]
    ) -> some View {
        let normalized = HomeModel.normalizedDay(date, calendar: calendar)
        let progress = progressLookup[normalized] ?? emptyProgress(for: normalized)
        let isSelected = normalized == selectedDayNormalized
        let isToday = HomeModel.isToday(normalized, calendar: calendar)

        return Button {
            onSelectDay(normalized)
        } label: {
            VStack(spacing: 4) {
                DiagonalSplitCircle(
                    morning: progress.morning,
                    daily: progress.daily
                )
                .frame(width: 25, height: 25)

                Text("\(calendar.component(.day, from: normalized))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? .blue.opacity(0.2) : .clear)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.blue.opacity(0.8), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(normalized.formatted(date: .abbreviated, time: .omitted)), morning \(Int((progress.morning.value * 100).rounded())) percent, daily \(Int((progress.daily.value * 100).rounded())) percent"
        )
    }

    private func monthSlots(year: Int, month: Int) -> [CalendarSlot] {
        guard
            let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return []
        }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (weekday - calendar.firstWeekday + 7) % 7

        var slots: [CalendarSlot] = []
        slots.reserveCapacity(leadingEmpty + dayRange.count + 7)

        for index in 0..<leadingEmpty {
            slots.append(CalendarSlot(id: "empty-\(year)-\(month)-\(index)", date: nil))
        }

        for day in dayRange {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
            slots.append(CalendarSlot(id: "day-\(year)-\(month)-\(day)", date: date))
        }

        while slots.count % 7 != 0 {
            slots.append(CalendarSlot(id: "tail-\(year)-\(month)-\(slots.count)", date: nil))
        }

        return slots
    }

    private func monthTitle(year: Int, month: Int) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month)/\(year)"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func monthID(year: Int, month: Int) -> String {
        "month-\(year)-\(month)"
    }

    private var initialMonthID: String {
        let components = calendar.dateComponents([.year, .month], from: initialScrollDay)
        let year = components.year ?? calendar.component(.year, from: initialScrollDay)
        let month = components.month ?? calendar.component(.month, from: initialScrollDay)
        return monthID(year: year, month: month)
    }

    private func scrollToInitialMonth(using proxy: ScrollViewProxy) {
        guard !hasScrolledToSelection else { return }
        let target = initialMonthID

        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                proxy.scrollTo(target, anchor: .top)
                hasScrolledToSelection = true
            }
        }
    }

    private func emptyProgress(for day: Date) -> HomeModel.DayProgress {
        HomeModel.DayProgress(
            date: day,
            morning: HomeModel.CompletionState(value: 1.0, isImplicitlyComplete: true),
            daily: HomeModel.CompletionState(value: 1.0, isImplicitlyComplete: true)
        )
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private var screenBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.00),
                Color(red: 0.90, green: 0.93, blue: 0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct CalendarSlot: Identifiable {
    let id: String
    let date: Date?
}

#Preview {
    let schema = Schema([
        MorningRoutineEntry.self,
        DailyTask.self
    ])

    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        CalendarView(
            selectedDay: Date(),
            onSelectDay: { _ in },
            onToday: {}
        )
    }
    .modelContainer(container)
}
