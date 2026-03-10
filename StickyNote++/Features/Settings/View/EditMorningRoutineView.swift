import SwiftData
import SwiftUI
import os

struct EditMorningRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MorningRoutineTemplateItem.sortOrder) private var templates: [MorningRoutineTemplateItem]

    @State private var newItemTitle: String = ""

    var body: some View {
        List {
            Section("Routine Items") {
                if templates.isEmpty {
                    Text("No routine items yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(templates) { template in
                    TextField(
                        "Routine item",
                        text: Binding(
                            get: { template.title },
                            set: { newValue in template.title = newValue }
                        )
                    )
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit(saveContext)
                }
                .onDelete(perform: deleteTemplates)
                .onMove(perform: moveTemplates)
            }

            Section("Add Item") {
                TextField("New routine item", text: $newItemTitle)
                    .textInputAutocapitalization(.sentences)

                Button("Add") {
                    addItem()
                }
                .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Edit Morning Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            EditButton()
        }
        .onDisappear {
            if modelContext.hasChanges {
                saveContext()
            }
        }
    }

    private func addItem() {
        let trimmed = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newItem = MorningRoutineTemplateItem(
            title: trimmed,
            sortOrder: templates.count,
            targetTime: nil
        )

        modelContext.insert(newItem)
        saveContext()

        newItemTitle = ""
    }

    private func deleteTemplates(at offsets: IndexSet) {
        var remaining = templates
        remaining.remove(atOffsets: offsets)

        for index in offsets {
            modelContext.delete(templates[index])
        }

        for (index, item) in remaining.enumerated() {
            item.sortOrder = index
        }

        saveContext()
    }

    private func moveTemplates(from source: IndexSet, to destination: Int) {
        var reordered = templates
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, item) in reordered.enumerated() {
            item.sortOrder = index
        }

        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
            TaskWidgetReloader.reloadTopTasksWidget()
        } catch {
            AppLogger.persistence.error("Save from EditMorningRoutineView failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    let schema = Schema([MorningRoutineTemplateItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        EditMorningRoutineView()
    }
    .modelContainer(container)
}
