import SwiftData
import SwiftUI

/// Settings hub: Edit Lists, adding a task on another day, and Retype to bump.
/// (Step 3 turns this into the full grouped list from DECISIONS.md.)
struct SettingsView: View {
    let now: Date
    var onListsChanged: () -> Void = {}
    @AppStorage private var retypeToBump: Bool

    init(
        defaults: UserDefaults = SharedPersistence.sharedDefaults,
        now: Date = Date(),
        onListsChanged: @escaping () -> Void = {}
    ) {
        self.now = now
        self.onListsChanged = onListsChanged
        _retypeToBump = AppStorage(
            wrappedValue: AppSettings.defaultRetypeToBump,
            AppSettings.retypeToBumpKey,
            store: defaults
        )
    }

    var body: some View {
        List {
            Section("Lists") {
                NavigationLink {
                    EditListsView(now: now, onChange: onListsChanged)
                } label: {
                    Label("Edit Lists", systemImage: "list.bullet")
                }
            }

            Section("Daily") {
                NavigationLink {
                    AddDailyTaskView()
                } label: {
                    Label("Add Daily Tasks", systemImage: "plus.circle")
                }
            }

            Section {
                Toggle(isOn: $retypeToBump) {
                    Label("Retype to Bump", systemImage: "keyboard")
                }
            } header: {
                Text("Bumping")
            } footer: {
                Text(retypeToBump
                     ? "On: to bump a task to tomorrow you type it again (you can change it)."
                     : "Off: the bump sheet fills in the title; you just confirm.")
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
