import Foundation
import SwiftData

/// In-memory V2 stores and throwaway defaults for the service and backfill tests.
enum StoreTestSupport {
    static func makeContext() throws -> ModelContext {
        let schema = SharedPersistence.appSchema()
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, migrationPlan: StickyNotesMigrationPlan.self, configurations: [config])
        return ModelContext(container)
    }

    /// A fresh, empty defaults suite. Call `removePersistentDomain(forName:)` with the name when done.
    static func makeDefaults() -> (defaults: UserDefaults, name: String) {
        let name = "StickyNotesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    static func all<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}
