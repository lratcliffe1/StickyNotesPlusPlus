import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum TaskWidgetReloader {
    static let topTasksWidgetKind = "TopTasksWidget"

    static func reloadTopTasksWidget() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: topTasksWidgetKind)
#endif
    }
}
