import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HomeStickyNoteCard: View {
    @ObservedObject var vm: HomeViewModel
    let modelContext: ModelContext
    var onTaskRowSwipeActiveChange: (Bool) -> Void = { _ in }
    @State private var isShowingBumpPopup = false
    @State private var pendingBumpTaskID: UUID?
    @State private var pendingBumpTitle: String = ""
    @State private var bumpFocusToken = 0
    @State private var isShowingPastCompletePopup = false
    @State private var pendingPastCompleteTaskID: UUID?
    @State private var pendingPastCompleteTitle: String = ""
    @State private var pastCompleteFocusToken = 0
    @State private var newTaskMustHappenToday = false
    @State private var draggedDailyTaskID: UUID?

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
                        canEdit: vm.canCompleteSelectedDay || (vm.isReadOnly && !task.isCompleted),
                        strikeColor: urgencyColor(for: task.bumpCount),
                        onHorizontalSwipeActivityChange: onTaskRowSwipeActiveChange
                    ) {
                        handleDailyTaskToggle(task)
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
                    .onDrag {
                        draggedDailyTaskID = task.id
                        return NSItemProvider(object: task.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: DailyTaskDropDelegate(
                            targetTaskID: task.id,
                            draggedTaskID: $draggedDailyTaskID,
                            vm: vm,
                            context: modelContext
                        )
                    )
                }
            }
        }
        .onChange(of: vm.dailyTasks.map(\.id)) { _, ids in
            guard let pendingBumpTaskID else { return }
            guard !ids.contains(pendingBumpTaskID) else { return }
            clearPendingBumpComposer()
        }
        .onChange(of: vm.dailyTasks.map(\.id)) { _, ids in
            guard let pendingPastCompleteTaskID else { return }
            guard !ids.contains(pendingPastCompleteTaskID) else { return }
            clearPendingPastCompleteComposer()
        }
        .onChange(of: isShowingBumpPopup) { _, isPresented in
            if isPresented {
                scheduleBumpComposerFocus()
            }
        }
        .onChange(of: isShowingPastCompletePopup) { _, isPresented in
            if isPresented {
                schedulePastCompleteComposerFocus()
            }
        }
        .sheet(
            isPresented: $isShowingBumpPopup,
            onDismiss: clearPendingBumpComposer
        ) {
            bumpPopupContent
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
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

    private var addTaskComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Add a task...", text: newTaskTitleBinding)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit {
                        submitNewTask()
                    }
                Button {
                    newTaskMustHappenToday.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: newTaskMustHappenToday ? "checkmark.circle.fill" : "circle")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(newTaskMustHappenToday ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.chipSurface)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Must happen today")
                .accessibilityValue(newTaskMustHappenToday ? "On" : "Off")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0)
    }

    private func submitNewTask() {
        let didAdd = vm.addDailyTask(
            context: modelContext,
            mustHappenToday: newTaskMustHappenToday
        )

        if didAdd {
            newTaskMustHappenToday = false
        }
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
        scheduleBumpComposerFocus()
    }

    private func clearPendingBumpComposer() {
        bumpFocusToken += 1
        pendingBumpTaskID = nil
        pendingBumpTitle = ""
        isShowingBumpPopup = false
    }

    private var pendingPastCompleteTask: DailyTask? {
        guard let pendingPastCompleteTaskID else { return nil }
        return vm.dailyTasks.first { $0.id == pendingPastCompleteTaskID }
    }

    private func handleDailyTaskToggle(_ task: DailyTask) {
        if vm.canCompleteSelectedDay {
            vm.toggleDailyTask(task, context: modelContext)
            return
        }

        guard vm.isReadOnly, !task.isCompleted else { return }
        presentPastCompleteComposer(for: task)
    }

    private func presentPastCompleteComposer(for task: DailyTask) {
        pendingPastCompleteTaskID = task.id
        pendingPastCompleteTitle = ""
        isShowingPastCompletePopup = true
        schedulePastCompleteComposerFocus()
    }

    private func clearPendingPastCompleteComposer() {
        pastCompleteFocusToken += 1
        pendingPastCompleteTaskID = nil
        pendingPastCompleteTitle = ""
        isShowingPastCompletePopup = false
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

            BumpAutofocusTextField(
                text: $pendingBumpTitle,
                placeholder: "Task for tomorrow...",
                isEnabled: task != nil,
                focusToken: bumpFocusToken,
                onSubmit: submitPendingBump
            )
            .frame(height: 22)

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
            scheduleBumpComposerFocus()
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

            BumpAutofocusTextField(
                text: $pendingPastCompleteTitle,
                placeholder: "Type task exactly...",
                isEnabled: task != nil,
                focusToken: pastCompleteFocusToken,
                onSubmit: submitPendingPastComplete
            )
            .frame(height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14, fill: AnyShapeStyle(AppTheme.cardSurface), shadowOpacity: 0)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .onAppear {
            schedulePastCompleteComposerFocus()
        }
    }

    private func scheduleBumpComposerFocus() {
        bumpFocusToken += 1
    }

    private func schedulePastCompleteComposerFocus() {
        pastCompleteFocusToken += 1
    }
}

private struct DailyTaskDropDelegate: DropDelegate {
    let targetTaskID: UUID
    @Binding var draggedTaskID: UUID?
    let vm: HomeViewModel
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID else { return }
        vm.reorderDailyTask(
            draggedID: draggedTaskID,
            over: targetTaskID,
            context: context
        )
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct BumpAutofocusTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    let focusToken: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textField.textColor = .label
        textField.returnKeyType = .done
        textField.autocapitalizationType = .sentences
        textField.autocorrectionType = .yes
        textField.clearButtonMode = .whileEditing
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit

        uiView.placeholder = placeholder
        uiView.isEnabled = isEnabled

        if uiView.text != text {
            uiView.text = text
        }

        context.coordinator.applyFocusIfNeeded(
            token: focusToken,
            to: uiView,
            isEnabled: isEnabled
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        private var lastFocusToken: Int = .min

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return false
        }

        func applyFocusIfNeeded(token: Int, to textField: UITextField, isEnabled: Bool) {
            guard token != lastFocusToken else { return }
            lastFocusToken = token
            guard isEnabled else { return }

            focusAndSelectAll(textField)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak textField] in
                guard let textField else { return }
                self.focusAndSelectAll(textField)
            }
        }

        private func focusAndSelectAll(_ textField: UITextField) {
            DispatchQueue.main.async {
                guard textField.window != nil, textField.isEnabled else { return }
                textField.becomeFirstResponder()
                textField.selectAll(nil)
            }
        }
    }
}
