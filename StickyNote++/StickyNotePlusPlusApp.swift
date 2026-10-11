import SwiftUI
import SwiftData

/// App entry point that injects the shared SwiftData container.
@main
struct StickyNotePlusPlusApp: App {
    var sharedModelContainer: ModelContainer = {
        do {
            return try SharedPersistence.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let harness = UITestHarness.current {
                HomeView(viewModel: harness.viewModel, initialDestination: harness.initialDestination)
                    .modelContainer(harness.container)
            } else {
                ContentView()
            }
#else
            ContentView()
#endif
        }
        .modelContainer(sharedModelContainer)
    }
}
