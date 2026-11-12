import Photos

/// One album scope's calendar data: per-day photo counts and thumbnail identifiers.
typealias CalendarData = (counts: [Date: Int], thumbnailIDs: [Date: [String]])

/// Session-scoped cache — avoids re-enumerating PHFetchResult every time CalendarView opens.
///
/// Guarded by a lock because it is touched from three threads: background
/// tasks (`calendarData`), the main thread (invalidation after a write), and
/// PhotoKit's own queue (`photoLibraryDidChange`). A plain dictionary can crash
/// when two of those overlap.
private nonisolated final class CalendarDataCache: @unchecked Sendable {
    static let shared = CalendarDataCache()

    private let lock = NSLock()
    private var storage: [String: CalendarData] = [:]

    func value(for key: String) -> CalendarData? {
        lock.withLock { storage[key] }
    }

    func set(_ value: CalendarData, for key: String) {
        lock.withLock { storage[key] = value }
    }

    func removeAll() {
        lock.withLock { storage.removeAll() }
    }
}

extension PhotoLibraryService {

    // MARK: - Calendar Data

    /// Returns photo counts and up to 4 thumbnail asset identifiers per calendar day.
    /// For days with more than 4 photos, 4 are picked randomly (stable per load).
    /// Respects album filtering: pass a collectionIdentifier to scope to an album,
    /// PhoneAlbum.favoritesIdentifier for favorites, or nil for all photos.
    nonisolated func calendarData(from earliest: Date, to latest: Date, inAlbum albumIdentifier: String? = nil) -> CalendarData {
        // includeVideos is part of the key so toggling the setting can't serve stale data.
        let cacheKey = "\(Self.includeVideos)|\(albumIdentifier ?? "")|\(earliest.timeIntervalSince1970)|\(latest.timeIntervalSince1970)"
        if let cached = CalendarDataCache.shared.value(for: cacheKey) {
            return cached
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result = Self.scopedAssets(
            inAlbum: albumIdentifier,
            matching: NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                earliest as NSDate, latest as NSDate
            ),
            options: options
        )

        var counts: [Date: Int] = [:]
        var allIDs: [Date: [String]] = [:]
        let cal = Calendar.current

        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let day = cal.startOfDay(for: date)
            counts[day, default: 0] += 1
            allIDs[day, default: []].append(asset.localIdentifier)
        }

        var thumbnailIDs: [Date: [String]] = [:]
        for (day, ids) in allIDs {
            thumbnailIDs[day] = ids.count <= 4 ? ids : Self.spreadPick(ids, count: 4)
        }

        let calendarResult: CalendarData = (counts, thumbnailIDs)
        CalendarDataCache.shared.set(calendarResult, for: cacheKey)
        return calendarResult
    }

    /// Returns every asset in the album scope between `earliest` and `latest`,
    /// newest first. Carries creationDate and videoDuration so the photo grid
    /// picker never needs a second per-cell PHAsset fetch.
    nonisolated func gridAssets(from earliest: Date, to latest: Date, inAlbum albumIdentifier: String? = nil) -> [(id: String, creationDate: Date, videoDuration: TimeInterval?)] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = Self.scopedAssets(
            inAlbum: albumIdentifier,
            matching: NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                earliest as NSDate, latest as NSDate
            ),
            options: options
        )

        var items: [(id: String, creationDate: Date, videoDuration: TimeInterval?)] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let duration = asset.mediaType == .video ? asset.duration : nil
            items.append((asset.localIdentifier, date, duration))
        }
        return items
    }

    /// Pre-loads all calendar thumbnails for a given date range into
    /// `CalendarThumbnailCache` (memory and disk). Call this at app launch so
    /// the calendar opens with its cells already filled.
    func warmCalendarCache(from earliest: Date, to latest: Date, inAlbum albumIdentifier: String? = nil) async {
        // This class runs on the main thread by default, and `calendarData`
        // walks the whole library — so hand that scan to a background task
        // instead of freezing the UI right after launch.
        let data = await Task.detached(priority: .background) {
            self.calendarData(from: earliest, to: latest, inAlbum: albumIdentifier)
        }.value
        let allIDs = data.thumbnailIDs.values.flatMap { $0 }
        guard !allIDs.isEmpty else { return }

        await CalendarThumbnailCache.shared.preload(allIDs)
    }

    /// Drops the cached calendar data. `nonisolated` because PhotoKit calls it
    /// from its own queue too (`photoLibraryDidChange`); the cache has its own lock.
    nonisolated func invalidateCalendarDataCache() {
        CalendarDataCache.shared.removeAll()
    }

    /// Picks `count` evenly-distributed items from `ids` in O(1) — no full-array copy.
    /// Gives a representative spread across the day (first, middle, last-ish photos)
    /// rather than a random grab that varies on every load.
    private nonisolated static func spreadPick(_ ids: [String], count: Int) -> [String] {
        let n = ids.count
        return (0..<count).map { i in ids[(i * n) / count] }
    }
}
