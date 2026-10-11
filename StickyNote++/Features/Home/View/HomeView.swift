import Combine
import SwiftData
import SwiftUI
import os

/// Main Home screen shell that composes header, sticky note card, and navigation flows.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm: HomeViewModel
    @Namespace private var calendarTransition
    @State private var isShowingCalendar = false
    @State private var isShowingSettings = false
    @State private var isShowingAddDailyTask = false
    @State private var didRunLaunch = false
#if DEBUG
    @State private var isShowingEditLists = false
#endif
    @State private var dayTransitionDirection: DayTransitionDirection = .next
    @State private var isTaskRowSwipeActive = false

    private let onOpenCalendar: () -> Void
    private let refreshOnAppear: Bool
    private let initialDestination: HomeInitialDestination
#if DEBUG
    /// Screenshot harness only.
    private var editListsLaunch: EditListsLaunch?
    private var initialSheet: HomeSheet?
    /// The calendar's first month, as months after the current one (`-uiCalendarMonth`).
    private var calendarMonthOffset = 0
#endif
    private let calendarTransitionSourceID = "home-calendar-header"

    @MainActor
    init(
        viewModel: HomeViewModel? = nil,
        refreshOnAppear: Bool = true,
        initialDestination: HomeInitialDestination = .home,
        onOpenCalendar: @escaping () -> Void = {}
    ) {
        _vm = StateObject(wrappedValue: viewModel ?? HomeViewModel())
        self.refreshOnAppear = refreshOnAppear
        self.initialDestination = initialDestination
        self.onOpenCalendar = onOpenCalendar
    }

#if DEBUG
    /// Screenshot harness only: Home plus Edit Lists or a sheet opened at launch.
    @MainActor
    init(
        viewModel: HomeViewModel,
        initialDestination: HomeInitialDestination,
        editListsLaunch: EditListsLaunch?,
        initialSheet: HomeSheet?,
        calendarMonthOffset: Int = 0
    ) {
        self.init(viewModel: viewModel, initialDestination: initialDestination)
        self.editListsLaunch = editListsLaunch
        self.initialSheet = initialSheet
        self.calendarMonthOffset = calendarMonthOffset
    }
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        headerCard

                        settingsButton
                    }

                    selectedDayControls

                    let bannerLines = vm.neverMissTwiceBannerLines
                    if !bannerLines.isEmpty {
                        HomeNeverMissTwiceBanner(lines: bannerLines)
                    }

                    HomeStickyNoteCard(
                        vm: vm,
                        modelContext: modelContext,
                        onTaskRowSwipeActiveChange: { isActive in
                            isTaskRowSwipeActive = isActive
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(daySwipeGesture)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .task {
                // Also runs on returning from Settings, so edits made there show.
                if refreshOnAppear {
                    vm.refresh(context: modelContext)
                }
                guard !didRunLaunch else { return }
                didRunLaunch = true
                switch initialDestination {
                case .home:
                    break
                case .calendar:
                    isShowingCalendar = true
                case .settings:
                    isShowingSettings = true
                }
#if DEBUG
                if editListsLaunch != nil {
                    isShowingEditLists = true
                }
                if let initialSheet {
                    try? await Task.sleep(for: .milliseconds(400))
                    vm.activeSheet = initialSheet
                }
#endif
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                syncFromExternalWrites()
            }
            // Midnight, a time-zone change or a clock change while the app is open.
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification))
                    .receive(on: DispatchQueue.main)
            ) { _ in
                vm.handleClockChange(context: modelContext)
            }
            // Wait for the next boundary (the morning's end, the evening's start or midnight), then
            // refresh, so the list flips on time.
            // Checks the wall clock at least once a minute, so it survives the phone sleeping
            // (uptime-based sleeps pause while locked) and wakes that come a little early.
            .task(id: vm.nextClockBoundary) {
                let due = vm.nextClockBoundary.addingTimeInterval(1)
                while Date() < due, !Task.isCancelled {
                    let remaining = due.timeIntervalSinceNow
                    try? await Task.sleep(for: .seconds(min(max(remaining, 0.5), 60)), clock: .continuous)
                }
                guard !Task.isCancelled else { return }
                vm.handleClockChange(context: modelContext)
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .navigationDestination(isPresented: $isShowingCalendar) {
                calendarDestination
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(
                    defaults: vm.defaults,
                    now: { vm.now },
                    onListsChanged: {
                        // Re-read straight away: Edit Lists may have deleted rows Home still holds.
                        vm.refresh(context: modelContext)
                    },
                    onRulesChanged: {
                        // Home re-reads on return; the widget picks its list again now.
                        vm.reloadWidget()
                    }
                )
            }
#if DEBUG
            .navigationDestination(isPresented: $isShowingEditLists) {
                EditListsView(initialList: editListsLaunch?.list ?? .morning, now: { vm.now }) {
                    vm.refresh(context: modelContext)
                }
                .autoOpening(itemTitled: editListsLaunch?.openItemTitle, showsRepeat: editListsLaunch?.showsRepeat ?? false)
            }
#endif
            .navigationDestination(isPresented: $isShowingAddDailyTask) {
                AddDailyTaskView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var isViewingToday: Bool {
        HomeModel.isToday(vm.selectedDay)
    }

    private var selectedDayControls: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.selectedDayRelativeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ZStack(alignment: .leading) {
                    Text(vm.selectedDayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .id(vm.selectedDay.timeIntervalSinceReferenceDate)
                        .transition(dayLabelTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassCard(
                cornerRadius: 12,
                fill: AnyShapeStyle(AppTheme.chipSurface),
                border: AppTheme.cardBorder,
                shadowOpacity: 0.04
            )

            if !isViewingToday {
                Button("Today") {
                    goToTodayAnimated()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.chipSurface)
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
        }
        .animation(dayAnimation, value: vm.selectedDay)
        .padding(.horizontal, 2)
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(AppTheme.chipSurface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open settings")
    }

    private func openCalendar() {
        isShowingCalendar = true
        onOpenCalendar()
    }

    @ViewBuilder
    private var headerCard: some View {
        if #available(iOS 18.0, *) {
            HomeHeaderCard(
                morningStreakCount: vm.morningStreakCount,
                dailyTaskStreakCount: vm.dailyTaskStreakCount,
                isMorningStreakFrozen: vm.isMorningStreakFrozen,
                isDailyTaskStreakFrozen: vm.isDailyTaskStreakFrozen,
                eveningStreakCount: vm.eveningStreakCount,
                isEveningStreakFrozen: vm.isEveningStreakFrozen,
                showsEveningStreak: vm.isEveningInUse,
                sevenDayProgress: vm.sevenDayProgress,
                selectedDay: vm.selectedDay,
                bumpsInSevenDays: vm.bumpsInSevenDays,
                today: vm.now,
                onTap: openCalendar
            )
            .frame(maxWidth: .infinity)
            .matchedTransitionSource(id: calendarTransitionSourceID, in: calendarTransition)
        } else {
            HomeHeaderCard(
                morningStreakCount: vm.morningStreakCount,
                dailyTaskStreakCount: vm.dailyTaskStreakCount,
                isMorningStreakFrozen: vm.isMorningStreakFrozen,
                isDailyTaskStreakFrozen: vm.isDailyTaskStreakFrozen,
                eveningStreakCount: vm.eveningStreakCount,
                isEveningStreakFrozen: vm.isEveningStreakFrozen,
                showsEveningStreak: vm.isEveningInUse,
                sevenDayProgress: vm.sevenDayProgress,
                selectedDay: vm.selectedDay,
                bumpsInSevenDays: vm.bumpsInSevenDays,
                today: vm.now,
                onTap: openCalendar
            )
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var calendarDestination: some View {
        if #available(iOS 18.0, *) {
            calendarView
                .navigationTransition(.zoom(sourceID: calendarTransitionSourceID, in: calendarTransition))
        } else {
            calendarView
        }
    }

    private var calendarView: some View {
        CalendarView(
            selectedDay: vm.selectedDay,
            now: vm.now,
            defaults: vm.defaults,
            context: modelContext,
            initialMonthOffset: initialCalendarMonthOffset,
            onSelectDay: { day in
                setSelectedDay(day, preferredList: .daily)
                isShowingCalendar = false
            }
        )
    }

    private var initialCalendarMonthOffset: Int {
#if DEBUG
        calendarMonthOffset
#else
        0
#endif
    }

    private var dayAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.2)
    }

    private var dayLabelTransition: AnyTransition {
        switch dayTransitionDirection {
        case .next:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .previous:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                guard !isTaskRowSwipeActive else { return }

                let horizontal = value.translation.width
                let vertical = value.translation.height

                guard abs(horizontal) > HomeGestureMetrics.minimumSwipeDistance else { return }
                guard abs(horizontal) > abs(vertical) * HomeGestureMetrics.horizontalToVerticalRatio else { return }

                if horizontal < 0 {
                    shiftSelectedDay(by: 1, direction: .next)
                } else {
                    shiftSelectedDay(by: -1, direction: .previous)
                }
            }
    }

    private func shiftSelectedDay(by value: Int, direction: DayTransitionDirection) {
        guard let target = Calendar.current.date(byAdding: .day, value: value, to: vm.selectedDay) else { return }
        setSelectedDay(target, direction: direction)
    }

    private func setSelectedDay(
        _ day: Date,
        preferredList: HomeModel.ContextualList? = nil,
        direction: DayTransitionDirection? = nil
    ) {
        let normalizedDay = HomeModel.normalizedDay(day)
        let currentDay = HomeModel.normalizedDay(vm.selectedDay)
        guard normalizedDay != currentDay else { return }

        dayTransitionDirection = direction ?? (normalizedDay > currentDay ? .next : .previous)

        withAnimation(dayAnimation) {
            vm.setSelectedDay(normalizedDay, context: modelContext, preferredList: preferredList)
        }
    }

    private func goToTodayAnimated() {
        let today = HomeModel.normalizedDay(Date())
        let currentDay = HomeModel.normalizedDay(vm.selectedDay)
        guard today != currentDay else { return }

        dayTransitionDirection = today > currentDay ? .next : .previous

        withAnimation(dayAnimation) {
            vm.goToToday(context: modelContext)
        }
    }

    private func syncFromExternalWrites() {
        if modelContext.hasChanges {
            do {
                try modelContext.save()
            } catch {
                AppLogger.persistence.error("HomeView external sync save failed: \(error.localizedDescription, privacy: .public)")
                modelContext.rollback()
            }
        } else {
            modelContext.rollback()
        }

        vm.handleClockChange(context: modelContext)
    }

    private func handleDeepLink(_ url: URL) {
        // The widget's bump button with Retype to bump on: open today's bump sheet for that row.
        if let id = BumpDeepLink.occurrenceID(from: url) {
            isShowingCalendar = false
            isShowingSettings = false
            isShowingAddDailyTask = false
            vm.goToToday(context: modelContext)
            vm.openBumpSheet(for: id, context: modelContext)
            return
        }
        guard isAddDailyTaskDeepLink(url) else { return }
        isShowingAddDailyTask = true
    }

    private func isAddDailyTaskDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "stickynotes" else { return false }
        if url.host?.lowercased() == "add-daily-task" {
            return true
        }

        let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return normalizedPath == "add-daily-task"
    }
}

/// Screen pushed when Home first appears. Only the screenshot harness uses anything but `.home`.
enum HomeInitialDestination: String {
    case home
    case calendar
    case settings
}

#if DEBUG
/// Edit Lists pushed when Home first appears, on a given list (screenshot harness only).
struct EditListsLaunch {
    let list: ListKind
    /// Opens this item's editor, and with `showsRepeat` its repeat picker.
    var openItemTitle: String?
    var showsRepeat = false
}
#endif

private enum DayTransitionDirection {
    case previous
    case next
}

private enum HomeGestureMetrics {
    static let minimumSwipeDistance: CGFloat = 44
    static let horizontalToVerticalRatio: CGFloat = 1.25
}
