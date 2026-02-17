//
//  ContentView.swift
//  Sticky Notes Sticky Life
//
//  Created by Liam Ratcliffe on 17/02/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Item.self,
                MorningRoutineTemplateItem.self,
                MorningRoutineEntry.self,
                DailyTask.self,
                DayRecord.self
            ],
            inMemory: true
        )
}
