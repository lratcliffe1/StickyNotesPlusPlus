import SwiftUI
import WidgetKit

/// Widget bundle entry point for StickyNote++ extensions.
@main
struct StickyNotePlusPlusWidgetBundle: WidgetBundle {
    var body: some Widget {
        TopTasksWidget()
    }
}
