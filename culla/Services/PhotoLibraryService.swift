import Photos
import UIKit

/// Shared pixel size for all calendar cell thumbnails.
/// The mosaic is 44pt tall; the largest cell (1-photo, widest iPhone) is ~57pt wide.
/// At @3x that's ~171×132px. 160×160px covers that with a small buffer while keeping
/// the 4-photo 2×2 case (78×66px) from fetching excess pixels.
/// Must match between loadThumbnail and startCachingCalendarThumbnails.
let CalendarThumbnailSize = CGSize(width: 160, height: 160)

// Session-scoped cache — avoids re-enumerating PHFetchResult every time CalendarView opens.
// nonisolated(unsafe) because calendarData() is nonisolated and this is only written
// from one Task.detached at a time (safe in practice).
private nonisolated(unsafe) var _calendarDataCache: [String?: (counts: [Date: Int], thumbnailIDs: [Date: [String]])] = [:]

@Observable
final class PhotoLibraryService {

    /// Shared instance — avoids creating multiple PHCachingImageManagers.
    static let shared = PhotoLibraryService()

    var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    /// In-memory cache for calendar thumbnails — avoids re-fetching when scrolling back.
    /// NSCache auto-evicts under memory pressure, so this is safe.
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 50_000_000  // ~50 MB
        return cache
    }()

    /// Persistent disk cache for decoded thumbnails — survives app restarts.
    /// Located in ~/Library/Caches/CalendarThumbnails/. iOS auto-evicts under pressure.
    private static let diskCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CalendarThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Returns the disk cache file path for an asset identifier.
    /// PHAsset identifiers contain "/" — replace with "-" to make filename-safe.
    private func diskCachePath(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "-")
        return Self.diskCacheDir.appendingPathComponent("\(safe).png")
    }

    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async -> PHAuthorizationStatus {
        // Skip photo permission check when running UI tests for screenshots
        if CommandLine.arguments.contains("-UITestScreenshots") {
            authorizationStatus = .authorized
            return .authorized
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    // MARK: - Date Range

    /// Returns the creation dates of the earliest and latest photos in the library.
    /// Ignores photos with creation dates before 2000-01-01 to filter out corrupted
    /// EXIF dates (e.g. images saved from the web that inherit old embedded metadata).
    /// Returns the creation date of the most recent photo in a given album.
    /// Pass `nil` for all photos, or a `PhoneAlbum` collection identifier for a specific album.
    func latestPhotoDate(inAlbum albumIdentifier: String? = nil) -> Date? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        if albumIdentifier == PhoneAlbum.favoritesIdentifier {
            options.predicate = NSPredicate(
                format: "mediaType == %d AND isFavorite == YES",
                PHAssetMediaType.image.rawValue
            )
            return PHAsset.fetchAssets(with: options).firstObject?.creationDate
        } else if let albumIdentifier,
                  albumIdentifier != PhoneAlbum.unsortedIdentifier,
                  let collection = PHAssetCollection.fetchAssetCollections(
                      withLocalIdentifiers: [albumIdentifier], options: nil
                  ).firstObject {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return PHAsset.fetchAssets(in: collection, options: options).firstObject?.creationDate
        } else {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return PHAsset.fetchAssets(with: options).firstObject?.creationDate
        }
    }

    func earliestPhotoDate(inAlbum albumIdentifier: String? = nil) -> Date? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1

        if albumIdentifier == PhoneAlbum.favoritesIdentifier {
            options.predicate = NSPredicate(
                format: "mediaType == %d AND isFavorite == YES",
                PHAssetMediaType.image.rawValue
            )
            return PHAsset.fetchAssets(with: options).firstObject?.creationDate
        } else if let albumIdentifier,
                  albumIdentifier != PhoneAlbum.unsortedIdentifier,
                  let collection = PHAssetCollection.fetchAssetCollections(
                      withLocalIdentifiers: [albumIdentifier], options: nil
                  ).firstObject {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return PHAsset.fetchAssets(in: collection, options: options).firstObject?.creationDate
        } else {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return PHAsset.fetchAssets(with: options).firstObject?.creationDate
        }
    }

    func photoDateRange() -> (earliest: Date, latest: Date)? {
        let imageType = PHAssetMediaType.image.rawValue
        let floorDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!

        let earliestOptions = PHFetchOptions()
        earliestOptions.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@",
            imageType,
            floorDate as NSDate
        )
        earliestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        earliestOptions.fetchLimit = 1

        let latestOptions = PHFetchOptions()
        latestOptions.predicate = NSPredicate(format: "mediaType == %d", imageType)
        latestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        latestOptions.fetchLimit = 1

        let earliest = PHAsset.fetchAssets(with: earliestOptions).firstObject?.creationDate
        let latest = PHAsset.fetchAssets(with: latestOptions).firstObject?.creationDate

        guard let earliest, let latest else { return nil }
        return (earliest, latest)
    }

    // MARK: - Favorite Toggle

    /// Toggles the favorite state of a photo. Returns the new state (true = now favorited).
    func toggleFavorite(identifier: String) async -> Bool {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else { return false }

        let newValue = !asset.isFavorite
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = newValue
            }
            return newValue
        } catch {
            print("culla: Failed to toggle favorite: \(error)")
            return asset.isFavorite
        }
    }

    // MARK: - Album Write Operations

    /// Creates a new album in the iPhone Photos library. Returns its localIdentifier.
    /// If an album with the same name already exists, returns that one instead.
    func createAlbum(name: String) async -> String? {
        // Check if album already exists
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title == %@", name)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: fetchOptions
        )
        if let existingAlbum = existing.firstObject {
            return existingAlbum.localIdentifier
        }

        // Create new album
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            }
            // Fetch the newly created album
            let result = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .any, options: fetchOptions
            )
            return result.firstObject?.localIdentifier
        } catch {
            print("culla: Failed to create album '\(name)': \(error)")
            return nil
        }
    }

    /// Adds a photo to an iPhone Photos album.
    func addPhoto(assetIdentifier: String, toAlbum albumIdentifier: String) async {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier], options: nil
        ).firstObject,
              let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                request.addAssets([asset] as NSFastEnumeration)
            }
        } catch {
            print("culla: Failed to add photo to album: \(error)")
        }
    }

    /// Permanently deletes photos from the iPhone library. iOS shows one confirmation dialog.
    /// Returns the number of photos actually deleted.
    func deletePhotos(identifiers: [String]) async -> Int {
        guard !identifiers.isEmpty else { return 0 }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return 0 }

        let count = assets.count
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }
            return count
        } catch {
            print("culla: Failed to delete photos: \(error)")
            return 0
        }
    }

    /// Removes a photo from an iPhone Photos album (does NOT delete the photo itself).
    func removePhoto(assetIdentifier: String, fromAlbum albumIdentifier: String) async {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier], options: nil
        ).firstObject,
              let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                request.removeAssets([asset] as NSFastEnumeration)
            }
        } catch {
            print("culla: Failed to remove photo from album: \(error)")
        }
    }

    /// Renames an iPhone Photos album.
    func renameAlbum(identifier: String, to newName: String) async {
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
                request.title = newName
            }
        } catch {
            print("culla: Failed to rename album: \(error)")
        }
    }

    /// Deletes an iPhone Photos album (does NOT delete the photos inside it).
    func deleteAlbum(identifier: String) async {
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest.deleteAssetCollections(
                    [album] as NSFastEnumeration
                )
            }
        } catch {
            print("culla: Failed to delete album: \(error)")
        }
    }

    // MARK: - Album Fetching

    /// Fetches all user-created and smart albums that contain at least one photo.
    func fetchAlbums() -> [PhoneAlbum] {
        var albums: [PhoneAlbum] = []

        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let album = PhoneAlbum(collection: collection)
            if album.photoCount > 0 {
                albums.append(album)
            }
        }

        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .any, options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            let album = PhoneAlbum(collection: collection)
            if album.photoCount > 0 {
                albums.append(album)
            }
        }

        return albums
    }

    // MARK: - Metadata

    /// Returns the creation date for a single photo asset.
    func fetchCreationDate(for identifier: String) -> Date? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return result.firstObject?.creationDate
    }

    // MARK: - Fetching

    /// Returns asset identifiers for photos taken on or after `startDate`,
    /// sorted by creation date ascending, excluding identifiers in `excludedIDs`.
    /// If `albumIdentifier` is provided, only fetches photos from that album.
    /// The special sentinel `PhoneAlbum.unsortedIdentifier` fetches only unsorted photos.
    func fetchAssetIdentifiers(
        from startDate: Date,
        excluding excludedIDs: Set<String>,
        inAlbum albumIdentifier: String? = nil
    ) -> [String] {
        // Handle virtual albums
        if albumIdentifier == PhoneAlbum.favoritesIdentifier {
            return fetchFavoritesAssetIdentifiers(from: startDate, excluding: excludedIDs)
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND mediaType == %d",
            startDate as NSDate,
            PHAssetMediaType.image.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result: PHFetchResult<PHAsset>

        if let albumIdentifier,
           let collection = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [albumIdentifier], options: nil
           ).firstObject {
            result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        } else {
            result = PHAsset.fetchAssets(with: fetchOptions)
        }

        var identifiers: [String] = []
        identifiers.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            if !excludedIDs.contains(asset.localIdentifier) {
                identifiers.append(asset.localIdentifier)
            }
        }

        return identifiers
    }

    /// Returns asset identifiers for photos taken on today's month+day in past years.
    /// Sorted oldest first. Excludes current year and identifiers in `excludedIDs`.
    func fetchOnThisDayIdentifiers(
        excluding excludedIDs: Set<String>,
        inAlbum albumIdentifier: String? = nil
    ) -> [String] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: .now)
        let currentYear = calendar.component(.year, from: .now)

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result: PHFetchResult<PHAsset>

        if let albumIdentifier,
           albumIdentifier != PhoneAlbum.unsortedIdentifier,
           let collection = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [albumIdentifier], options: nil
           ).firstObject {
            result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        } else {
            result = PHAsset.fetchAssets(with: fetchOptions)
        }

        var identifiers: [String] = []

        result.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let components = calendar.dateComponents([.month, .day, .year], from: date)
            guard components.month == today.month,
                  components.day == today.day,
                  components.year != currentYear else { return }
            if !excludedIDs.contains(asset.localIdentifier) {
                identifiers.append(asset.localIdentifier)
            }
        }

        return identifiers
    }

    /// Returns the count of favorited photos.
    func favoritesPhotoCount() -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND isFavorite == YES",
            PHAssetMediaType.image.rawValue
        )
        return PHAsset.fetchAssets(with: options).count
    }

    /// Returns the count of all photos not yet sorted into a gallery (excludes already-sorted identifiers).
    func unsortedPhotoCount(excluding excludedIDs: Set<String> = []) -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        let allAssets = PHAsset.fetchAssets(with: options)

        var count = 0
        allAssets.enumerateObjects { asset, _, _ in
            if !excludedIDs.contains(asset.localIdentifier) {
                count += 1
            }
        }
        return count
    }

    // MARK: - Favorites Fetching

    /// Returns identifiers for favorited photos, filtered by start date and exclusion set.
    private func fetchFavoritesAssetIdentifiers(
        from startDate: Date,
        excluding excludedIDs: Set<String>
    ) -> [String] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND mediaType == %d AND isFavorite == YES",
            startDate as NSDate,
            PHAssetMediaType.image.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let allAssets = PHAsset.fetchAssets(with: fetchOptions)

        var identifiers: [String] = []
        allAssets.enumerateObjects { asset, _, _ in
            if !excludedIDs.contains(asset.localIdentifier) {
                identifiers.append(asset.localIdentifier)
            }
        }
        return identifiers
    }

    // MARK: - Image Loading

    /// Returns a thumbnail UIImage for the most recent photo in an album.
    func fetchAlbumThumbnail(albumIdentifier: String, targetSize: CGSize) async -> UIImage? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else { return nil }

        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        guard let asset = assets.firstObject else { return nil }

        return await loadImage(for: asset.localIdentifier, targetSize: targetSize)
    }

    /// Loads a display-quality UIImage for the given asset identifier.
    func loadImage(
        for assetIdentifier: String,
        targetSize: CGSize
    ) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else {
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            // Holds a degraded preview received while waiting for the iCloud download.
            // Used as fallback if the final high-quality delivery fails.
            var degradedFallback: UIImage? = nil

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil

                if isDegraded {
                    // Save as fallback; keep waiting for the high-quality version.
                    degradedFallback = image
                } else if isCancelled || hasError {
                    // Final delivery failed — use the degraded preview if we got one.
                    continuation.resume(returning: degradedFallback)
                } else {
                    // High-quality delivery (image may still be nil in rare edge cases).
                    continuation.resume(returning: image ?? degradedFallback)
                }
            }
        }
    }

    // MARK: - Calendar Thumbnail Loading

    /// Fast, local-only thumbnail load for calendar grid cells.
    /// Uses fastFormat delivery (single callback, no iCloud wait) and aspectFill
    /// so the image fills the cell without letterboxing.
    func loadThumbnail(for assetIdentifier: String) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let cacheKey = assetIdentifier as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        // Disk cache hit — much faster than PHImageManager
        let diskPath = diskCachePath(for: assetIdentifier)
        do {
            let data = try Data(contentsOf: diskPath)
            if let diskImage = UIImage(data: data) {
                let decoded = diskImage.preparingForDisplay() ?? diskImage
                thumbnailCache.setObject(decoded, forKey: cacheKey)
                return decoded
            }
        } catch {
            // Disk read or decode failed — remove corrupted file and fall back to PHImageManager
            try? FileManager.default.removeItem(at: diskPath)
        }

        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else { return nil }

        guard !Task.isCancelled else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast

        let image: UIImage? = await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: CalendarThumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }

        if let image {
            // Pre-decode pixels on this background thread so the main thread only composites.
            let decoded = image.preparingForDisplay() ?? image
            thumbnailCache.setObject(decoded, forKey: cacheKey)

            // Write to disk in background — don't await, return immediately
            let pathForWrite = diskPath  // capture before escaping
            Task.detached(priority: .background) {
                guard let data = decoded.pngData() else { return }

                // Write to temp file, then atomic rename to avoid incomplete reads
                let tempPath = pathForWrite.appendingPathExtension("tmp")
                do {
                    try data.write(to: tempPath, options: .atomic)
                    try FileManager.default.moveItem(at: tempPath, to: pathForWrite)
                } catch {
                    try? FileManager.default.removeItem(at: tempPath)
                }
            }

            return decoded
        }

        return nil
    }

    // MARK: - Calendar Data

    /// Returns photo counts and up to 4 thumbnail asset identifiers per calendar day.
    /// For days with more than 4 photos, 4 are picked randomly (stable per load).
    /// Respects album filtering: pass a collectionIdentifier to scope to an album,
    /// PhoneAlbum.favoritesIdentifier for favorites, or nil for all photos.
    nonisolated func calendarData(from earliest: Date, to latest: Date, inAlbum albumIdentifier: String? = nil) -> (counts: [Date: Int], thumbnailIDs: [Date: [String]]) {
        if let cached = _calendarDataCache[albumIdentifier] {
            return cached
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result: PHFetchResult<PHAsset>

        if albumIdentifier == PhoneAlbum.favoritesIdentifier {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d AND isFavorite == YES",
                earliest as NSDate, latest as NSDate, PHAssetMediaType.image.rawValue
            )
            result = PHAsset.fetchAssets(with: options)
        } else if let albumIdentifier,
                  albumIdentifier != PhoneAlbum.unsortedIdentifier,
                  let collection = PHAssetCollection.fetchAssetCollections(
                      withLocalIdentifiers: [albumIdentifier], options: nil
                  ).firstObject {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
                earliest as NSDate, latest as NSDate, PHAssetMediaType.image.rawValue
            )
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
                earliest as NSDate, latest as NSDate, PHAssetMediaType.image.rawValue
            )
            result = PHAsset.fetchAssets(with: options)
        }

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

        let calendarResult = (counts, thumbnailIDs)
        _calendarDataCache[albumIdentifier] = calendarResult
        return calendarResult
    }

    // MARK: - Preloading

    /// Tells PHCachingImageManager to start caching images for upcoming identifiers.
    func startCaching(identifiers: [String], targetSize: CGSize) {
        let assets = fetchAssets(for: identifiers)
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: nil
        )
    }

    /// Stops caching for identifiers that are no longer needed.
    func stopCaching(identifiers: [String], targetSize: CGSize) {
        let assets = fetchAssets(for: identifiers)
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: nil
        )
    }

    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// Pre-loads all calendar thumbnails into NSCache and disk for a given date range.
    /// Runs concurrent background tasks to populate memory cache from disk (or PHImageManager on first load).
    /// Safe to call with .background priority — does not block the caller.
    /// Call this at app launch to ensure hot cache before user opens the calendar view.
    func warmCalendarCache(from earliest: Date, to latest: Date, inAlbum albumIdentifier: String? = nil) async {
        let data = calendarData(from: earliest, to: latest, inAlbum: albumIdentifier)
        let allIDs = data.thumbnailIDs.values.flatMap { $0 }
        guard !allIDs.isEmpty else { return }

        startCachingCalendarThumbnails(allIDs)

        await withTaskGroup(of: Void.self) { group in
            for id in allIDs {
                group.addTask(priority: .background) { [self] in
                    _ = await self.loadThumbnail(for: id)
                }
            }
        }
    }

    /// Pre-warms the image cache for all calendar thumbnails at once.
    /// Call this right after calendarData() resolves so cells hit the cache on first render.
    func startCachingCalendarThumbnails(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast
        let assets = fetchAssets(for: identifiers)
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: CalendarThumbnailSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    // MARK: - Private

    /// Picks `count` evenly-distributed items from `ids` in O(1) — no full-array copy.
    /// Gives a representative spread across the day (first, middle, last-ish photos)
    /// rather than a random grab that varies on every load.
    private nonisolated static func spreadPick(_ ids: [String], count: Int) -> [String] {
        let n = ids.count
        return (0..<count).map { i in ids[(i * n) / count] }
    }

    private func fetchAssets(for identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}
