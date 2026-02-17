import SwiftUI
import SwiftData

struct AddDailyTaskView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var selectedDate = Date()
    @State private var mustHappenToday = false

    var body: some View {
        Form {
            Section("Task") {
                TextField("Task title", text: $title)
                    .textInputAutocapitalization(.sentences)

                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)

                Toggle("Must happen today", isOn: $mustHappenToday)

                Button("Add Task") {
                    addTask()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Add Daily Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = DailyTask(
            date: selectedDate,
            title: trimmed,
            isBumpable: !mustHappenToday
        )

        modelContext.insert(task)
        saveContext()

        title = ""
        mustHappenToday = false
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("SwiftData save error:", error)
        }
    }
}

#Preview {
    let schema = Schema([DailyTask.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        AddDailyTaskView()
    }
    .modelContainer(container)
}
