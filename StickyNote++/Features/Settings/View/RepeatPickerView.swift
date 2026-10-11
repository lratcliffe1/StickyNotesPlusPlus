import SwiftUI

/// The repeat picker, after Apple Reminders (DECISIONS.md, "Repeats follow Apple Reminders"):
/// Daily, Weekdays, Weekends, Weekly (chosen days), Every 2 Weeks, Monthly, Yearly, and Custom
/// (every N days, weeks on chosen days, or months). "Never" isn't offered: a one-off is added on Home.
struct RepeatPickerView: View {
    @Binding var rule: RepeatRule
    /// The weekday a weekly rule falls on when no days are chosen (the item's start day).
    let defaultWeekday: Int

    private let calendar = Calendar.current

    private enum Preset: CaseIterable, Hashable {
        case daily, weekdays, weekends, weekly, everyTwoWeeks, monthly, yearly, custom

        var title: String {
            switch self {
            case .daily: return "Daily"
            case .weekdays: return "Weekdays"
            case .weekends: return "Weekends"
            case .weekly: return "Weekly"
            case .everyTwoWeeks: return "Every 2 Weeks"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            case .custom: return "Custom"
            }
        }
    }

    private enum Frequency: Hashable {
        case days, weeks, months
    }

    var body: some View {
        Form {
            Section {
                ForEach(Preset.allCases, id: \.self) { preset in
                    Button {
                        select(preset)
                    } label: {
                        HStack {
                            Text(preset.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if currentPreset == preset {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(currentPreset == preset ? .isSelected : [])
                }
            } footer: {
                Text("A change applies from today; earlier days keep what they had.")
            }

            if currentPreset == .custom {
                Section("Custom") {
                    Picker("Frequency", selection: frequencyBinding) {
                        Text("Days").tag(Frequency.days)
                        Text("Weeks").tag(Frequency.weeks)
                        Text("Months").tag(Frequency.months)
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: intervalBinding, in: 1...99) {
                        Text("Every \(rule.interval) \(unitName)")
                    }
                }
            }

            if showsWeekdays {
                Section("On") {
                    ForEach(RepeatRule.weekdayOrder(calendar: calendar), id: \.self) { weekday in
                        Button {
                            toggle(weekday)
                        } label: {
                            HStack {
                                Text(calendar.weekdaySymbols[weekday - 1])
                                    .foregroundStyle(.primary)
                                Spacer()
                                if chosenWeekdays.contains(weekday) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosenWeekdays.contains(weekday) ? .isSelected : [])
                    }
                }
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - State

    private var currentPreset: Preset {
        switch rule.kind {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekends: return .weekends
        case .weekly: return .weekly
        case .everyTwoWeeks: return .everyTwoWeeks
        case .monthly: return .monthly
        case .yearly: return .yearly
        case .everyNDays, .everyNWeeks, .everyNMonths: return .custom
        }
    }

    private var showsWeekdays: Bool {
        rule.kind == .weekly || rule.kind == .everyTwoWeeks || rule.kind == .everyNWeeks
    }

    private var chosenWeekdays: Set<Int> {
        rule.weekdays.isEmpty ? [defaultWeekday] : rule.weekdays
    }

    private var unitName: String {
        switch rule.kind {
        case .everyNWeeks: return rule.interval == 1 ? "week" : "weeks"
        case .everyNMonths: return rule.interval == 1 ? "month" : "months"
        default: return rule.interval == 1 ? "day" : "days"
        }
    }

    private func select(_ preset: Preset) {
        guard preset != currentPreset else { return }
        switch preset {
        case .daily: rule = .daily
        case .weekdays: rule = .weekdays
        case .weekends: rule = .weekends
        case .weekly: rule = .weekly(on: chosenWeekdays)
        case .everyTwoWeeks: rule = RepeatRule(kind: .everyTwoWeeks, weekdays: chosenWeekdays)
        case .monthly: rule = .monthly
        case .yearly: rule = .yearly
        case .custom: rule = .everyNDays(2)
        }
    }

    private var frequencyBinding: Binding<Frequency> {
        Binding(
            get: {
                switch rule.kind {
                case .everyNWeeks: return .weeks
                case .everyNMonths: return .months
                default: return .days
                }
            },
            set: { frequency in
                switch frequency {
                case .days: rule = .everyNDays(rule.interval)
                case .weeks: rule = .everyNWeeks(rule.interval, on: chosenWeekdays)
                case .months: rule = .everyNMonths(rule.interval)
                }
            }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { rule.interval },
            set: { rule = RepeatRule(kind: rule.kind, interval: $0, weekdays: rule.weekdays) }
        )
    }

    /// Never leaves a weekly rule with no day.
    private func toggle(_ weekday: Int) {
        var days = chosenWeekdays
        if days.contains(weekday) {
            guard days.count > 1 else { return }
            days.remove(weekday)
        } else {
            days.insert(weekday)
        }
        rule = RepeatRule(kind: rule.kind, interval: rule.interval, weekdays: days)
    }
}
