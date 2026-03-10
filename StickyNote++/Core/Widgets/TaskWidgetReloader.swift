import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// Small helper to trigger timeline refreshes for task widgets.
enum TaskWidgetReloader {
    static let topTasksWidgetKind = "TopTasksWidget"

    static func reloadTopTasksWidget() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: topTasksWidgetKind)
#endif
    }
}
