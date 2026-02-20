import SwiftData
import SwiftUI

struct HomeStickyNoteCard: View {
    @ObservedObject var vm: HomeViewModel
    let modelContext: ModelContext
    var onTaskRowSwipeActiveChange: (Bool) -> Void = { _ in }
    @State private var isShowingBumpPopup = false
    @State private var pendingBumpTaskID: UUID?
    @State private var pendingBumpTitle: String = ""
    @FocusState private var isBumpTitleFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader

            ProgressView(value: vm.activeListProgress)
                .progressViewStyle(.linear)
                .tint(vm.isMorningMode ? .blue : .orange)
                .opacity(vm.activeListProgressIsImplicit ? 0.45 : 1)
                .accessibilityLabel("\(vm.activeListTitle) progress \(vm.activeListProgressPercent) percent")

            if vm.isMorningMode {
                morningList
            } else {
                dailyList
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.isMorningMode)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .padding(16)
        .background(AppTheme.stickyNoteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
    }

    private var cardHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(vm.activeListTitle)
                .font(.headline.weight(.bold))

            Spacer()

            HStack(spacing: 8) {
                Text("\(vm.activeListProgressPercent)%")
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
                .accessibilityLabel(vm.isMorningMode ? "Flip to daily tasks" : "Flip to morning routine")
            }
        }
    }

    private var morningList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.morningEntries.isEmpty {
                Text("No morning items yet. Add routine templates in Settings.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(vm.morningEntries) { entry in
                    InkStrikeRow(
                        title: entry.titleSnapshot,
                        subtitle: timeLabel(from: entry.targetTimeSnapshot),
                        isCompleted: entry.isCompleted,
                        canEdit: vm.canCompleteSelectedDay,
                        strikeColor: .blue,
                        onHorizontalSwipeActivityChange: onTaskRowSwipeActiveChange
                    ) {
                        vm.toggleMorningEntry(entry, context: modelContext)
                    } trailing: {
                        EmptyView()
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
                    InkStrikeRow(
                        title: task.title,
                        subtitle: dailySubtitle(for: task),
                        isCompleted: task.isCompleted,
                        canEdit: vm.canCompleteSelectedDay,
                        strikeColor: urgencyColor(for: task.bumpCount),
                        onHorizontalSwipeActivityChange: onTaskRowSwipeActiveChange
                    ) {
                        vm.toggleDailyTask(task, context: modelContext)
                    } trailing: {
                        if task.isBumpable, !task.isCompleted, !vm.isReadOnly {
                            Button {
                                presentBumpComposer(for: task)
                            } label: {
                                Image(systemName: "arrowshape.right.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(urgencyColor(for: task.bumpCount))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bump to tomorrow")
                        } else if !task.isBumpable {
                            Text("Must do")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onChange(of: vm.dailyTasks.map(\.id)) { _, ids in
            guard let pendingBumpTaskID else { return }
            guard !ids.contains(pendingBumpTaskID) else { return }
            clearPendingBumpComposer()
        }
        .sheet(
            isPresented: $isShowingBumpPopup,
            onDismiss: clearPendingBumpComposer
        ) {
            bumpPopupContent
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
        }
    }

    private var addTaskComposer: some View {
        HStack(spacing: 8) {
            TextField("Add a task...", text: newTaskTitleBinding)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .submitLabel(.done)
                .onSubmit {
                    vm.addDailyTask(context: modelContext)
                }

            Button("Add") {
                vm.addDailyTask(context: modelContext)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.chipSurface)
            .clipShape(Capsule())
            .disabled(!vm.canAddNewTask)
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

    private func timeLabel(from components: DateComponents?) -> String? {
        guard let components, let hour = components.hour, let minute = components.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func dailySubtitle(for task: DailyTask) -> String? {
        if task.bumpedTaskID != nil {
            return "Bumped to tomorrow"
        }
        if task.bumpCount > 0 {
            return "Bumped \(task.bumpCount)x"
        }
        if !task.isBumpable {
            return "Must happen today"
        }
        return nil
    }

    private func urgencyColor(for bumpCount: Int) -> Color {
        let clamped = min(max(Double(bumpCount), 0), 5) / 5
        return Color(
            hue: 0.08 - (0.08 * clamped),
            saturation: 0.82,
            brightness: 0.95
        )
    }

    private var pendingBumpTask: DailyTask? {
        guard let pendingBumpTaskID else { return nil }
        return vm.dailyTasks.first { $0.id == pendingBumpTaskID }
    }

    private func presentBumpComposer(for task: DailyTask) {
        pendingBumpTaskID = task.id
        pendingBumpTitle = ""
        isShowingBumpPopup = true
    }

    private func clearPendingBumpComposer() {
        pendingBumpTaskID = nil
        pendingBumpTitle = ""
        isBumpTitleFieldFocused = false
        isShowingBumpPopup = false
    }

    private func submitPendingBump() {
        guard let task = pendingBumpTask else {
            clearPendingBumpComposer()
            return
        }

        let title = pendingBumpTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        vm.bumpTaskToTomorrow(task, bumpedTitle: title, context: modelContext)
        clearPendingBumpComposer()
    }

    private var bumpPopupContent: some View {
        let task = pendingBumpTask

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bump \"\(task?.title ?? "")\"")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    clearPendingBumpComposer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel bump")
            }

            TextField("Task for tomorrow...", text: $pendingBumpTitle)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .submitLabel(.done)
                .focused($isBumpTitleFieldFocused)
                .onSubmit(submitPendingBump)
                .disabled(task == nil)

            Text("Press Enter to bump this task to tomorrow.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .onAppear {
            DispatchQueue.main.async {
                isBumpTitleFieldFocused = true
            }
        }
    }
}
