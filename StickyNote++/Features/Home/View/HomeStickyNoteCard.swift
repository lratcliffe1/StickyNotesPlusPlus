import SwiftData
import SwiftUI

/// The sticky note: the morning, day or evening list, with each row's long-press menu
/// (DECISIONS.md, 2b). Tap and swipe complete; the menu carries skip, bump, edit and delete.
struct HomeStickyNoteCard: View {
    @ObservedObject var vm: HomeViewModel
    let modelContext: ModelContext
    var onTaskRowSwipeActiveChange: (Bool) -> Void = { _ in }
    /// Plain values, so the dialog never reads a row after it's deleted.
    @State private var pendingDeletion: DeletionRequest?

    private struct DeletionRequest {
        let id: UUID
        let title: String
        let isRepeating: Bool
        let wasBumpedIn: Bool

        init(_ occurrence: Occurrence) {
            id = occurrence.id
            title = occurrence.title
            isRepeating = occurrence.isRepeating
            wasBumpedIn = occurrence.bumpedFromID != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader

            ProgressView(value: vm.activeListProgress)
                .progressViewStyle(.linear)
                .tint(listTint(vm.contextualList))
                .opacity(vm.activeListProgressIsNeutral ? 0.45 : 1)
                .accessibilityLabel(
                    vm.activeListProgressIsNeutral
                        ? "\(vm.activeListTitle): nothing to count"
                        : "\(vm.activeListTitle) progress \(vm.activeListProgressPercent) percent"
                )

            switch vm.contextualList {
            case .morning:
                routineList(vm.morningEntries, emptyText: "No morning items yet. Add them in Settings → Edit Lists.")
            case .daily:
                dailyList
            case .evening:
                routineList(vm.eveningEntries, emptyText: "No evening items yet. Add them in Settings → Edit Lists.")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.contextualList)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .padding(16)
        .background(AppTheme.stickyNoteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
        .sheet(item: $vm.activeSheet, onDismiss: { vm.revertUnsetDeadlineChoice() }) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { request in
            Button(request.isRepeating ? "Delete from Today On" : "Delete", role: .destructive) {
                if let occurrence = vm.occurrence(id: request.id, context: modelContext) {
                    vm.delete(occurrence, context: modelContext)
                }
            }
        } message: { request in
            Text(deletionMessage(for: request))
        }
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(vm.activeListTitle)
            } icon: {
                Image(systemName: listIcon(vm.contextualList))
            }
            .font(.headline.weight(.bold))

            Spacer()

            HStack(spacing: 8) {
                Text(vm.activeListProgressText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        vm.flipStickyNoteList()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.chipSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flip to \(vm.nextListTitle.lowercased())")
            }
        }
    }

    private func listIcon(_ list: HomeModel.ContextualList) -> String {
        switch list {
        case .morning: return "sun.max"
        case .daily: return "checklist"
        case .evening: return "moon"
        }
    }

    private func listTint(_ list: HomeModel.ContextualList) -> Color {
        switch list {
        case .morning: return .blue
        case .daily: return .orange
        case .evening: return .indigo
        }
    }

    // MARK: - Lists

    /// The morning or evening list: recurring items (and any one-offs bumped onto it).
    private func routineList(_ entries: [Occurrence], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if entries.isEmpty && vm.activePlannedItems.isEmpty {
                Text(vm.isFutureDay ? "Nothing planned for this day." : emptyText)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                plannedRows
                ForEach(entries) { entry in
                    row(
                        for: entry,
                        canEdit: vm.canCompleteSelectedDay || vm.canCompletePast(entry),
                        strikeColor: listTint(vm.contextualList)
                    ) {
                        handleToggle(entry)
                    }
                }
            }
        }
    }

    private var dailyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.isReadOnly {
                addTaskComposer
            }

            if vm.sortedDailyTasks.isEmpty && vm.activePlannedItems.isEmpty {
                Text("No tasks for this day.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                plannedRows
                ForEach(vm.sortedDailyTasks) { task in
                    row(
                        for: task,
                        canEdit: vm.canCompleteSelectedDay || vm.canCompletePast(task),
                        strikeColor: listTint(vm.contextualList)
                    ) {
                        handleToggle(task)
                    }
                    .draggable(task.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let rawID = items.first, let draggedID = UUID(uuidString: rawID) else {
                            return false
                        }
                        vm.reorderDailyTask(
                            draggedID: draggedID,
                            over: task.id,
                            context: modelContext
                        )
                        return true
                    }
                }
            }
        }
    }

    /// A future day's recurring items, before they have rows: read-only until the day comes
    /// (provisional, step 4). Recurring items come first, as on the day itself.
    @ViewBuilder
    private var plannedRows: some View {
        ForEach(vm.activePlannedItems) { item in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("Repeats · can be done on the day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "repeat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), repeats, planned for this day")
        }
    }

    private func row(
        for occurrence: Occurrence,
        canEdit: Bool,
        strikeColor: Color,
        onToggle: @escaping () -> Void
    ) -> some View {
        InkStrikeRow(
            title: occurrence.title,
            subtitle: subtitle(for: occurrence),
            isCompleted: occurrence.isCompleted,
            // A row the vault moved to a later day is history: the live task is the new row.
            canEdit: canEdit && vm.movedTo(occurrence) == nil,
            strikeColor: strikeColor,
            isDimmed: occurrence.state == .skipped,
            onHorizontalSwipeActivityChange: onTaskRowSwipeActiveChange,
            onToggle: onToggle
        ) {
            trailing(for: occurrence)
        }
        .contextMenu(isEnabled: vm.hasRowMenu(occurrence)) {
            rowMenu(for: occurrence)
        }
    }

    // MARK: - Row menu (long press)

    @ViewBuilder
    private func rowMenu(for occurrence: Occurrence) -> some View {
        if occurrence.isRepeating && vm.canCompleteSelectedDay {
            if occurrence.state == .skipped {
                Button {
                    vm.unskip(occurrence, context: modelContext)
                } label: {
                    Label("Undo Skip", systemImage: "arrow.uturn.backward")
                }
            } else if occurrence.state == .open {
                Button {
                    vm.skip(occurrence, context: modelContext)
                } label: {
                    Label("Skip Today", systemImage: "forward.end")
                }
            }
        }

        if vm.canBump(occurrence) {
            Button {
                vm.activeSheet = .bump(occurrence.id)
            } label: {
                Label("Bump…", systemImage: "arrow.clockwise")
            }
        }

        // A row whose item has ended (deleted, or replaced by a repeat change) has no Edit… or
        // Delete: the old item isn't the one to change, and its replacement can't be told apart.
        if vm.canEditOrDelete(occurrence) {
            Button {
                if let itemID = occurrence.itemID {
                    vm.activeSheet = .editItem(itemID)
                } else {
                    vm.activeSheet = .editOneOff(occurrence.id)
                }
            } label: {
                Label("Edit…", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                pendingDeletion = DeletionRequest(occurrence)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var deletionTitle: String {
        guard let pendingDeletion else { return "Delete?" }
        return pendingDeletion.isRepeating
            ? "Delete “\(pendingDeletion.title)” from today on?"
            : "Delete “\(pendingDeletion.title)”?"
    }

    private func deletionMessage(for request: DeletionRequest) -> String {
        if request.isRepeating {
            return "It stops repeating from today. Earlier days keep it."
        }
        if request.wasBumpedIn {
            return "The day it was bumped from goes back to not done."
        }
        return "This can't be undone."
    }

    // MARK: - Row text

    private func subtitle(for occurrence: Occurrence) -> String? {
        if let movedTo = vm.movedTo(occurrence) {
            // Moved to a later day in Now.md: neutral like a skip (fix round 2). "" once the task
            // has no later row (it left Now.md, or that row went).
            return movedTo.isEmpty ? "No longer planned" : "Moved to \(BumpCost.format(movedTo))"
        }
        if occurrence.state == .skipped {
            return "Skipped today"
        }
        if occurrence.state == .bumped {
            return "Bumped to tomorrow"
        }
        if vm.isBonus(occurrence) {
            // Added after the morning's cutoff: shown and tickable, never counted (fix round 1).
            return "Added after the cutoff · doesn't count"
        }
        if occurrence.bumpLimit == .cantBump, !occurrence.isRepeating {
            return "Must happen today"
        }
        return nil
    }

    @ViewBuilder
    private func trailing(for occurrence: Occurrence) -> some View {
        HStack(spacing: 8) {
            trailingNote(for: occurrence)
            if occurrence.bumpCount > 0 {
                BumpCountMark(count: occurrence.bumpCount)
            }
        }
    }

    @ViewBuilder
    private func trailingNote(for occurrence: Occurrence) -> some View {
        if vm.movedTo(occurrence) != nil {
            // A status, not a disclosure; the subtitle already says it, so VoiceOver skips it.
            Image(systemName: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else if occurrence.state == .skipped {
            Image(systemName: "forward.end")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Skipped")
        } else if !occurrence.isRepeating, occurrence.state == .open || occurrence.state == .done {
            // "Must do" and "Due …" stay once ticked (fix round 1); "No bumps left" is open only.
            if occurrence.bumpLimit == .cantBump {
                Text("Must do")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let deadline = occurrence.deadlineDayKey {
                Text("Due \(BumpCost.format(deadline))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if occurrence.state == .open, !vm.isReadOnly, !vm.isFutureDay, !vm.canBump(occurrence) {
                // Its bump limit is used up (bumps, deadline or end of week).
                Text("No bumps left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Adding a one-off

    private var addTaskComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Add a task...", text: newTaskTitleBinding)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit {
                        _ = vm.addDailyTask(context: modelContext)
                    }

                AddTaskOptionsMenu(vm: vm)
            }

            if let summary = AddTaskOptionsMenu.summary(of: vm.newTaskOptions) {
                Text(summary)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0)
    }

    private var newTaskTitleBinding: Binding<String> {
        Binding(
            get: { vm.newTaskTitle },
            set: { vm.updateNewTaskTitle($0) }
        )
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: HomeSheet) -> some View {
        switch sheet {
        case let .bump(id):
            if let occurrence = vm.occurrence(id: id, context: modelContext) {
                BumpSheet(
                    occurrence: occurrence,
                    costs: (try? ListService.bumpCosts(for: occurrence, context: modelContext)) ?? [],
                    retypeRequired: vm.retypeToBump
                ) { typed in
                    vm.bump(occurrence, typedTitle: typed, context: modelContext)
                }
            } else {
                missingSheet
            }
        case let .editOneOff(id):
            if let occurrence = vm.occurrence(id: id, context: modelContext) {
                OneOffEditorView(occurrence: occurrence) { title, limit, deadline in
                    vm.editOneOff(occurrence, title: title, bumpLimit: limit, deadlineDayKey: deadline, context: modelContext)
                }
            } else {
                missingSheet
            }
        case let .editItem(itemID):
            if let item = try? ListService.item(id: itemID, context: modelContext) {
                ItemEditorView(mode: .edit(item), now: { vm.now }) {
                    vm.itemsDidChange(context: modelContext)
                }
            } else {
                missingSheet
            }
        case let .completePast(id):
            // No state check here: the row is done the moment the sheet closes, and the view model
            // refuses anything that can't be ticked.
            if let occurrence = vm.occurrence(id: id, context: modelContext) {
                PastCompleteSheet(
                    occurrence: occurrence,
                    dayLabel: vm.selectedDayRelativeLabel,
                    footer: vm.pastCompleteFooter(for: occurrence)
                ) { typed in
                    vm.completePastOccurrence(occurrence, typedConfirmation: typed, context: modelContext)
                }
            } else {
                missingSheet
            }
        case .deadline:
            DeadlineSheet(
                deadlineDayKey: vm.newTaskOptions.deadlineDayKey,
                today: HomeModel.normalizedDay(vm.now)
            ) { newDeadline in
                vm.newTaskOptions.deadlineDayKey = newDeadline
                if newDeadline == nil, vm.newTaskOptions.limitChoice == .untilDeadline {
                    vm.newTaskOptions.limitChoice = .upToDays
                }
            }
        }
    }

    private var missingSheet: some View {
        ContentUnavailableView("Not found", systemImage: "questionmark.circle", description: Text("It may have been changed elsewhere."))
            .presentationDetents([.medium])
    }

    // MARK: - Ticking

    /// Today: tick or untick. A past day: an open row opens the retype sheet (fix round 3).
    private func handleToggle(_ occurrence: Occurrence) {
        if vm.canCompleteSelectedDay {
            if occurrence.list == .morning {
                vm.toggleMorningEntry(occurrence, context: modelContext)
            } else {
                vm.toggleDailyTask(occurrence, context: modelContext)
            }
        } else if vm.canCompletePast(occurrence) {
            vm.activeSheet = .completePast(occurrence.id)
        }
    }
}

/// "↻2": how many times a task has been bumped, in bold, in place of a colour scale
/// (DECISIONS.md, 2026-10-11 evening, "5: greyscale").
private struct BumpCountMark: View {
    let count: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: "arrow.clockwise")
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bumped \(count) \(count == 1 ? "time" : "times")")
    }
}
