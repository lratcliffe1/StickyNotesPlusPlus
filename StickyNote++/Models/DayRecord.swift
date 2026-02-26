import Foundation
import SwiftData

/// DayRecord — optional cache of per-day completion summaries
/// Spec fields:
/// - date: Date (normalized)
/// - dayKey: String (stable YYYY-MM-DD day identity)
/// - morningCompletion: Double
/// - dailyCompletion: Double
@Model
final class DayRecord {
    @Attribute(.unique)
    var date: Date
    var dayKey: String = ""
    var morningCompletion: Double
    var dailyCompletion: Double

    init(
        date: Date,
        dayKey: String? = nil,
        morningCompletion: Double = 0,
        dailyCompletion: Double = 0
    ) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        self.date = normalizedDate
        self.dayKey = dayKey ?? HomeModel.dayKey(for: normalizedDate)
        self.morningCompletion = morningCompletion
        self.dailyCompletion = dailyCompletion
    }
}
