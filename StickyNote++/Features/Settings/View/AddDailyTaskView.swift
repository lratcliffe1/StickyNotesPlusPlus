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
        let sortOrder = nextSortOrder(for: selectedDate, insertAtTop: mustHappenToday)

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

    private func nextSortOrder(for day: Date, insertAtTop: Bool) -> Int {
        let dayKey = HomeModel.dayKey(for: HomeModel.normalizedDay(day))
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.dayKey == dayKey },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []

        if insertAtTop {
            return (tasks.map(\.sortOrder).min() ?? 0) - 1
        }

        return (tasks.map(\.sortOrder).max() ?? -1) + 1
    }

    private func saveContext() {
        do {
            try modelContext.save()
            TaskWidgetReloader.reloadTopTasksWidget()
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
