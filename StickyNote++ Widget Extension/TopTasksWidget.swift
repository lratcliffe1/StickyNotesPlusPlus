import AppIntents
import SwiftUI
import WidgetKit

/// Widget timeline/view composition for displaying top uncompleted tasks.
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
                WidgetTaskItem(id: UUID(), title: "Drink water", list: .morning, canBump: false),
                WidgetTaskItem(id: UUID(), title: "Stretch", list: .morning, canBump: false),
                WidgetTaskItem(id: UUID(), title: "Journal", list: .morning, canBump: false),
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
                    HStack(spacing: 6) {
                        Button(intent: CompleteTopTaskIntent(taskID: item.id, list: item.list)) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    StickyNotePalette.cardSurface,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(StickyNotePalette.cardBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)

                        if item.canBump {
                            Button(intent: BumpTopTaskIntent(taskID: item.id, list: item.list)) {
                                Image(systemName: "arrowshape.right.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        StickyNotePalette.chipSurface,
                                        in: Circle()
                                    )
                                    .overlay {
                                        Circle()
                                            .stroke(StickyNotePalette.cardBorder, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bump task to tomorrow")
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            StickyNotePalette.stickyNoteBackground
        }
        .overlay(alignment: .bottomTrailing) {
            if let addDailyTaskDeepLink {
                Link(destination: addDailyTaskDeepLink) {
                    Image(systemName: "plus")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 26, height: 26)
                        .background(
                            StickyNotePalette.chipSurface,
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(StickyNotePalette.cardBorder, lineWidth: 1.2)
                        }
                }
                .padding(.bottom, 12)
                .padding(.trailing, 12)
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
