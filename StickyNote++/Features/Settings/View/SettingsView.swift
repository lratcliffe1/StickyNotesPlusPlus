import SwiftData
import SwiftUI

/// Settings hub that links to routine editing and task utilities.
struct SettingsView: View {
    var body: some View {
        List {
            Section("Daily") {
                NavigationLink {
                    AddDailyTaskView()
                } label: {
                    Label("Add Daily Tasks", systemImage: "plus.circle")
                }
            }

            Section("Morning") {
                NavigationLink {
                    EditMorningRoutineView()
                } label: {
                    Label("Edit Morning Routine", systemImage: "sun.max")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

#Preview {
    let schema = SharedPersistence.appSchema()

    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        SettingsView()
    }
    .modelContainer(container)
}
