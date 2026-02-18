import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: HomeViewModel
    @State private var isShowingCalendar = false
    @State private var isShowingSettings = false

    private let onOpenCalendar: () -> Void
    private let refreshOnAppear: Bool

    @MainActor
    init(
        viewModel: HomeViewModel? = nil,
        refreshOnAppear: Bool = true,
        onOpenCalendar: @escaping () -> Void = {}
    ) {
        _vm = StateObject(wrappedValue: viewModel ?? HomeViewModel())
        self.refreshOnAppear = refreshOnAppear
        self.onOpenCalendar = onOpenCalendar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        HomeHeaderCard(
                            morningStreakCount: vm.morningStreakCount,
                            dailyTaskStreakCount: vm.dailyTaskStreakCount,
                            sevenDayProgress: vm.sevenDayProgress,
                            onTap: openCalendar
                        )
                        .frame(maxWidth: .infinity)

                        settingsButton
                    }

                    if !isViewingToday {
                        selectedDayControls
                    }

                    if let bannerText = vm.neverMissTwiceBannerText {
                        HomeNeverMissTwiceBanner(text: bannerText)
                    }

                    HomeStickyNoteCard(vm: vm, modelContext: modelContext)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(screenBackground.ignoresSafeArea())
            .task {
                if refreshOnAppear {
                    vm.refresh(context: modelContext)
                }
            }
            .navigationDestination(isPresented: $isShowingCalendar) {
                CalendarView(
                    selectedDay: vm.selectedDay,
                    onSelectDay: { day in
                        vm.setSelectedDay(day, context: modelContext, preferredList: .daily)
                        isShowingCalendar = false
                    },
                    onToday: {
                        vm.goToToday(context: modelContext)
                        isShowingCalendar = false
                    }
                )
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var isViewingToday: Bool {
        HomeModel.isToday(vm.selectedDay)
    }

    private var selectedDayControls: some View {
        HStack(spacing: 10) {
            Button {
                openCalendar()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.8))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to calendar")

            Button("Today") {
                vm.goToToday(context: modelContext)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.8))
            .clipShape(Capsule())
            .buttonStyle(.plain)

            Spacer()

            Text(vm.selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.85))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.95), lineWidth: 1)
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

    private var screenBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.00),
                Color(red: 0.89, green: 0.92, blue: 0.98)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
