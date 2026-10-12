import SwiftData
import SwiftUI
import os

/// Settings → Edit Lists (DECISIONS.md, 2b): one screen with a Morning / Day / Evening switch.
/// Lists that list's recurring items (current ones, including one starting tomorrow after a repeat
/// change); add, reorder, tap to edit, delete (confirmed). One-offs are added on Home.
struct EditListsView: View {
    private enum EditorTarget: Identifiable {
        case add(ListKind)
        case edit(Item)

        var id: String {
            switch self {
            case let .add(list): return "add-\(list.rawValue)"
            case let .edit(item): return "edit-\(item.id.uuidString)"
            }
        }
    }

    /// The current time, read at each change (not when the screen opened).
    let now: () -> Date
    var onChange: () -> Void = {}
#if DEBUG
    /// Screenshot harness only: open this item's editor (and its repeat picker) on appear.
    private var autoOpenItemTitle: String?
    private var autoShowsRepeat = false
#endif

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Item.sortOrder), SortDescriptor(\Item.createdAt), SortDescriptor(\Item.startDayKey)])
    private var allItems: [Item]
    @State private var list: ListKind
    @State private var editor: EditorTarget?
    @State private var pendingDelete: Item?
    @State private var didAutoOpen = false

    init(
        initialList: ListKind = .morning,
        now: @escaping () -> Date = { Date() },
        onChange: @escaping () -> Void = {}
    ) {
        _list = State(initialValue: initialList)
        self.now = now
        self.onChange = onChange
    }

#if DEBUG
    /// Screenshot harness only.
    func autoOpening(itemTitled title: String?, showsRepeat: Bool) -> EditListsView {
        var copy = self
        copy.autoOpenItemTitle = title
        copy.autoShowsRepeat = showsRepeat
        return copy
    }
#endif

    private var items: [Item] {
        allItems.filter { $0.list == list && $0.endDayKey == nil }
    }

    private var todayKey: String {
        HomeModel.dayKey(for: now())
    }

    var body: some View {
        List {
            Section {
                Picker("List", selection: $list) {
                    Text("Morning").tag(ListKind.morning)
                    Text("Day").tag(ListKind.day)
                    Text("Evening").tag(ListKind.evening)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if items.isEmpty {
                    Text("No \(listName) items yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button {
                        editor = .edit(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(.primary)
                            Label(item.repeatRule.summary(startDayKey: item.startDayKey), systemImage: "repeat")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    // Plain, so the rows read as black text, not tinted links (greyscale).
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit item")
                }
                .onMove(perform: move)
                .onDelete { offsets in
                    pendingDelete = offsets.first.map { items[$0] }
                }
            } header: {
                Text("Repeating items")
            } footer: {
                Text("One-offs are added on Home. Changes apply from today; earlier days keep what they had.")
            }
        }
        .navigationTitle("Edit Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button {
                    editor = .add(list)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add item")
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case let .add(list):
                ItemEditorView(mode: .add(list), now: now, onSaved: onChange)
            case let .edit(item):
                editor(for: item)
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")” from today on?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete from Today On", role: .destructive) {
                delete(item)
            }
        } message: { _ in
            Text("Earlier days keep it.")
        }
#if DEBUG
        .task {
            guard !didAutoOpen, let title = autoOpenItemTitle else { return }
            didAutoOpen = true
            try? await Task.sleep(for: .milliseconds(500))
            if let item = items.first(where: { $0.title == title }) {
                editor = .edit(item)
            }
        }
#endif
    }

    private func editor(for item: Item) -> ItemEditorView {
        let view = ItemEditorView(mode: .edit(item), now: now, onSaved: onChange)
#if DEBUG
        if autoShowsRepeat, item.title == autoOpenItemTitle {
            return view.showingRepeatOnAppear()
        }
#endif
        return view
    }

    private var listName: String {
        switch list {
        case .morning: return "morning"
        case .day: return "day"
        case .evening: return "evening"
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        perform("Reorder items") {
            try ListService.reorderItems(reordered, todayKey: todayKey, context: modelContext)
        }
    }

    private func delete(_ item: Item) {
        perform("Delete item") {
            _ = try ListService.deleteItem(item, todayKey: todayKey, context: modelContext)
        }
    }

    private func perform(_ label: String, _ body: () throws -> Void) {
        do {
            try body()
            TaskWidgetReloader.reloadTopTasksWidget()
            onChange()
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
        EditListsView()
    }
    .modelContainer(container)
}
