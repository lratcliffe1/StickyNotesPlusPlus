import SwiftUI
import SwiftData
import os

/// App entry point that injects the shared SwiftData container.
@main
struct StickyNotePlusPlusApp: App {
    private let modelContainer: ModelContainer

    init() {
#if DEBUG
        // Screenshot harness: use its in-memory store and never open the shared on-disk one.
        if let harness = UITestHarness.current {
            modelContainer = harness.container
            return
        }
#endif
        do {
            modelContainer = try SharedPersistence.makeContainer()
        } catch {
            // The widget may be migrating the store at this very moment: wait briefly, try once more.
            AppLogger.persistence.error("ModelContainer failed, retrying: \(error.localizedDescription, privacy: .public)")
            Thread.sleep(forTimeInterval: 0.5)
            do {
                modelContainer = try SharedPersistence.makeContainer()
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let harness = UITestHarness.current {
                HomeView(
                    viewModel: harness.viewModel,
                    initialDestination: harness.initialDestination,
                    editListsLaunch: harness.editListsLaunch,
                    initialSheet: harness.initialSheet,
                    calendarMonthOffset: harness.calendarMonthOffset
                )
                .preferredColorScheme(harness.colorScheme)
            } else {
                ContentView()
            }
#else
            ContentView()
#endif
        }
        .modelContainer(modelContainer)
    }
}
