import SwiftUI

/// "Bump to tomorrow" (DECISIONS.md, 2b): what the bump costs, and the title for tomorrow.
/// With Retype to bump on, the field starts empty with the old title as its placeholder, and Bump
/// stays disabled until something is typed; the typed title (it may differ) becomes the copy's.
/// With it off, the field starts filled in.
struct BumpSheet: View {
    let occurrence: Occurrence
    let costs: [BumpCost]
    let retypeRequired: Bool
    /// Returns whether the bump happened.
    let onBump: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var typed: String
    @FocusState private var isFocused: Bool

    init(occurrence: Occurrence, costs: [BumpCost], retypeRequired: Bool, onBump: @escaping (String) -> Bool) {
        self.occurrence = occurrence
        self.costs = costs
        self.retypeRequired = retypeRequired
        self.onBump = onBump
        _typed = State(initialValue: retypeRequired ? "" : occurrence.title)
    }

    private var bumpedTitle: String? {
        BumpRules.bumpedTitle(typed: typed, original: occurrence.title, retypeRequired: retypeRequired)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(occurrence.title, text: $typed)
                        .focused($isFocused)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit(bump)
                        .accessibilityLabel("Title for tomorrow")
                } header: {
                    Text(retypeRequired ? "Type it again" : "Title for tomorrow")
                } footer: {
                    Text(retypeRequired
                         ? "Retype to bump is on: type the task again to move it. You can change it."
                         : "You can change the title.")
                }

                if !costs.isEmpty {
                    Section("What it costs") {
                        ForEach(Array(costs.enumerated()), id: \.offset) { _, cost in
                            Label(cost.text(), systemImage: icon(for: cost))
                        }
                    }
                }
            }
            .navigationTitle("Bump to tomorrow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bump", action: bump)
                        .fontWeight(.semibold)
                        .disabled(bumpedTitle == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func bump() {
        guard bumpedTitle != nil else { return }
        if onBump(typed) {
            dismiss()
        }
    }

    private func icon(for cost: BumpCost) -> String {
        switch cost {
        case .bumpsUsed: return "number"
        case .deadline, .endOfWeek: return "calendar"
        case .periodEnd: return "repeat"
        case .unlimited: return "infinity"
        }
    }
}
