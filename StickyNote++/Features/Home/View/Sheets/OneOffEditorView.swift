import SwiftUI

/// Edit… on a one-off (provisional: this row only): its title, deadline and bump limit.
struct OneOffEditorView: View {
    let occurrence: Occurrence
    /// (title, bump limit, deadline day key or nil)
    let onSave: (String, BumpLimit, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var limitChoice: BumpLimitChoice
    @State private var days: Int

    init(occurrence: Occurrence, onSave: @escaping (String, BumpLimit, String?) -> Void) {
        self.occurrence = occurrence
        self.onSave = onSave
        let limit = occurrence.bumpLimit
        let deadlineKey = occurrence.deadlineDayKey
        let rowDay = HomeModel.date(fromDayKey: occurrence.dayKey) ?? Date()
        _title = State(initialValue: occurrence.title)
        _hasDeadline = State(initialValue: deadlineKey != nil)
        _deadline = State(
            initialValue: deadlineKey.flatMap { HomeModel.date(fromDayKey: $0) }
                ?? Calendar.current.date(byAdding: .day, value: 3, to: rowDay)
                ?? rowDay
        )
        _limitChoice = State(initialValue: BumpLimitChoice(limit))
        _days = State(initialValue: limit.storedDays > 0 ? limit.storedDays : 3)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Date", selection: $deadline, displayedComponents: .date)
                    }
                }

                Section {
                    Picker("Bump limit", selection: $limitChoice) {
                        Text("Can't bump").tag(BumpLimitChoice.cantBump)
                        Text("Up to a number of days").tag(BumpLimitChoice.upToDays)
                        Text("Until the end of the week").tag(BumpLimitChoice.endOfWeek)
                        if hasDeadline {
                            Text("Until the deadline").tag(BumpLimitChoice.untilDeadline)
                        }
                        Text("Unlimited").tag(BumpLimitChoice.unlimited)
                    }
                    if limitChoice == .upToDays {
                        Stepper("Up to \(days) \(days == 1 ? "day" : "days")", value: $days, in: 1...30)
                    }
                } header: {
                    Text("Bumping")
                } footer: {
                    Text("Changes this task only. A bump to tomorrow carries these with it.")
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onChange(of: hasDeadline) { _, isOn in
                if !isOn, limitChoice == .untilDeadline {
                    limitChoice = .upToDays
                }
            }
        }
    }

    private func save() {
        let deadlineKey = hasDeadline ? HomeModel.dayKey(for: deadline) : nil
        let limit = limitChoice.limit(days: days, deadlineDayKey: deadlineKey) ?? .defaultForNewOneOffs
        onSave(trimmedTitle, limit, deadlineKey)
        dismiss()
    }
}
