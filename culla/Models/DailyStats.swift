import Foundation
import SwiftData

@Model
final class DailyStats {
    /// Midnight of the day this record covers.
    var date: Date
    var skipped: Int = 0
    var deletedCount: Int = 0
    var favourited: Int = 0

    init(date: Date, skipped: Int = 0, deletedCount: Int = 0, favourited: Int = 0) {
        self.date = date
        self.skipped = skipped
        self.deletedCount = deletedCount
        self.favourited = favourited
    }

    /// Find-or-create today's record and apply deltas. Safe to call from any view.
    ///
    /// Uses its own ModelContext so that the caller's context state (e.g. a
    /// recent save from batch-delete) cannot prevent the change from persisting.
    static func upsert(
        in context: ModelContext,
        skippedDelta: Int = 0,
        deletedDelta: Int = 0,
        favouritedDelta: Int = 0
    ) {
        let today = Date.now
        let calendar = Calendar.current

        // Work on a private context that reads/writes the store directly,
        // independent of any pending state on the caller's context.
        let ctx = ModelContext(context.container)

        let all = (try? ctx.fetch(FetchDescriptor<DailyStats>())) ?? []
        let existing = all.filter { calendar.isDate($0.date, inSameDayAs: today) }

        let oldSkipped    = existing.reduce(0) { $0 + $1.skipped }
        let oldDeleted    = existing.reduce(0) { $0 + $1.deletedCount }
        let oldFavourited = existing.reduce(0) { $0 + $1.favourited }

        for record in existing {
            ctx.delete(record)
        }

        ctx.insert(DailyStats(
            date:       calendar.startOfDay(for: today),
            skipped:    max(0, oldSkipped    + skippedDelta),
            deletedCount: max(0, oldDeleted    + deletedDelta),
            favourited: max(0, oldFavourited + favouritedDelta)
        ))

        try? ctx.save()
    }
}
