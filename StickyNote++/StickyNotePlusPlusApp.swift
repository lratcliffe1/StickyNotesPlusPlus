import SwiftUI
import SwiftData

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
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let harness = UITestHarness.current {
                HomeView(viewModel: harness.viewModel, initialDestination: harness.initialDestination)
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
