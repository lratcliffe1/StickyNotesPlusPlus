import SwiftUI

/// The add menu's "Deadline…": a date for the next one-off, independent of its bump limit.
struct DeadlineSheet: View {
    let deadlineDayKey: String?
    let today: Date
    /// The chosen day key, or nil to remove the deadline.
    let onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(deadlineDayKey: String?, today: Date, onDone: @escaping (String?) -> Void) {
        self.deadlineDayKey = deadlineDayKey
        self.today = today
        self.onDone = onDone
        _date = State(
            initialValue: deadlineDayKey.flatMap { HomeModel.date(fromDayKey: $0) }
                ?? Calendar.current.date(byAdding: .day, value: 3, to: today)
                ?? today
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Deadline", selection: $date, in: today..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } footer: {
                    Text("A deadline doesn't change the bump limit. Choose “Until Deadline” under Bump Limit to let the task move only up to this day.")
                }

                if deadlineDayKey != nil {
                    Section {
                        Button(role: .destructive) {
                            onDone(nil)
                            dismiss()
                        } label: {
                            Label("Remove Deadline", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(HomeModel.dayKey(for: date))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
