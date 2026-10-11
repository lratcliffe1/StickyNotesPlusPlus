import SwiftData
import SwiftUI
import os

/// Settings screen for editing the morning list's items (repeat daily) and their order.
/// Every change goes through `ListService`: renames apply from today, deletes stop the item
/// from today on, and earlier days keep what they had.
struct EditMorningRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Item> { $0.listRaw == "morning" && $0.endDayKey == nil },
        sort: \Item.sortOrder
    ) private var items: [Item]

    @State private var newItemTitle: String = ""

    var body: some View {
        List {
            Section("Routine Items") {
                if items.isEmpty {
                    Text("No routine items yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(items) { item in
                    TextField(
                        "Routine item",
                        text: Binding(
                            get: { item.title },
                            set: { newValue in rename(item, to: newValue) }
                        )
                    )
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)
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
    }

    private var todayKey: String {
        HomeModel.dayKey(for: Date())
    }

    private func addItem() {
        let title = newItemTitle
        perform("Add routine item") {
            _ = try ListService.addItem(list: .morning, title: title, rule: .daily, context: modelContext)
        }
        newItemTitle = ""
    }

    private func rename(_ item: Item, to title: String) {
        perform("Rename routine item") {
            try ListService.renameItem(item, to: title, todayKey: todayKey, context: modelContext)
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let doomed = offsets.map { items[$0] }
        perform("Delete routine item") {
            for item in doomed {
                try ListService.deleteItem(item, todayKey: todayKey, context: modelContext)
            }
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        perform("Reorder routine items") {
            try ListService.reorderItems(reordered, todayKey: todayKey, context: modelContext)
        }
    }

    private func perform(_ label: String, _ body: () throws -> Void) {
        do {
            try body()
            TaskWidgetReloader.reloadTopTasksWidget()
        } catch {
            AppLogger.persistence.error("\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
        }
    }
}

#Preview {
    let schema = SharedPersistence.appSchema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        EditMorningRoutineView()
    }
    .modelContainer(container)
}
