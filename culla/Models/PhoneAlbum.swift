import Photos

/// Represents an album from the user's phone photo library.
/// Not persisted — fetched fresh from PhotoKit each time.
struct PhoneAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let photoCount: Int
    let startDate: Date?
    let endDate: Date?

    /// The underlying PhotoKit collection identifier, used to fetch photos from this album.
    let collectionIdentifier: String

    /// Sentinel identifier for the "Unsorted Photos" virtual album.
    static let unsortedIdentifier = "__culla_unsorted__"

    /// Sentinel identifier for the "Favorites" virtual album.
    static let favoritesIdentifier = "__culla_favorites__"

    /// Whether this represents the virtual "Unsorted Photos" filter.
    var isUnsorted: Bool { collectionIdentifier == Self.unsortedIdentifier }

    /// Whether this represents the virtual "Favorites" filter.
    var isFavorites: Bool { collectionIdentifier == Self.favoritesIdentifier }

    /// Creates a virtual album representing the user's favorited photos.
    static func favorites(photoCount: Int) -> PhoneAlbum {
        PhoneAlbum(
            id: favoritesIdentifier,
            name: "Favorites",
            photoCount: photoCount,
            startDate: nil,
            endDate: nil,
            collectionIdentifier: favoritesIdentifier
        )
    }

    /// Creates a virtual album representing photos not in any user-created album.
    static func unsorted(photoCount: Int) -> PhoneAlbum {
        PhoneAlbum(
            id: unsortedIdentifier,
            name: "Unculla'd",
            photoCount: photoCount,
            startDate: nil,
            endDate: nil,
            collectionIdentifier: unsortedIdentifier
        )
    }

    init(collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.collectionIdentifier = collection.localIdentifier
        self.name = collection.localizedTitle ?? "Untitled"
        self.startDate = collection.startDate
        self.endDate = collection.endDate

        // estimatedAssetCount can return NSNotFound for smart albums,
        // so we do a real count in that case.
        let estimated = collection.estimatedAssetCount
        if estimated != NSNotFound {
            self.photoCount = estimated
        } else {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d",
                PHAssetMediaType.image.rawValue
            )
            self.photoCount = PHAsset.fetchAssets(in: collection, options: options).count
        }
    }

    init(
        id: String,
        name: String,
        photoCount: Int,
        startDate: Date?,
        endDate: Date?,
        collectionIdentifier: String
    ) {
        self.id = id
        self.name = name
        self.photoCount = photoCount
        self.startDate = startDate
        self.endDate = endDate
        self.collectionIdentifier = collectionIdentifier
    }
}

enum AlbumSortOption: String, CaseIterable {
    case name = "Name"
    case photoCount = "Photo Count"
    case dateCreated = "Date Created"
}
