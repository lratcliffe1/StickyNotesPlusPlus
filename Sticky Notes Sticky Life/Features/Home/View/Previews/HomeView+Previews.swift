#if DEBUG
import SwiftData
import SwiftUI

@MainActor
private func makeHomePreviewContainer() -> ModelContainer {
    let schema = Schema([
        MorningRoutineTemplateItem.self,
        MorningRoutineEntry.self,
        DailyTask.self,
        DayRecord.self,
    ])

    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [config])
}

#Preview("Morning List - In Morning") {
    HomeView(viewModel: .preview(.morningActive), refreshOnAppear: false)
        .modelContainer(makeHomePreviewContainer())
}

#Preview("Daily List - After Morning Window") {
    HomeView(viewModel: .preview(.dailyAfterMorningWindow), refreshOnAppear: false)
        .modelContainer(makeHomePreviewContainer())
}

#Preview("Daily List - Morning Completed") {
    HomeView(viewModel: .preview(.dailyAfterMorningCompleted), refreshOnAppear: false)
        .modelContainer(makeHomePreviewContainer())
}

#Preview("Streak - Morning Frozen") {
    HomeView(viewModel: .preview(.morningStreakFrozen), refreshOnAppear: false)
        .modelContainer(makeHomePreviewContainer())
}

#Preview("Streak - Daily Frozen") {
    HomeView(viewModel: .preview(.dailyStreakFrozen), refreshOnAppear: false)
        .modelContainer(makeHomePreviewContainer())
}

#Preview("Streak - Reset to Zero") {
    HomeView(viewModel: .preview(.streakReset), refreshOnAppear: false)
        .modelContainer(makeHomePreviewContainer())
}
#endif
