import AppIntents
import WidgetKit

/// Widget intent that marks a selected top task as complete.
struct CompleteTopTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks the selected task as complete.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task ID")
    var taskID: String

    @Parameter(title: "List")
    var listRawValue: String

    init() {
        taskID = ""
        listRawValue = ""
    }

    init(taskID: UUID, list: WidgetContextualList) {
        self.taskID = taskID.uuidString
        listRawValue = list.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        guard let list = WidgetContextualList(rawValue: listRawValue) else { return .result() }

        if try await WidgetTaskStore.completeTask(id: id, list: list) {
            await WidgetCenter.shared.reloadTimelines(ofKind: WidgetTaskStore.widgetKind)
        }

        return .result()
    }
}
