import Foundation
import SwiftData

@Model
final class DailyStats {
    /// Midnight of the day this record covers.
    var date: Date
    var skipped: Int
    var deleted: Int

    init(date: Date, skipped: Int = 0, deleted: Int = 0) {
        self.date = date
        self.skipped = skipped
        self.deleted = deleted
    }
}
