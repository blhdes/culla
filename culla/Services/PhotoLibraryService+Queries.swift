import Photos

extension PhotoLibraryService {

    // MARK: - Date Range

    /// Returns the creation date of the oldest photo in a given album.
    /// Pass `nil` for all photos, or a `PhoneAlbum` collection identifier for a specific album.
    func earliestPhotoDate(inAlbum albumIdentifier: String? = nil) -> Date? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1
        return Self.scopedAssets(inAlbum: albumIdentifier, options: options).firstObject?.creationDate
    }

    /// Returns the creation dates of the earliest and latest photos in the library.
    /// Ignores photos with creation dates before 2000-01-01 to filter out corrupted
    /// EXIF dates (e.g. images saved from the web that inherit old embedded metadata).
    func photoDateRange() -> (earliest: Date, latest: Date)? {
        let floorDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))!

        let earliestOptions = PHFetchOptions()
        earliestOptions.predicate = Self.mediaPredicate(
            and: NSPredicate(format: "creationDate >= %@", floorDate as NSDate)
        )
        earliestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        earliestOptions.fetchLimit = 1

        let latestOptions = PHFetchOptions()
        latestOptions.predicate = Self.mediaPredicate()
        latestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        latestOptions.fetchLimit = 1

        let earliest = PHAsset.fetchAssets(with: earliestOptions).firstObject?.creationDate
        let latest = PHAsset.fetchAssets(with: latestOptions).firstObject?.creationDate

        guard let earliest, let latest else { return nil }
        return (earliest, latest)
    }

    // MARK: - Existence Checks

    /// How many of these photos still exist in the library. Tells a cancelled
    /// delete (photos still there) apart from photos that were already gone.
    func existingPhotoCount(identifiers: [String]) -> Int {
        Self.existingIdentifiers(among: Set(identifiers)).count
    }

    /// Which of these photos still exist in the library. Hidden photos and every
    /// shot of a burst count as existing — the default lookup skips them.
    nonisolated static func existingIdentifiers(among identifiers: Set<String>) -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        let options = lookupOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        var existing = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: Array(identifiers), options: options)
            .enumerateObjects { asset, _, _ in existing.insert(asset.localIdentifier) }
        return existing
    }

    /// Looks photos up by identifier without skipping hidden photos or the
    /// extra shots of a burst, which the default lookup leaves out.
    nonisolated static func lookupOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        return options
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

    /// Everything the UI asks about a single asset, answered in one fetch.
    struct AssetInfo {
        let creationDate: Date?
        let isFavorite: Bool
        let isVideo: Bool
        let duration: TimeInterval   // 0 for images
    }

    /// Cheap single-asset metadata fetch (one PHAsset lookup).
    func assetInfo(for identifier: String) -> AssetInfo? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        return AssetInfo(
            creationDate: asset.creationDate,
            isFavorite: asset.isFavorite,
            isVideo: asset.mediaType == .video,
            duration: asset.duration
        )
    }

    // MARK: - Fetching

    /// Returns asset identifiers for photos taken on or after `startDate`,
    /// sorted by creation date ascending, excluding identifiers in `excludedIDs`.
    /// If `albumIdentifier` is provided, only fetches photos from that album.
    /// The special sentinel `PhoneAlbum.unsortedIdentifier` fetches only unsorted photos.
    nonisolated func fetchAssetIdentifiers(
        from startDate: Date,
        excluding excludedIDs: Set<String>,
        inAlbum albumIdentifier: String? = nil
    ) -> [String] {
        // Handle virtual albums
        if albumIdentifier == PhoneAlbum.favoritesIdentifier {
            return fetchFavoritesAssetIdentifiers(from: startDate, excluding: excludedIDs)
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = Self.mediaPredicate(
            and: NSPredicate(format: "creationDate >= %@", startDate as NSDate)
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
    nonisolated func fetchOnThisDayIdentifiers(
        excluding excludedIDs: Set<String>,
        inAlbum albumIdentifier: String? = nil
    ) -> [String] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: .now)
        let currentYear = calendar.component(.year, from: .now)

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = Self.mediaPredicate()
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
        options.predicate = Self.mediaPredicate(and: NSPredicate(format: "isFavorite == YES"))
        return PHAsset.fetchAssets(with: options).count
    }

    /// Returns the count of all photos not yet sorted into a gallery (excludes already-sorted identifiers).
    func unsortedPhotoCount(excluding excludedIDs: Set<String> = []) -> Int {
        let options = PHFetchOptions()
        options.predicate = Self.mediaPredicate()
        let total = PHAsset.fetchAssets(with: options).count
        guard !excludedIDs.isEmpty else { return total }

        // Count only the excluded assets that still exist, then subtract —
        // far cheaper than walking every photo in the library one by one.
        let excludedStillInLibrary = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(excludedIDs), options: options
        ).count
        return max(total - excludedStillInLibrary, 0)
    }

    // MARK: - Favorites Fetching

    /// Returns identifiers for favorited photos, filtered by start date and exclusion set.
    private nonisolated func fetchFavoritesAssetIdentifiers(
        from startDate: Date,
        excluding excludedIDs: Set<String>
    ) -> [String] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = Self.mediaPredicate(and: NSPredicate(
            format: "creationDate >= %@ AND isFavorite == YES",
            startDate as NSDate
        ))
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
}
