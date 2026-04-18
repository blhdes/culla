import Foundation
import SwiftData

@Model
final class DailyStats {
    /// Midnight of the day this record covers.
    var date: Date
    var skipped: Int = 0
    var deleted: Int = 0
    var favourited: Int = 0

    init(date: Date, skipped: Int = 0, deleted: Int = 0, favourited: Int = 0) {
        self.date = date
        self.skipped = skipped
        self.deleted = deleted
        self.favourited = favourited
    }

    /// Find-or-create today's record and apply deltas. Safe to call from any view.
    static func upsert(
        in context: ModelContext,
        skippedDelta: Int = 0,
        deletedDelta: Int = 0,
        favouritedDelta: Int = 0
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let descriptor = FetchDescriptor<DailyStats>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.skipped    = max(0, existing.skipped    + skippedDelta)
            existing.deleted    = max(0, existing.deleted    + deletedDelta)
            existing.favourited = max(0, existing.favourited + favouritedDelta)
        } else {
            context.insert(DailyStats(
                date:       today,
                skipped:    max(0, skippedDelta),
                deleted:    max(0, deletedDelta),
                favourited: max(0, favouritedDelta)
            ))
        }
    }
}
