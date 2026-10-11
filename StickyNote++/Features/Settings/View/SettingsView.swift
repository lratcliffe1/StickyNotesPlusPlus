import SwiftData
import SwiftUI

/// Settings (DECISIONS.md, "3: flip times and settings"): a native grouped form with Lists ·
/// Morning (how it ends, the time) · Evening (start time or Off) · Bumping (Retype to bump).
/// A change to the morning or evening applies to today too; past days keep their own rules.
struct SettingsView: View {
    let now: () -> Date
    let defaults: UserDefaults
    var onListsChanged: () -> Void = {}
    /// The morning or evening settings changed (today's rules were rewritten).
    var onRulesChanged: () -> Void = {}

    @AppStorage private var retypeToBump: Bool
    @AppStorage private var morningEnd: DayRules.MorningEnd
    @AppStorage private var morningEndMinutes: Int
    @AppStorage private var eveningEnabled: Bool
    @AppStorage private var eveningStartMinutes: Int

    init(
        defaults: UserDefaults = SharedPersistence.sharedDefaults,
        now: @escaping () -> Date = { Date() },
        onListsChanged: @escaping () -> Void = {},
        onRulesChanged: @escaping () -> Void = {}
    ) {
        self.now = now
        self.defaults = defaults
        self.onListsChanged = onListsChanged
        self.onRulesChanged = onRulesChanged
        // A saved wake-up window becomes a set time before the pickers read it.
        AppSettings.migrateWakeUpWindowIfNeeded(in: defaults)
        _retypeToBump = AppStorage(wrappedValue: AppSettings.defaultRetypeToBump, AppSettings.retypeToBumpKey, store: defaults)
        _morningEnd = AppStorage(wrappedValue: AppSettings.defaultMorningEnd, AppSettings.morningEndKey, store: defaults)
        _morningEndMinutes = AppStorage(
            wrappedValue: AppSettings.defaultMorningCutoffMinutes, AppSettings.morningCutoffMinutesKey, store: defaults
        )
        _eveningEnabled = AppStorage(wrappedValue: AppSettings.defaultEveningEnabled, AppSettings.eveningEnabledKey, store: defaults)
        _eveningStartMinutes = AppStorage(
            wrappedValue: AppSettings.defaultEveningStartMinutes, AppSettings.eveningStartMinutesKey, store: defaults
        )
    }

    var body: some View {
        Form {
            listsSection
            morningSection
            eveningSection
            bumpingSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: morningEnd) { applyToToday() }
        .onChange(of: morningEndMinutes) { applyToToday() }
        .onChange(of: eveningEnabled) { applyToToday() }
        .onChange(of: eveningStartMinutes) { applyToToday() }
    }

    // MARK: - Sections

    private var listsSection: some View {
        Section {
            NavigationLink {
                EditListsView(now: now, onChange: onListsChanged)
            } label: {
                Label("Edit Lists", systemImage: "list.bullet")
            }
            NavigationLink {
                AddDailyTaskView()
            } label: {
                Label("Add a Task on Another Day", systemImage: "calendar.badge.plus")
            }
        } header: {
            Text("Lists")
        } footer: {
            Text("The items on your morning, day and evening lists, and how often they repeat.")
        }
    }

    private var morningSection: some View {
        Section {
            Picker("Morning Ends", selection: $morningEnd) {
                Text("Ends at a Set Time").tag(DayRules.MorningEnd.setTime)
                Text("Ends When Everything’s Done or Skipped").tag(DayRules.MorningEnd.doneOrSkipped)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityLabel("Morning ends")

            if morningEnd == .setTime {
                DatePicker("Time", selection: timeBinding($morningEndMinutes), displayedComponents: .hourAndMinute)
                    .accessibilityLabel("Morning ends at")
            }
        } header: {
            Text("Morning")
        } footer: {
            Text(morningFooter)
        }
    }

    private var eveningSection: some View {
        Section {
            Toggle("Switch to Evening List", isOn: $eveningEnabled)
            if eveningEnabled {
                DatePicker("Starts At", selection: timeBinding($eveningStartMinutes), displayedComponents: .hourAndMinute)
                    .accessibilityLabel("Evening starts at")
            }
        } header: {
            Text("Evening")
        } footer: {
            Text(eveningEnabled
                 ? "From this time until midnight Home shows your evening list. Finish it by midnight to keep the evening streak."
                 : "Off: Home doesn’t switch to the evening list on its own. The flip button still shows it.")
        }
    }

    private var bumpingSection: some View {
        Section {
            Toggle(isOn: $retypeToBump) {
                Label("Retype to Bump", systemImage: "keyboard")
            }
            // The widget's bump button follows this setting.
            .onChange(of: retypeToBump) { _, _ in
                TaskWidgetReloader.reloadTopTasksWidget()
            }
        } header: {
            Text("Bumping")
        } footer: {
            Text(retypeToBump
                 ? "On: to bump a task to tomorrow you type it again (you can change it). The widget's bump button opens the app to do it."
                 : "Off: the bump sheet fills in the title; you just confirm. The widget bumps in one tap.")
        }
    }

    private var morningFooter: String {
        let change = "Changes count from today; earlier days keep the times they had."
        switch morningEnd {
        case .setTime:
            return "Home shows the morning list until it’s done or this time comes. Finish by then to keep the morning streak. \(change)"
        case .doneOrSkipped:
            return "Home shows the morning list until everything on it is done or skipped, or until 12:00. Finish by 12:00 to keep the morning streak. \(change)"
        }
    }

    // MARK: - Helpers

    /// Minutes after midnight, edited as a time of day.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { AppSettings.date(fromMinutes: minutes.wrappedValue, on: now()) },
            set: { minutes.wrappedValue = AppSettings.minutesFromMidnight(from: $0) }
        )
    }

    /// Today takes the new rules as well (it isn't over); past days keep theirs.
    private func applyToToday() {
        ListService.applySettingsToToday(now: now(), defaults: defaults)
        onRulesChanged()
    }
}

#Preview {
    let schema = SharedPersistence.appSchema()

    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

    return NavigationStack {
        SettingsView()
    }
    .modelContainer(container)
}
