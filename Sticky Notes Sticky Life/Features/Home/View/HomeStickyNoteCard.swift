import SwiftData
import SwiftUI

struct HomeStickyNoteCard: View {
    @ObservedObject var vm: HomeViewModel
    let modelContext: ModelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(vm.isMorningMode ? "Morning Routine" : "Daily Tasks")
                    .font(.title3.weight(.bold))
                Spacer()
                HStack(spacing: 8) {
                    Text("\(Int((vm.isMorningMode ? vm.morningProgress : vm.dailyProgress) * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            vm.flipStickyNoteList()
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.78))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(vm.isMorningMode ? "Flip to daily tasks" : "Flip to morning routine")
                }
            }

            if vm.isMorningMode {
                morningList
            } else {
                dailyList
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.isMorningMode)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .padding(16)
        .background(stickyBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private var morningList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.morningEntries.isEmpty {
                Text("No morning items yet. Add routine templates in Settings.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(vm.morningEntries) { entry in
                    InkStrikeRow(
                        title: entry.titleSnapshot,
                        subtitle: timeLabel(from: entry.targetTimeSnapshot),
                        isCompleted: entry.isCompleted,
                        canEdit: vm.canCompleteSelectedDay,
                        strikeColor: .blue
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
                HStack(spacing: 8) {
                    TextField("Add a task...", text: $vm.newTaskTitle)
                        .textFieldStyle(.plain)

                    Button("Add") {
                        vm.addDailyTask(context: modelContext)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.8))
                    .clipShape(Capsule())
                    .disabled(vm.newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.7), lineWidth: 1)
                )
            }

            if vm.canUndoLastBump {
                Button {
                    vm.undoLastBump(context: modelContext)
                } label: {
                    Label("Undo last bump", systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.75))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last bump")
            }

            if prioritizedDailyTasks.isEmpty {
                Text("No tasks for this day.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(prioritizedDailyTasks) { task in
                    InkStrikeRow(
                        title: task.title,
                        subtitle: dailySubtitle(for: task),
                        isCompleted: task.isCompleted,
                        canEdit: vm.canCompleteSelectedDay,
                        strikeColor: urgencyColor(for: task.bumpCount)
                    ) {
                        vm.toggleDailyTask(task, context: modelContext)
                    } trailing: {
                        if task.isBumpable, !task.isCompleted, !vm.isReadOnly {
                            Button {
                                vm.bumpTaskToTomorrow(task, context: modelContext)
                            } label: {
                                Image(systemName: "arrowshape.right.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(urgencyColor(for: task.bumpCount))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bump to tomorrow")
                        } else if !task.isBumpable {
                            Text("Must do")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var prioritizedDailyTasks: [DailyTask] {
        vm.dailyTasks.sorted { lhs, rhs in
            if lhs.isBumpable != rhs.isBumpable {
                return lhs.isBumpable == false
            }

            let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func timeLabel(from components: DateComponents?) -> String? {
        guard let components, let hour = components.hour, let minute = components.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func dailySubtitle(for task: DailyTask) -> String? {
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

    private var stickyBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.97, blue: 0.78),
                Color(red: 0.99, green: 0.93, blue: 0.67)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
