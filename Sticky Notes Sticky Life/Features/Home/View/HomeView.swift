import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm: HomeViewModel

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
                    HomeHeaderCard(
                        morningStreakCount: vm.morningStreakCount,
                        dailyTaskStreakCount: vm.dailyTaskStreakCount,
                        sevenDayProgress: vm.sevenDayProgress,
                        onTap: onOpenCalendar
                    )

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
        }
        .toolbar(.hidden, for: .navigationBar)
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
