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
    @State private var dayTransitionDirection: DayTransitionDirection = .next
    @State private var isTaskRowSwipeActive = false

    private let onOpenCalendar: () -> Void
    private let refreshOnAppear: Bool
    private let initialDestination: HomeInitialDestination
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
                if refreshOnAppear {
                    vm.refresh(context: modelContext)
                }
                switch initialDestination {
                case .home:
                    break
                case .calendar:
                    isShowingCalendar = true
                case .settings:
                    isShowingSettings = true
                }
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
            // Wait for the next cutoff or midnight, then refresh, so the list flips on time.
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
                SettingsView()
            }
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
                sevenDayProgress: vm.sevenDayProgress,
                selectedDay: vm.selectedDay,
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
                sevenDayProgress: vm.sevenDayProgress,
                selectedDay: vm.selectedDay,
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
            onSelectDay: { day in
                setSelectedDay(day, preferredList: .daily)
                isShowingCalendar = false
            }
        )
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

private enum DayTransitionDirection {
    case previous
    case next
}

private enum HomeGestureMetrics {
    static let minimumSwipeDistance: CGFloat = 44
    static let horizontalToVerticalRatio: CGFloat = 1.25
}
