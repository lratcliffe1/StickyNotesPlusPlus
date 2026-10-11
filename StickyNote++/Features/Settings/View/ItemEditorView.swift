import SwiftData
import SwiftUI
import os

/// Adds or edits a recurring item: title, repeat (Reminders-style picker), bump limit (non-daily
/// repeats only) and delete. Every write goes through `ListService`: a rename applies from today,
/// a new repeat starts a new item from today (or tomorrow; see `ListService.updateItem`), a delete
/// stops it from today on.
struct ItemEditorView: View {
    enum Mode {
        case add(ListKind)
        case edit(Item)
    }

    private enum Route: Hashable {
        case repeatPicker
    }

    let mode: Mode
    let now: Date
    /// Opens straight onto the repeat picker (the screenshot harness).
    var showsRepeatOnAppear = false
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var rule: RepeatRule
    @State private var limitChoice: BumpLimitChoice
    @State private var days: Int
    @State private var path: [Route] = []
    @State private var isConfirmingDelete = false

    init(mode: Mode, now: Date, showsRepeatOnAppear: Bool = false, onSaved: @escaping () -> Void = {}) {
        self.mode = mode
        self.now = now
        self.showsRepeatOnAppear = showsRepeatOnAppear
        self.onSaved = onSaved
        switch mode {
        case .add:
            _title = State(initialValue: "")
            _rule = State(initialValue: .daily)
            _limitChoice = State(initialValue: .unlimited)
            _days = State(initialValue: 3)
        case let .edit(item):
            let limit = item.defaultBumpLimit
            _title = State(initialValue: item.title)
            _rule = State(initialValue: item.repeatRule)
            _limitChoice = State(initialValue: BumpLimitChoice(limit))
            _days = State(initialValue: limit.storedDays > 0 ? limit.storedDays : 3)
        }
    }

    private var item: Item? {
        if case let .edit(item) = mode { return item }
        return nil
    }

    private var todayKey: String {
        HomeModel.dayKey(for: now)
    }

    private var startDayKey: String {
        item?.startDayKey ?? todayKey
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    NavigationLink(value: Route.repeatPicker) {
                        LabeledContent("Repeat", value: rule.summary(startDayKey: startDayKey))
                    }
                }

                if rule.kind != .daily {
                    Section {
                        Picker("Bump limit", selection: $limitChoice) {
                            Text("Until its period ends").tag(BumpLimitChoice.unlimited)
                            Text("Up to a number of days").tag(BumpLimitChoice.upToDays)
                            Text("Until the end of the week").tag(BumpLimitChoice.endOfWeek)
                            Text("Can't bump").tag(BumpLimitChoice.cantBump)
                        }
                        if limitChoice == .upToDays {
                            Stepper("Up to \(days) \(days == 1 ? "day" : "days")", value: $days, in: 1...30)
                        }
                    } header: {
                        Text("Bumping")
                    } footer: {
                        Text("It can move a day at a time until its next one is due or its \(rule.periodName) ends, and no further than this limit.")
                    }
                }

                if item != nil {
                    Section {
                        Button("Delete Item", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } footer: {
                        Text("It stops from today on. Earlier days keep it.")
                    }
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { _ in
                RepeatPickerView(rule: $rule, defaultWeekday: DayMath().weekday(startDayKey))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete “\(item?.title ?? title)” from today on?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete from Today On", role: .destructive, action: delete)
            } message: {
                Text("Earlier days keep it.")
            }
            .onAppear {
                if showsRepeatOnAppear, path.isEmpty {
                    path = [.repeatPicker]
                }
            }
        }
    }

    /// The limit to save. Daily repeats can't be bumped, so their limit is kept as it was.
    private var bumpLimit: BumpLimit {
        if rule.kind == .daily {
            return item?.defaultBumpLimit ?? .unlimited
        }
        return limitChoice.limit(days: days, deadlineDayKey: nil) ?? .unlimited
    }

    private func save() {
        perform("Save item") {
            switch mode {
            case let .add(list):
                _ = try ListService.addItem(
                    list: list, title: trimmedTitle, rule: rule, defaultBumpLimit: bumpLimit,
                    now: now, context: modelContext
                )
            case let .edit(item):
                _ = try ListService.updateItem(
                    item, title: trimmedTitle, rule: rule, bumpLimit: bumpLimit,
                    now: now, context: modelContext
                )
            }
        }
    }

    private func delete() {
        guard let item else { return }
        perform("Delete item") {
            try ListService.deleteItem(item, todayKey: todayKey, context: modelContext)
        }
    }

    private func perform(_ label: String, _ body: () throws -> Void) {
        do {
            try body()
            TaskWidgetReloader.reloadTopTasksWidget()
            onSaved()
            dismiss()
        } catch {
            AppLogger.persistence.error("\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            modelContext.rollback()
        }
    }
}
