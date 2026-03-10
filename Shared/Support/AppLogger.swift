import Foundation
import OSLog

/// Centralized structured logging categories.
/// Avoid ad-hoc `print` so production/debug telemetry is searchable and consistent.
enum AppLogger {
    static let persistence = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StickyNotesStickyLife", category: "persistence")
    static let widget = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StickyNotesStickyLife", category: "widget")
}
