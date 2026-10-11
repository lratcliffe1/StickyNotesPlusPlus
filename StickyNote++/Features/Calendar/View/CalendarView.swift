import SwiftData
import SwiftUI
import UIKit

/// Read-only calendar surface that visualizes daily morning/daily completion history.
private enum CalendarMonthLayoutMetrics {
    static let titleRowHeight: CGFloat = 22
    static let contentSpacingAfterTitle: CGFloat = 10
    static let weekdayHeaderHeight: CGFloat = 16
    static let dayCellContentHeight: CGFloat = 52
    static let dayCellVerticalPadding: CGFloat = 2
    static let gridRowSpacing: CGFloat = 8
    static let cardVerticalPadding: CGFloat = 24
    static let safetyBuffer: CGFloat = 12
}

struct CalendarView: View {
    @Query(sort: \Occurrence.dayKey) private var occurrences: [Occurrence]
    @Query(sort: \Item.sortOrder) private var items: [Item]

    let selectedDay: Date
    let onSelectDay: (Date) -> Void
    @State private var scrollRequestVersion = 0
    @State private var requestedMonthID: String?
    var body: some View {
        let months = displayMonthDescriptors
        let progressLookup = dayProgressLookup
        let monthProgressByMonthID = monthProgressLookupByMonthID(
            from: progressLookup,
            monthCount: months.count
        )
        let selectedMonthID = monthID(
            year: calendar.component(.year, from: selectedDayNormalized),
            month: calendar.component(.month, from: selectedDayNormalized)
        )
        let todayMonthID = monthID(
            year: calendar.component(.year, from: todayNormalized),
            month: calendar.component(.month, from: todayNormalized)
        )

        ZStack(alignment: .bottomLeading) {
            CalendarCollectionView(
                months: months,
                weekdaySymbols: weekdaySymbols,
                monthProgressByMonthID: monthProgressByMonthID,
                selectedDay: selectedDayNormalized,
                today: todayNormalized,
                initialMonthID: initialMonthID,
                focusedMonthID: requestedMonthID ?? selectedMonthID,
                scrollRequestVersion: scrollRequestVersion,
                onSelectDay: onSelectDay
            )

            Button("Today") {
                requestedMonthID = todayMonthID
                scrollRequestVersion += 1
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1.2)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.leading, 18)
            .padding(.bottom, 16)
        }
        .onChange(of: selectedDayNormalized) { _, _ in
            requestedMonthID = nil
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .ignoresSafeArea(edges: .vertical)
        .toolbar(.hidden, for: .navigationBar)
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
        selectedDayNormalized
    }

    private var yearBounds: ClosedRange<Int> {
        let currentYear = calendar.component(.year, from: todayNormalized)
        let lowerBound = currentYear - 50
        let upperBound = currentYear + 10
        let initialYear = calendar.component(.year, from: selectedDayNormalized)

        // Keep default range tight for smoother scrolling, then expand only as needed for real data.
        var minYear = min(currentYear - 1, initialYear)
        var maxYear = max(currentYear + 1, initialYear)

        // Sorted by day key, so the first and last rows bound the data.
        for occurrence in [occurrences.first, occurrences.last].compactMap({ $0 }) {
            guard let year = DayMath.parse(occurrence.dayKey)?.year else { continue }
            guard year >= lowerBound && year <= upperBound else { continue }
            minYear = min(minYear, year)
            maxYear = max(maxYear, year)
        }

        let paddedStart = max(1, minYear - 1)
        let paddedEnd = min(9999, maxYear + 1)
        return paddedStart...paddedEnd
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { offset in
            let index = (calendar.firstWeekday - 1 + offset) % 7
            return symbols[index]
        }
    }

    private var displayMonthDescriptors: [CalendarMonthDescriptor] {
        Array(yearBounds).flatMap { year in
            (1...12).map { month in
                CalendarMonthDescriptor(
                    id: monthID(year: year, month: month),
                    year: year,
                    month: month
                )
            }
        }
    }

    /// Morning and day lists only; the evening list isn't shown yet.
    private var dayProgressLookup: [Date: HomeModel.DayProgress] {
        let byDayKey = Dictionary(grouping: occurrences, by: \.dayKey)
        // Past days nobody opened, with something due, show as 0% rather than neutral grey.
        let todayKey = HomeModel.dayKey(for: Date())
        func misses(_ list: ListKind) -> Set<String> {
            ListRules.unopenedMisses(
                schedules: items.filter { $0.list == list }.map(\.schedule),
                openedDays: Set(occurrences.filter { $0.list == list }.map(\.dayKey)),
                before: todayKey
            )
        }
        let morningMisses = misses(.morning)
        let dailyMisses = misses(.day)

        var lookup: [Date: HomeModel.DayProgress] = [:]
        lookup.reserveCapacity(byDayKey.count + morningMisses.count + dailyMisses.count)

        for dayKey in Set(byDayKey.keys).union(morningMisses).union(dailyMisses) {
            guard let parsed = HomeModel.date(fromDayKey: dayKey, calendar: calendar) else { continue }
            let day = HomeModel.normalizedDay(parsed, calendar: calendar)
            let rows = byDayKey[dayKey] ?? []
            lookup[day] = HomeModel.DayProgress(
                date: day,
                morning: ListRules.completion(rows.filter { $0.list == .morning }, isUnopenedMiss: morningMisses.contains(dayKey)),
                daily: ListRules.completion(rows.filter { $0.list == .day }, isUnopenedMiss: dailyMisses.contains(dayKey))
            )
        }

        return lookup
    }

    private func monthProgressLookupByMonthID(
        from progressLookup: [Date: HomeModel.DayProgress],
        monthCount: Int
    ) -> [String: [Date: HomeModel.DayProgress]] {
        var grouped: [String: [Date: HomeModel.DayProgress]] = [:]
        grouped.reserveCapacity(monthCount)

        for (day, progress) in progressLookup {
            let normalizedDay = HomeModel.normalizedDay(day, calendar: calendar)
            let year = calendar.component(.year, from: normalizedDay)
            let month = calendar.component(.month, from: normalizedDay)
            let key = monthID(year: year, month: month)
            grouped[key, default: [:]][normalizedDay] = progress
        }

        return grouped
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

}

private struct CalendarMonthDescriptor: Hashable {
    let id: String
    let year: Int
    let month: Int
}

private struct CalendarCollectionView: UIViewRepresentable {
    let months: [CalendarMonthDescriptor]
    let weekdaySymbols: [String]
    let monthProgressByMonthID: [String: [Date: HomeModel.DayProgress]]
    let selectedDay: Date
    let today: Date
    let initialMonthID: String
    let focusedMonthID: String
    let scrollRequestVersion: Int
    let onSelectDay: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectDay: onSelectDay)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 22
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        layout.estimatedItemSize = .zero

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.cellReuseID)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        context.coordinator.collectionView = collectionView
        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.update(
            months: months,
            weekdaySymbols: weekdaySymbols,
            monthProgressByMonthID: monthProgressByMonthID,
            selectedDay: selectedDay,
            today: today,
            initialMonthID: initialMonthID,
            focusedMonthID: focusedMonthID,
            scrollRequestVersion: scrollRequestVersion
        )
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        static let cellReuseID = "CalendarMonthCell"

        weak var collectionView: UICollectionView?
        private let onSelectDay: (Date) -> Void

        private var months: [CalendarMonthDescriptor] = []
        private var weekdaySymbols: [String] = []
        private var monthProgressByMonthID: [String: [Date: HomeModel.DayProgress]] = [:]
        private var selectedDay: Date = Date()
        private var today: Date = Date()
        private var initialMonthID: String = ""
        private var focusedMonthID: String = ""
        private var scrollRequestVersion: Int = 0
        private var hasAnchoredInitialMonth = false
        private var lastFocusedMonthID: String?

        init(onSelectDay: @escaping (Date) -> Void) {
            self.onSelectDay = onSelectDay
        }

        func update(
            months: [CalendarMonthDescriptor],
            weekdaySymbols: [String],
            monthProgressByMonthID: [String: [Date: HomeModel.DayProgress]],
            selectedDay: Date,
            today: Date,
            initialMonthID: String,
            focusedMonthID: String,
            scrollRequestVersion: Int
        ) {
            let didStructureChange =
                self.months != months ||
                self.weekdaySymbols != weekdaySymbols
            let didVisualChange =
                self.monthProgressByMonthID != monthProgressByMonthID ||
                self.selectedDay != selectedDay ||
                self.today != today
            let shouldReload = didStructureChange || didVisualChange
            let previousFocusedMonthID = self.focusedMonthID
            let previousScrollRequestVersion = self.scrollRequestVersion

            self.months = months
            self.weekdaySymbols = weekdaySymbols
            self.monthProgressByMonthID = monthProgressByMonthID
            self.selectedDay = selectedDay
            self.today = today
            self.initialMonthID = initialMonthID
            self.focusedMonthID = focusedMonthID
            self.scrollRequestVersion = scrollRequestVersion

            guard let collectionView else { return }
            if shouldReload {
                collectionView.reloadData()
            }
            if didStructureChange {
                collectionView.collectionViewLayout.invalidateLayout()
            }

            if !hasAnchoredInitialMonth {
                hasAnchoredInitialMonth = true
                scrollToMonth(initialMonthID, in: collectionView, animated: false)
                lastFocusedMonthID = focusedMonthID
                return
            }

            if scrollRequestVersion != previousScrollRequestVersion {
                lastFocusedMonthID = focusedMonthID
                scrollToMonth(focusedMonthID, in: collectionView, animated: true)
                return
            }

            if focusedMonthID != previousFocusedMonthID || focusedMonthID != lastFocusedMonthID {
                lastFocusedMonthID = focusedMonthID
                scrollToMonth(focusedMonthID, in: collectionView, animated: true)
                return
            }
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            months.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.cellReuseID, for: indexPath)
            let month = months[indexPath.item]
            let monthProgress = monthProgressByMonthID[month.id] ?? [:]

            cell.backgroundColor = .clear
            cell.clipsToBounds = true
            cell.contentView.clipsToBounds = true
            cell.contentConfiguration = UIHostingConfiguration {
                CalendarMonthCardView(
                    year: month.year,
                    month: month.month,
                    weekdaySymbols: weekdaySymbols,
                    monthProgressLookup: monthProgress,
                    selectedDay: selectedDay,
                    today: today,
                    onSelectDay: onSelectDay
                )
                .equatable()
            }
            .margins(.all, 0)
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
                return CGSize(width: collectionView.bounds.width, height: 380)
            }

            let month = months[indexPath.item]
            let availableWidth = max(
                collectionView.bounds.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right,
                0
            )
            let monthHeight = deterministicMonthHeight(for: month)
            return CGSize(width: availableWidth, height: monthHeight)
        }

        private func scrollToMonth(_ monthID: String, in collectionView: UICollectionView, animated: Bool) {
            guard let index = months.firstIndex(where: { $0.id == monthID }) else { return }
            let indexPath = IndexPath(item: index, section: 0)

            DispatchQueue.main.async {
                guard collectionView.numberOfItems(inSection: 0) > indexPath.item else { return }
                collectionView.scrollToItem(at: indexPath, at: .top, animated: animated)
            }
        }

        private func deterministicMonthHeight(for month: CalendarMonthDescriptor) -> CGFloat {
            let weekRows = weekRowCount(year: month.year, month: month.month)

            let dayCellTotalHeight =
                CalendarMonthLayoutMetrics.dayCellContentHeight +
                (CalendarMonthLayoutMetrics.dayCellVerticalPadding * 2)
            let dayRowsHeight = CGFloat(weekRows) * dayCellTotalHeight
            let spacingBetweenRows = CGFloat(weekRows) * CalendarMonthLayoutMetrics.gridRowSpacing

            return
                CalendarMonthLayoutMetrics.cardVerticalPadding +
                CalendarMonthLayoutMetrics.titleRowHeight +
                CalendarMonthLayoutMetrics.contentSpacingAfterTitle +
                CalendarMonthLayoutMetrics.weekdayHeaderHeight +
                dayRowsHeight +
                spacingBetweenRows +
                CalendarMonthLayoutMetrics.safetyBuffer
        }

        private func weekRowCount(year: Int, month: Int) -> Int {
            var calendar = Calendar.current
            calendar.firstWeekday = 1

            guard
                let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
            else {
                return 6
            }

            let weekday = calendar.component(.weekday, from: monthStart)
            let leadingEmpty = (weekday - calendar.firstWeekday + 7) % 7
            let slotCount = leadingEmpty + dayRange.count
            return Int(ceil(Double(slotCount) / 7.0))
        }
    }
}

private struct CalendarMonthCardView: View, Equatable {
    let year: Int
    let month: Int
    let weekdaySymbols: [String]
    let monthProgressLookup: [Date: HomeModel.DayProgress]
    let selectedDay: Date
    let today: Date
    let onSelectDay: (Date) -> Void

    static func == (lhs: CalendarMonthCardView, rhs: CalendarMonthCardView) -> Bool {
        lhs.year == rhs.year &&
        lhs.month == rhs.month &&
        lhs.weekdaySymbols == rhs.weekdaySymbols &&
        lhs.monthProgressLookup == rhs.monthProgressLookup &&
        lhs.selectedDay == rhs.selectedDay &&
        lhs.today == rhs.today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(height: CalendarMonthLayoutMetrics.titleRowHeight, alignment: .center)

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: CalendarMonthLayoutMetrics.weekdayHeaderHeight)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthSlots) { slot in
                    if let day = slot.date {
                        dayCell(for: day)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardSurface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 1
        return value
    }

    private var monthTitle: String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return "\(month)/\(year)"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private var monthSlots: [CalendarSlot] {
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

    private func dayCell(for date: Date) -> some View {
        let normalized = HomeModel.normalizedDay(date, calendar: calendar)
        let progress = monthProgressLookup[normalized] ?? emptyProgress(for: normalized)
        let isSelected = normalized == selectedDay
        let isToday = normalized == today
        let circleDiameter: CGFloat = 25

        return Button {
            onSelectDay(normalized)
        } label: {
            VStack(spacing: 4) {
                DiagonalSplitCircle(
                    morning: progress.morning,
                    daily: progress.daily,
                    completionTickDiameter: circleDiameter
                )
                .frame(width: circleDiameter, height: circleDiameter)

                Text("\(calendar.component(.day, from: normalized))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: CalendarMonthLayoutMetrics.dayCellContentHeight)
            .padding(.vertical, CalendarMonthLayoutMetrics.dayCellVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppTheme.selectedDayTint : .clear)
            )
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.todayStroke, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(normalized.formatted(date: .abbreviated, time: .omitted)), morning \(Int((progress.morning.value * 100).rounded())) percent, daily \(Int((progress.daily.value * 100).rounded())) percent"
        )
    }

    private func emptyProgress(for day: Date) -> HomeModel.DayProgress {
        HomeModel.DayProgress(
            date: day,
            morning: .neutral,
            daily: .neutral
        )
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }
}

private struct CalendarSlot: Identifiable {
    let id: String
    let date: Date?
}

#Preview {
    let schema = SharedPersistence.appSchema()

    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        CalendarView(
            selectedDay: Date(),
            onSelectDay: { _ in }
        )
    }
    .modelContainer(container)
}
