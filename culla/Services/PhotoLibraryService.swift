import Photos
import UIKit

/// Talks to the iPhone photo library. The work is split by job across files:
/// `+Queries` (reading), `+Writes` (changing), `+Media` (images and videos)
/// and `+Calendar` (calendar data and its cache).
@Observable
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {

    /// Shared instance — avoids creating multiple PHCachingImageManagers.
    static let shared = PhotoLibraryService()

    var authorizationStatus: PHAuthorizationStatus = .notDetermined

    /// Used by image loading and swipe preloading in `+Media`. Not `private`
    /// because that code lives in another file.
    let imageManager = PHCachingImageManager()

    override private init() {
        super.init()
        // Observe library changes so the calendar cache is dropped whenever the
        // user changes their limited selection (in-app picker or Settings) or
        // the underlying photo set changes for any other reason. Without this,
        // `CalendarDataCache` keeps stale identifiers and mosaic cells render
        // as empty gray placeholders because `CalendarThumbnailCache` returns nil for
        // assets the user no longer has access to.
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// Goes up by one on every photo library change, so views can react (e.g. the
    /// cleanup of records for deleted photos).
    private(set) var libraryChangeCount = 0

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        invalidateCalendarDataCache()
        Task { @MainActor in
            self.libraryChangeCount += 1
            #if DEBUG
            // Part C2: how often the calendar cache is rebuilt while swiping. The
            // cleanup's `[cleanup] … changes:` line says what kind of changes they were.
            print("[cleanup] library change #\(self.libraryChangeCount): calendar cache dropped")
            #endif
        }
    }

    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status
    }

    // MARK: - Include Videos Setting

    /// UserDefaults key backing the Settings "Include videos" toggle.
    /// Must match the @AppStorage key used in SettingsView/DatePickerView.
    nonisolated static let includeVideosKey = "includeVideos"

    /// Whether videos join the swipe pipeline. ON by default.
    /// Uses object(forKey:) because bool(forKey:) returns false for a
    /// missing key, which would silently default the feature OFF.
    nonisolated static var includeVideos: Bool {
        UserDefaults.standard.object(forKey: includeVideosKey) as? Bool ?? true
    }

    /// Builds the media-type predicate, optionally ANDed with extra conditions.
    /// Single source of truth for "what counts as a sortable asset".
    nonisolated static func mediaPredicate(and extra: NSPredicate? = nil) -> NSPredicate {
        let types = includeVideos
            ? [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue]
            : [PHAssetMediaType.image.rawValue]
        let media = NSPredicate(format: "mediaType IN %@", types)
        guard let extra else { return media }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [media, extra])
    }

    // MARK: - Album Scope

    /// Fetches sortable assets in one album scope: Favorites, a real album, or
    /// the whole library (`nil`, the "unsorted" sentinel, whose sorted photos
    /// the caller filters out, or the clutter deck, which picks its photos
    /// while swiping). `extra` narrows the search, e.g. a date range.
    /// Sets `options.predicate`; set sorting and limits before calling.
    nonisolated static func scopedAssets(
        inAlbum albumIdentifier: String?,
        matching extra: NSPredicate? = nil,
        options: PHFetchOptions
    ) -> PHFetchResult<PHAsset> {
        if albumIdentifier == PhoneAlbum.favoritesIdentifier {
            let favorite = NSPredicate(format: "isFavorite == YES")
            let condition = extra.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [$0, favorite])
            } ?? favorite
            options.predicate = mediaPredicate(and: condition)
            return PHAsset.fetchAssets(with: options)
        }

        options.predicate = mediaPredicate(and: extra)
        if let albumIdentifier,
           !PhoneAlbum.isVirtual(albumIdentifier),
           let collection = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [albumIdentifier], options: nil
           ).firstObject {
            return PHAsset.fetchAssets(in: collection, options: options)
        }
        return PHAsset.fetchAssets(with: options)
    }
}
