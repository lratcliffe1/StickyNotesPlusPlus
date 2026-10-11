import Combine
import SwiftData
import SwiftUI

/// The calendar (DECISIONS.md, 2026-10-11 evening, "4: calendar"): months in a vertical scroll, from
/// the first entry's month through the next 12 months, opening on the current month. Weeks start on
/// the locale's first weekday. Past days and today show the segmented day circle (the 7-day ring's
/// own component and rule); later days are plain dates with a dot when something is planned.
/// Tapping a day opens it on Home. Each month is fetched only once it scrolls into view.
struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: CalendarModel
    @ScaledMetric(relativeTo: .footnote) private var scaledDiameter: CGFloat = 36

    let selectedDay: Date
    /// Home's clock (the screenshot harness fixes it).
    let now: () -> Date
    let onSelectDay: (Date) -> Void
    /// The month shown first, as months after the current one (the screenshot harness's
    /// `-uiCalendarMonth`); 0 in the app.
    private let initialMonthOffset: Int

    @MainActor
    init(
        selectedDay: Date,
        now: @escaping () -> Date,
        defaults: UserDefaults,
        context: ModelContext,
        initialMonthOffset: Int = 0,
        onSelectDay: @escaping (Date) -> Void
    ) {
        _model = StateObject(wrappedValue: CalendarModel(now: now(), defaults: defaults, context: context))
        self.selectedDay = selectedDay
        self.now = now
        self.initialMonthOffset = initialMonthOffset
        self.onSelectDay = onSelectDay
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(model.months) { month in
                        CalendarMonthSection(
                            month: month,
                            data: model.loaded[month.id],
                            lists: model.lists,
                            firstEntryDayKey: model.firstEntryDayKey,
                            todayKey: model.todayKey,
                            todayOpenLists: model.todayOpenLists,
                            selectedKey: HomeModel.dayKey(for: selectedDay, calendar: model.calendar),
                            calendar: model.calendar,
                            diameter: min(scaledDiameter, 48),
                            onSelect: select
                        )
                        .id(month.id)
                        // On appearing, and again after each reload while on screen.
                        .task(id: model.generation) { @MainActor in
                            model.load(month, context: modelContext)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear {
                scroll(proxy, toMonthsAfterCurrent: initialMonthOffset, animated: false)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        scroll(proxy, toMonthsAfterCurrent: 0, animated: true)
                    }
                }
            }
        }
        // While on screen, read again at the next boundary, so today's morning stops being drawn
        // as open once its deadline passes (step 5). A fixed clock (the harness) never gets there.
        .task(id: model.nextBoundary) { @MainActor in
            let wait = model.nextBoundary.timeIntervalSince(now())
            guard wait > 0, wait < 2 * 86_400 else { return }
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            model.reload(now: now(), context: modelContext)
        }
        // Back from the background (the widget may have written) or a new day: read again.
        // Deferred a turn so Home's own foreground sync (it refreshes the shared context) runs first.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            DispatchQueue.main.async { model.reload(now: now(), context: modelContext) }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
                .receive(on: DispatchQueue.main)
        ) { _ in
            model.reload(now: now(), context: modelContext)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func scroll(_ proxy: ScrollViewProxy, toMonthsAfterCurrent offset: Int, animated: Bool) {
        guard let target = model.currentMonth?.shifted(by: offset), model.months.contains(target) else { return }
        if animated {
            withAnimation { proxy.scrollTo(target.id, anchor: .top) }
        } else {
            proxy.scrollTo(target.id, anchor: .top)
            // Months above the target are laid out lazily, at estimated heights: settle once more.
            DispatchQueue.main.async {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    private func select(_ dayKey: String) {
        guard let day = HomeModel.date(fromDayKey: dayKey, calendar: model.calendar) else { return }
        onSelectDay(HomeModel.normalizedDay(day, calendar: model.calendar))
    }
}

/// One month: its title, the weekday row and the weeks.
private struct CalendarMonthSection: View {
    let month: CalendarRules.Month
    let data: CalendarModel.MonthData?
    let lists: [ListKind]
    let firstEntryDayKey: String?
    let todayKey: String
    let todayOpenLists: Set<ListKind>
    let selectedKey: String
    let calendar: Calendar
    let diameter: CGFloat
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                let symbols = CalendarRules.weekdaySymbols(calendar: calendar)
                ForEach(symbols.indices, id: \.self) { index in
                    Text(symbols[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                let weeks = CalendarRules.weeks(for: month, calendar: calendar)
                ForEach(weeks.indices, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { slot in
                            if let dayKey = weeks[week][slot] {
                                dayCell(dayKey)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0.04)
    }

    private var title: String {
        CalendarRules.monthTitle(month, calendar: calendar)
    }

    private func dayCell(_ dayKey: String) -> some View {
        let isFuture = dayKey > todayKey
        let segments = isFuture ? [] : CalendarRules.segments(
            on: dayKey, lists: lists, firstEntryDayKey: firstEntryDayKey, looks: data?.looks ?? [:]
        )
        let hasBump = !isFuture && (data?.bumpedDays.contains(dayKey) ?? false)
        let isPlanned = isFuture && (data?.plannedDays.contains(dayKey) ?? false)
        return CalendarDayCell(
            dayNumber: DayMath.parse(dayKey)?.day ?? 0,
            isToday: dayKey == todayKey,
            isSelected: dayKey == selectedKey,
            isFuture: isFuture,
            segments: segments,
            hasBump: hasBump,
            isPlanned: isPlanned,
            openLists: dayKey == todayKey ? todayOpenLists : [],
            diameter: diameter,
            accessibilityLabel: CalendarRules.accessibilityLabel(
                dayKey: dayKey, todayKey: todayKey, segments: segments,
                hasBump: hasBump, isPlanned: isPlanned, todayOpenLists: todayOpenLists, calendar: calendar
            ),
            onTap: { onSelect(dayKey) }
        )
    }
}

/// One day. Past days and today: the date inside its segmented circle (no circle before any list
/// was in use), each segment in the `DayMark` shapes, with a ✓ or × badge on one-list days. Later days: the plain date, with a dot under it when something is planned. Today's
/// date sits on a filled disc; the day open on Home is tinted.
private struct CalendarDayCell: View {
    let dayNumber: Int
    let isToday: Bool
    let isSelected: Bool
    let isFuture: Bool
    let segments: [DaySegment]
    let hasBump: Bool
    let isPlanned: Bool
    /// Today's lists still undecided; empty on other days.
    let openLists: Set<ListKind>
    let diameter: CGFloat
    let accessibilityLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                ZStack {
                    if !segments.isEmpty {
                        SegmentedDayRing(segments: segments, openLists: openLists, lineWidth: max(3, diameter * 0.15))
                    }
                    if isToday {
                        Circle()
                            .fill(Color.primary)
                            .padding(diameter * 0.2)
                    }
                    Text("\(dayNumber)")
                        .font(.footnote.weight(isToday ? .bold : .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(numberStyle)
                        .padding(.horizontal, diameter * 0.18)
                }
                .frame(width: diameter, height: diameter)
                .overlay(alignment: .topTrailing) {
                    if hasBump {
                        // Clear of the ring, so it never hides the first segment (step 5).
                        BumpBadge(diameter: diameter * 0.75)
                            .offset(x: diameter * 0.25, y: -diameter * 0.14)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // ✓ or × only where there's room: a one-list day (provisional, step 5).
                    if segments.count == 1, let glyph = dayGlyph {
                        DayGlyphBadge(glyph: glyph, diameter: diameter * 0.75)
                            .offset(x: diameter * 0.25, y: diameter * 0.14)
                    }
                }

                Circle()
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .opacity(isPlanned ? 1 : 0)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.selectedDayTint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayGlyph: DayMark.Glyph? {
        DayMark.glyph(for: segments.map { DayMark.mark(for: $0, openLists: openLists) })
    }

    private var numberStyle: AnyShapeStyle {
        if isToday { return AnyShapeStyle(Color(uiColor: .systemBackground)) }
        if !isFuture && segments.isEmpty { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
    }
}

#Preview {
    let schema = SharedPersistence.appSchema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        CalendarView(
            selectedDay: Date(),
            now: { Date() },
            defaults: .standard,
            context: container.mainContext,
            onSelectDay: { _ in }
        )
    }
    .modelContainer(container)
}
