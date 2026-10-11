import SwiftData
import SwiftUI

/// The sticky note: the morning, day or evening list, with each row's long-press menu
/// (DECISIONS.md, 2b). Tap and swipe complete; the menu carries skip, bump, edit and delete.
struct HomeStickyNoteCard: View {
    @ObservedObject var vm: HomeViewModel
    let modelContext: ModelContext
    var onTaskRowSwipeActiveChange: (Bool) -> Void = { _ in }
    @State private var isShowingPastCompletePopup = false
    @State private var pendingPastCompleteTaskID: UUID?
    @State private var pendingPastCompleteTitle: String = ""
    /// Plain values, so the dialog never reads a row after it's deleted.
    @State private var pendingDeletion: DeletionRequest?
    @FocusState private var focusedField: SheetField?

    private enum SheetField {
        case pastComplete
    }

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
            if entries.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(entries) { entry in
                    row(for: entry, canEdit: vm.canCompleteSelectedDay, strikeColor: listTint(vm.contextualList)) {
                        if entry.list == .morning {
                            vm.toggleMorningEntry(entry, context: modelContext)
                        } else {
                            vm.toggleDailyTask(entry, context: modelContext)
                        }
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

            if vm.sortedDailyTasks.isEmpty {
                Text("No tasks for this day.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(vm.sortedDailyTasks) { task in
                    row(
                        for: task,
                        canEdit: vm.canCompleteSelectedDay || (vm.isReadOnly && !task.isCompleted),
                        strikeColor: urgencyColor(for: task.bumpCount)
                    ) {
                        handleDailyTaskToggle(task)
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
        .onChange(of: vm.dailyTasks.map(\.id)) { _, ids in
            if let pendingPastCompleteTaskID, !ids.contains(pendingPastCompleteTaskID) {
                clearPendingPastCompleteComposer()
            }
        }
        .onChange(of: isShowingPastCompletePopup) { _, isPresented in
            if isPresented {
                focusedField = .pastComplete
            }
        }
        .sheet(
            isPresented: $isShowingPastCompletePopup,
            onDismiss: clearPendingPastCompleteComposer
        ) {
            pastCompletePopupContent
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
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
            canEdit: canEdit,
            strikeColor: strikeColor,
            isDimmed: occurrence.state == .skipped,
            onHorizontalSwipeActivityChange: onTaskRowSwipeActiveChange,
            onToggle: onToggle
        ) {
            trailing(for: occurrence)
        }
        .contextMenu(isEnabled: !vm.isReadOnly) {
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
        if occurrence.state == .skipped {
            return "Skipped today"
        }
        if occurrence.state == .bumped {
            return "Bumped to tomorrow"
        }
        if occurrence.bumpCount > 0 {
            return "Bumped \(occurrence.bumpCount)×"
        }
        if occurrence.bumpLimit == .cantBump, !occurrence.isRepeating {
            return "Must happen today"
        }
        return nil
    }

    @ViewBuilder
    private func trailing(for occurrence: Occurrence) -> some View {
        if occurrence.state == .skipped {
            Image(systemName: "forward.end")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Skipped")
        } else if !occurrence.isRepeating, occurrence.state == .open {
            if occurrence.bumpLimit == .cantBump {
                Text("Must do")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let deadline = occurrence.deadlineDayKey {
                Text("Due \(BumpCost.format(deadline))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if !vm.isReadOnly, !vm.canBump(occurrence) {
                // Its bump limit is used up (bumps, deadline or end of week).
                Text("No bumps left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func urgencyColor(for bumpCount: Int) -> Color {
        let clamped = min(max(Double(bumpCount), 0), 5) / 5
        return Color(
            hue: 0.08 - (0.08 * clamped),
            saturation: 0.82,
            brightness: 0.95
        )
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

    // MARK: - Completing a past day's task

    private var pendingPastCompleteTask: Occurrence? {
        guard let pendingPastCompleteTaskID else { return nil }
        return vm.dailyTasks.first { $0.id == pendingPastCompleteTaskID }
    }

    private func handleDailyTaskToggle(_ task: Occurrence) {
        if vm.canCompleteSelectedDay {
            vm.toggleDailyTask(task, context: modelContext)
            return
        }

        guard vm.isReadOnly, !task.isCompleted else { return }
        presentPastCompleteComposer(for: task)
    }

    private func presentPastCompleteComposer(for task: Occurrence) {
        pendingPastCompleteTaskID = task.id
        pendingPastCompleteTitle = ""
        isShowingPastCompletePopup = true
        focusedField = .pastComplete
    }

    private func clearPendingPastCompleteComposer() {
        focusedField = nil
        pendingPastCompleteTaskID = nil
        pendingPastCompleteTitle = ""
        isShowingPastCompletePopup = false
    }

    private func submitPendingPastComplete() {
        guard let task = pendingPastCompleteTask else {
            clearPendingPastCompleteComposer()
            return
        }

        let didComplete = vm.completePastDailyTask(
            task,
            typedConfirmation: pendingPastCompleteTitle,
            context: modelContext
        )

        if didComplete {
            clearPendingPastCompleteComposer()
        }
    }

    private var pastCompletePopupContent: some View {
        let task = pendingPastCompleteTask

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mark as completed?")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    clearPendingPastCompleteComposer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel completion confirmation")
            }

            Text("Are you sure you completed this task? Type it in exactly to complete it.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\"\(task?.title ?? "")\"")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            TextField("Type task exactly...", text: $pendingPastCompleteTitle)
                .disabled(task == nil)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($focusedField, equals: .pastComplete)
                .submitLabel(.done)
                .onSubmit(submitPendingPastComplete)
                .frame(height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .onAppear {
            focusedField = .pastComplete
        }
    }
}
