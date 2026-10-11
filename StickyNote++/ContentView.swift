//
//  ContentView.swift
//  StickyNote++
//
//  Created by Liam Ratcliffe on 17/02/2026.
//

import SwiftUI
import SwiftData

/// Root host view that loads the main Home experience.
struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                MorningRoutineTemplateItem.self,
                MorningRoutineEntry.self,
                DailyTask.self,
                DayRecord.self,
                Item.self,
                Occurrence.self,
            ],
            inMemory: true
        )
}
