import Foundation
import SwiftData

/// DayRecord — optional cache of per-day completion summaries
/// Spec fields:
/// - date: Date (normalized)
/// - morningCompletion: Double
/// - dailyCompletion: Double
@Model
final class DayRecord {
    @Attribute(.unique)
    var date: Date
    var morningCompletion: Double
    var dailyCompletion: Double

    init(
        date: Date,
        morningCompletion: Double = 0,
        dailyCompletion: Double = 0
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.morningCompletion = morningCompletion
        self.dailyCompletion = dailyCompletion
    }
}

