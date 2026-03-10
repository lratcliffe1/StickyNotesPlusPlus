import SwiftUI
import SwiftData
import os

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
        let sortOrder: Int
        do {
            sortOrder = try HomeDataStore.nextSortOrder(
                for: selectedDate,
                insertAtTop: mustHappenToday,
                context: modelContext
            )
        } catch {
            AppLogger.persistence.error("Compute sort order in settings failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let task = DailyTask(
            date: selectedDate,
            title: trimmed,
            sortOrder: sortOrder,
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
            TaskWidgetReloader.reloadTopTasksWidget()
        } catch {
            AppLogger.persistence.error("Save from AddDailyTaskView failed: \(error.localizedDescription, privacy: .public)")
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
