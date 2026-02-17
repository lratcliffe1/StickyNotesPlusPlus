import SwiftUI
import SwiftData

@main
struct Sticky_Notes_Sticky_LifeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            MorningRoutineTemplateItem.self,
            MorningRoutineEntry.self,
            DailyTask.self,
            DayRecord.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
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
