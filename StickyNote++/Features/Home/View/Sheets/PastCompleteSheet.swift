import SwiftUI

/// A forgotten tick on a past day (DECISIONS.md, 2026-10-16, fix round 3), any list: type the
/// title exactly to mark it done. Mark Done stays disabled until it matches. The footer says when
/// the tick counts (`BackfillRules`) and that it can't be undone.
struct PastCompleteSheet: View {
    let occurrence: Occurrence
    /// "Yesterday", or the day's date.
    let dayLabel: String
    let footer: String
    /// Returns whether the tick happened.
    let onComplete: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var isFocused: Bool

    private var matches: Bool {
        BackfillRules.confirms(typed, title: occurrence.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(occurrence.title, text: $typed)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit(complete)
                        .accessibilityLabel("Type \(occurrence.title) to confirm")
                } header: {
                    Text("Did you do “\(occurrence.title)”?")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Mark Done for \(dayLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Done", action: complete)
                        .fontWeight(.semibold)
                        .disabled(!matches)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func complete() {
        guard matches else { return }
        if onComplete(typed) {
            dismiss()
        }
    }
}
