import AppIntents
import SwiftUI
import WidgetKit

struct TopTasksWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Top Tasks"
    static var description = IntentDescription("Shows the top 3 uncompleted morning or daily items.")
}

struct TopTasksEntry: TimelineEntry {
    let date: Date
    let list: WidgetContextualList
    let items: [WidgetTaskItem]
}

struct TopTasksProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TopTasksEntry {
        TopTasksEntry(
            date: Date(),
            list: .morning,
            items: [
                WidgetTaskItem(id: UUID(), title: "Drink water", list: .morning),
                WidgetTaskItem(id: UUID(), title: "Stretch", list: .morning),
                WidgetTaskItem(id: UUID(), title: "Journal", list: .morning),
            ]
        )
    }

    func snapshot(for configuration: TopTasksWidgetConfigurationIntent, in context: Context) async -> TopTasksEntry {
        let snapshot = WidgetTaskStore.snapshot()
        return TopTasksEntry(
            date: snapshot.date,
            list: snapshot.list,
            items: snapshot.items
        )
    }

    func timeline(for configuration: TopTasksWidgetConfigurationIntent, in context: Context) async -> Timeline<TopTasksEntry> {
        let snapshot = WidgetTaskStore.snapshot()
        let entry = TopTasksEntry(
            date: snapshot.date,
            list: snapshot.list,
            items: snapshot.items
        )
        return Timeline(entries: [entry], policy: .after(snapshot.nextRefreshDate))
    }
}

struct TopTasksWidgetEntryView: View {
    let entry: TopTasksEntry

    private let addDailyTaskDeepLink = URL(string: "stickynotes://add-daily-task")

    private var stickyNoteBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.97, blue: 0.78),
                Color(red: 0.99, green: 0.93, blue: 0.67),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.items.isEmpty {
                Spacer(minLength: 0)

                Text("All caught up.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("No uncompleted items right now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            } else {
                ForEach(entry.items) { item in
                    Button(intent: CompleteTopTaskIntent(taskID: item.id, list: item.list)) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Color.black.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            stickyNoteBackground
        }
        .overlay(alignment: .topTrailing) {
            if let addDailyTaskDeepLink {
                Link(destination: addDailyTaskDeepLink) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 20, height: 20)
                        .background(
                            Color.black.opacity(0.08),
                            in: Circle()
                        )
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
                .accessibilityLabel("Add daily task")
            }
        }
    }
}

struct TopTasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetTaskStore.widgetKind,
            intent: TopTasksWidgetConfigurationIntent.self,
            provider: TopTasksProvider()
        ) { entry in
            TopTasksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sticky Top 3")
        .description("Shows your top 3 uncompleted morning or daily items.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
