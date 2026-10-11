import SwiftData
import SwiftUI
import os

/// Settings (DECISIONS.md, "3: flip times and settings"): a native grouped form with Lists ·
/// Morning (how it ends, the time) · Evening (start time or Off) · Bumping (Retype to bump) ·
/// Vault (the vault link, step 6).
/// An evening change applies today; a morning change applies today only while this morning is
/// still undecided, otherwise from tomorrow (`DayRules.todayAfterChange`). Past days keep theirs.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    /// Today's stored rules, when their morning differs from the settings (the change waits for
    /// tomorrow): shown as a line in the Morning footer.
    @State private var todayKeeps: DayRules?
    /// Today's record as it was when Settings opened (with its day): every change in this visit
    /// is judged from it, so a half-made edit never sticks.
    @State private var original: (dayKey: String, rules: DayRules)?

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
            VaultLinkSettingsSection()
        }
        .vaultLinkHarnessDestination()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: morningEnd) { applyToToday() }
        .onChange(of: morningEndMinutes) { applyToToday() }
        .onChange(of: eveningEnabled) { applyToToday() }
        .onChange(of: eveningStartMinutes) { applyToToday() }
        .onAppear {
            // Once per visit (not again on returning from Edit Lists), unless the day changed.
            let current = now()
            let todayKey = HomeModel.dayKey(for: current)
            if original?.dayKey != todayKey {
                original = (todayKey, ListService.todaysRules(now: current, defaults: defaults))
            }
            readTodaysRules()
        }
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
            VStack(alignment: .leading, spacing: 4) {
                if let todayKeeps {
                    Text(todayKeepsLine(todayKeeps))
                        .fontWeight(.semibold)
                }
                Text(morningFooter)
            }
        }
    }

    private var eveningSection: some View {
        Section {
            Toggle("Switch to Evening List", isOn: $eveningEnabled)
            if eveningEnabled {
                DatePicker(
                    "Starts At",
                    selection: timeBinding($eveningStartMinutes, clamp: AppSettings.clampedEveningStart),
                    in: eveningRange,
                    displayedComponents: .hourAndMinute
                )
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
        let change = "A change counts from today only while this morning is still open; otherwise from tomorrow."
        switch morningEnd {
        case .setTime:
            return "Home shows the morning list until it’s done or this time comes. Finish by then to keep the morning streak. \(change)"
        case .doneOrSkipped:
            return "Home shows the morning list until everything on it is done or skipped. Finish by 12:00 to keep the morning streak. \(change)"
        }
    }

    /// "Today keeps 9:00; this applies from tomorrow."
    private func todayKeepsLine(_ rules: DayRules) -> String {
        let kept: String
        switch rules.morningEnd {
        case .setTime:
            kept = AppSettings.date(fromMinutes: rules.morningEndMinutes, on: now()).formatted(date: .omitted, time: .shortened)
        case .doneOrSkipped:
            kept = "“done or skipped” (12:00)"
        }
        return "Today keeps \(kept); this applies from tomorrow."
    }

    private var eveningRange: ClosedRange<Date> {
        let day = now()
        return AppSettings.date(fromMinutes: AppSettings.eveningStartRange.lowerBound, on: day)
            ... AppSettings.date(fromMinutes: AppSettings.eveningStartRange.upperBound, on: day)
    }

    // MARK: - Helpers

    /// Minutes after midnight, edited as a time of day (kept within `clamp`'s range).
    private func timeBinding(_ minutes: Binding<Int>, clamp: @escaping (Int) -> Int = { $0 }) -> Binding<Date> {
        Binding(
            get: { AppSettings.date(fromMinutes: clamp(minutes.wrappedValue), on: now()) },
            set: { minutes.wrappedValue = clamp(AppSettings.minutesFromMidnight(from: $0)) }
        )
    }

    /// Rewrites today's rules: the evening always, the morning only while it's undecided.
    private func applyToToday() {
        do {
            let current = now()
            let snapshot = original.flatMap { $0.dayKey == HomeModel.dayKey(for: current) ? $0.rules : nil }
            try ListService.applySettingsToToday(now: current, defaults: defaults, original: snapshot, context: modelContext)
        } catch {
            AppLogger.persistence.error("Applying settings to today failed: \(error.localizedDescription, privacy: .public)")
        }
        readTodaysRules()
        onRulesChanged()
    }

    private func readTodaysRules() {
        let todayKey = HomeModel.dayKey(for: now())
        let today = DayRulesStore.resolvedHistory(in: defaults, todayKey: todayKey).rules(for: todayKey)
        todayKeeps = today.hasSameMorning(as: AppSettings.currentRules(in: defaults)) ? nil : today
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
