import Foundation
import OSLog

enum AppLogger {
    static let persistence = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StickyNotesStickyLife", category: "persistence")
    static let widget = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StickyNotesStickyLife", category: "widget")
}
