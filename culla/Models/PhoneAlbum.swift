import Photos
import SwiftUI

/// Represents an album from the user's phone photo library.
/// Not persisted — fetched fresh from PhotoKit each time.
nonisolated struct PhoneAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let photoCount: Int
    let startDate: Date?
    let endDate: Date?

    /// The underlying PhotoKit collection identifier, used to fetch photos from this album.
    let collectionIdentifier: String

    /// Whether iOS lets apps add photos to this album. False for smart albums
    /// (Screenshots, Selfies…), shared albums and albums synced from a computer,
    /// so they can't back a gallery that Culla writes into.
    let canAddPhotos: Bool

    /// Sentinel identifier for the "Unsorted Photos" virtual album.
    nonisolated static let unsortedIdentifier = "__culla_unsorted__"

    /// Sentinel identifier for the "Favorites" virtual album.
    nonisolated static let favoritesIdentifier = "__culla_favorites__"

    /// Whether this represents the virtual "Unsorted Photos" filter.
    var isUnsorted: Bool { collectionIdentifier == Self.unsortedIdentifier }

    /// Whether this represents the virtual "Favorites" filter.
    var isFavorites: Bool { collectionIdentifier == Self.favoritesIdentifier }

    /// Sentinel identifier for the clutter deck (Part Q5 of the iOS 27 kits
    /// plan): screenshots, documents, blurry shots and a dirty lens.
    nonisolated static let clutterIdentifier = "__culla_clutter__"

    /// Whether this represents the clutter deck.
    var isClutter: Bool { collectionIdentifier == Self.clutterIdentifier }

    /// Whether an identifier is one of Culla's own sources rather than a real
    /// iPhone album, so there's no album to read from or move photos out of.
    nonisolated static func isVirtual(_ identifier: String) -> Bool {
        identifier == unsortedIdentifier || identifier == favoritesIdentifier || identifier == clutterIdentifier
    }

    /// Creates the virtual album behind the clutter deck. Its size isn't known
    /// until the search runs while swiping, so it has no photo count.
    static func clutter() -> PhoneAlbum {
        PhoneAlbum(
            id: clutterIdentifier,
            // Localized: this name is shown on the home screen's album button.
            name: String(localized: "Clutter"),
            photoCount: 0,
            startDate: nil,
            endDate: nil,
            collectionIdentifier: clutterIdentifier
        )
    }

    /// Creates a virtual album representing the user's favorited photos.
    static func favorites(photoCount: Int) -> PhoneAlbum {
        PhoneAlbum(
            id: favoritesIdentifier,
            // Localized: this name is shown on the home screen's album button.
            name: String(localized: "Favorites"),
            photoCount: photoCount,
            startDate: nil,
            endDate: nil,
            collectionIdentifier: favoritesIdentifier
        )
    }

    /// Creates a virtual album representing all unsorted photos, starting from the very first photo.
    static func unsorted(photoCount: Int) -> PhoneAlbum {
        PhoneAlbum(
            id: unsortedIdentifier,
            name: String(localized: "From the very first photo"),
            photoCount: photoCount,
            startDate: nil,
            endDate: nil,
            collectionIdentifier: unsortedIdentifier
        )
    }

    init(collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.collectionIdentifier = collection.localIdentifier
        self.name = collection.localizedTitle ?? String(localized: "Untitled")
        self.startDate = collection.startDate
        self.endDate = collection.endDate
        self.canAddPhotos = collection.canPerform(.addContent)

        // estimatedAssetCount can return NSNotFound for smart albums,
        // so we do a real count in that case.
        let estimated = collection.estimatedAssetCount
        if estimated != NSNotFound {
            self.photoCount = estimated
        } else {
            let options = PHFetchOptions()
            options.predicate = PhotoLibraryService.mediaPredicate()
            self.photoCount = PHAsset.fetchAssets(in: collection, options: options).count
        }
    }

    init(
        id: String,
        name: String,
        photoCount: Int,
        startDate: Date?,
        endDate: Date?,
        collectionIdentifier: String,
        canAddPhotos: Bool = false
    ) {
        self.id = id
        self.name = name
        self.photoCount = photoCount
        self.startDate = startDate
        self.endDate = endDate
        self.collectionIdentifier = collectionIdentifier
        self.canAddPhotos = canAddPhotos
    }
}

enum AlbumSortOption: String, CaseIterable {
    case name = "Name"
    case photoCount = "Photo Count"
    case dateCreated = "Date Created"

    /// User-visible name. Kept separate from `rawValue` so translations
    /// never change the underlying case identity.
    var displayName: LocalizedStringKey {
        switch self {
        case .name: "Name"
        case .photoCount: "Photo Count"
        case .dateCreated: "Date Created"
        }
    }
}
