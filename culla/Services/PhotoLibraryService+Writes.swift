import Photos

extension PhotoLibraryService {

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
            invalidateCalendarDataCache()
            return newValue
        } catch {
            print("culla: Failed to toggle favorite: \(Self.describe(error))")
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
            print("culla: Failed to create album '\(name)': \(Self.describe(error))")
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
            invalidateCalendarDataCache()
        } catch {
            print("culla: Failed to add photo to album: \(Self.describe(error))")
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
            invalidateCalendarDataCache()
        } catch {
            print("culla: Failed to remove photo from album: \(Self.describe(error))")
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
            print("culla: Failed to rename album: \(Self.describe(error))")
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
            print("culla: Failed to delete album: \(Self.describe(error))")
        }
    }

    // MARK: - Photo Deletion

    /// Permanently deletes photos from the iPhone library. iOS shows one confirmation dialog.
    /// Returns the number of photos actually deleted.
    func deletePhotos(identifiers: [String]) async -> Int {
        guard !identifiers.isEmpty else { return 0 }

        // Same lookup as `existingIdentifiers`, so hidden photos get deleted too.
        // With the default lookup they were skipped, and a gallery made only of
        // hidden photos looked like a cancelled delete forever.
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers, options: Self.lookupOptions()
        )
        guard assets.count > 0 else { return 0 }

        let count = assets.count
        // Measure freed space BEFORE deletion — the assets are gone afterwards.
        var freedBytes: Int64 = 0
        var unknownSizes = 0
        assets.enumerateObjects { asset, _, _ in
            if let bytes = Self.assetByteSize(asset) {
                freedBytes += bytes
            } else {
                unknownSizes += 1
            }
        }
        if unknownSizes > 0 {
            print("[storage] \(unknownSizes) of \(count) deleted photos had no known size; the Storage card undercounts them")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }
            Self.recordReclaimed(bytes: freedBytes)
            invalidateCalendarDataCache()
            CalendarThumbnailCache.shared.evict(identifiers)
            return count
        } catch {
            print("culla: Failed to delete photos: \(Self.describe(error))")
            return 0
        }
    }

    // MARK: - Errors

    /// Error text for the console. Names Photos' "limit exceeded" error (new
    /// in iOS 26.1) so a hit stands out from ordinary failures.
    nonisolated static func describe(_ error: any Error) -> String {
        if #available(iOS 26.1, *), (error as? PHPhotosError)?.code == .limitExceeded {
            return "Photos limit exceeded (PHPhotosError.limitExceeded): \(error)"
        }
        return "\(error)"
    }

    // MARK: - Reclaimed storage tracking

    /// Accumulates freed bytes into the running total the Insights "Storage"
    /// card reads. Stored in UserDefaults so it survives relaunch, mirroring
    /// `totalDeletedPhotos`. The photo count itself comes from
    /// `totalDeletedPhotos`, so the two never desync.
    private static func recordReclaimed(bytes: Int64) {
        guard bytes > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.double(forKey: "totalReclaimedBytes") + Double(bytes), forKey: "totalReclaimedBytes")
    }
}
