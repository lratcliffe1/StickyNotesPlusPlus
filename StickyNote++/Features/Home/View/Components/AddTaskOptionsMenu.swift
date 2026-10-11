import SwiftUI

/// The options menu next to the add field (tap or long-press; DECISIONS.md, 2b): must happen today
/// (can't bump), a deadline, and a bump limit. A plain add keeps the default, up to 3 days.
struct AddTaskOptionsMenu: View {
    @ObservedObject var vm: HomeViewModel

    private enum LimitOption: Hashable {
        case days(Int)
        case endOfWeek
        case untilDeadline
        case unlimited
    }

    var body: some View {
        Menu {
            Toggle(isOn: $vm.newTaskOptions.mustHappenToday) {
                Label("Must Happen Today", systemImage: "exclamationmark.circle")
            }

            Button {
                vm.activeSheet = .deadline
            } label: {
                Label(deadlineTitle, systemImage: "calendar")
            }

            Picker(selection: limitBinding) {
                Text("Up to 1 Day").tag(LimitOption.days(1))
                Text("Up to 3 Days").tag(LimitOption.days(3))
                Text("Up to 7 Days").tag(LimitOption.days(7))
                Text("End of Week").tag(LimitOption.endOfWeek)
                Text("Until Deadline").tag(LimitOption.untilDeadline)
                Text("Unlimited").tag(LimitOption.unlimited)
            } label: {
                Label("Bump Limit", systemImage: "arrow.clockwise")
            }
            .pickerStyle(.menu)
            .disabled(vm.newTaskOptions.mustHappenToday)

            if !vm.newTaskOptions.isDefault {
                Divider()
                Button {
                    vm.newTaskOptions = OneOffOptions()
                } label: {
                    Label("Reset Options", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: vm.newTaskOptions.isDefault ? "ellipsis.circle" : "ellipsis.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(vm.newTaskOptions.isDefault ? .secondary : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.chipSurface)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
        }
        .accessibilityLabel("Task options")
        .accessibilityValue(Self.summary(of: vm.newTaskOptions) ?? "Up to 3 days")
    }

    private var deadlineTitle: String {
        guard let deadline = vm.newTaskOptions.deadlineDayKey else { return "Deadline…" }
        return "Deadline: \(BumpCost.format(deadline))…"
    }

    private var limitBinding: Binding<LimitOption> {
        Binding(
            get: {
                let options = vm.newTaskOptions
                switch options.limitChoice {
                case .upToDays: return .days(options.days)
                case .endOfWeek: return .endOfWeek
                case .untilDeadline: return .untilDeadline
                case .unlimited, .cantBump: return .unlimited
                }
            },
            set: { option in
                switch option {
                case let .days(days):
                    vm.newTaskOptions.limitChoice = .upToDays
                    vm.newTaskOptions.days = days
                case .endOfWeek:
                    vm.newTaskOptions.limitChoice = .endOfWeek
                case .untilDeadline:
                    if vm.newTaskOptions.deadlineDayKey == nil {
                        // Restored if the date sheet is cancelled (`revertUnsetDeadlineChoice`).
                        vm.optionsBeforeDeadlinePick = vm.newTaskOptions
                        vm.activeSheet = .deadline
                    }
                    vm.newTaskOptions.limitChoice = .untilDeadline
                case .unlimited:
                    vm.newTaskOptions.limitChoice = .unlimited
                }
            }
        )
    }

    /// The options in words, shown under the add field when they aren't the default (so the state
    /// reads without colour). Nil for the default.
    static func summary(of options: OneOffOptions) -> String? {
        guard !options.isDefault else { return nil }
        var parts: [String] = []
        switch options.bumpLimit {
        case .cantBump:
            parts.append("Must happen today")
        case let .upToDays(days):
            if days != 3 { parts.append("Bump up to \(days) \(days == 1 ? "day" : "days")") }
        case .endOfWeek:
            parts.append("Bump until end of week")
        case .untilDeadline:
            parts.append("Bump until deadline")
        case .unlimited:
            parts.append("No bump limit")
        }
        if let deadline = options.deadlineDayKey {
            parts.append("Deadline \(BumpCost.format(deadline))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
