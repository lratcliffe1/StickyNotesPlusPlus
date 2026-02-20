import SwiftUI
import SwiftData

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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
