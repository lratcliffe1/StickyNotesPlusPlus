//
//  Sticky_Notes_Sticky_LifeApp.swift
//  Sticky Notes Sticky Life
//
//  Created by Liam Ratcliffe on 17/02/2026.
//

import SwiftUI
import SwiftData

@main
struct Sticky_Notes_Sticky_LifeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
