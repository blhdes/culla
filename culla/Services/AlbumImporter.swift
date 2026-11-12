import Foundation
import SwiftData

/// One iPhone album the user picked, reduced to what the importer needs.
/// A plain value, so it can be handed to the background importer safely.
nonisolated struct AlbumImportRequest: Sendable {
    let name: String
    let albumIdentifier: String
    /// The count shown in the picker. Only used to size the progress bar
    /// before the real list of photos has been read.
    let estimatedPhotoCount: Int
}

/// How far an import has got. Sent to the screen while the import runs.
nonisolated struct AlbumImportProgress: Sendable, Equatable {
    var albumName: String = ""
    /// Position of the album being imported, starting at 0.
    var albumIndex: Int = 0
    var albumCount: Int
    var photosDone: Int = 0
    var photosTotal: Int
    /// Photos added so far for the album being imported, out of its own total.
    var albumPhotosDone: Int = 0
    var albumPhotosTotal: Int = 0
    /// How many albums are fully saved. Album `i` is done when `i < albumsFinished`.
    var albumsFinished: Int = 0

    /// 0…1 for the whole import, for progress bars and rings.
    var fraction: Double {
        guard photosTotal > 0 else { return 0 }
        return min(1, Double(photosDone) / Double(photosTotal))
    }

    /// 0…1 for the album being imported.
    var albumFraction: Double {
        guard albumPhotosTotal > 0 else { return 0 }
        return min(1, Double(albumPhotosDone) / Double(albumPhotosTotal))
    }
}

/// Thrown when an album can't be saved. Albums saved before it stay
/// imported, so their gallery IDs travel with the error.
nonisolated struct AlbumImportFailure: Error {
    let albumName: String
    let importedGalleryIDs: [UUID]
    let underlying: any Error
}

/// Creates galleries from iPhone albums on its own database context, away
/// from the main thread, so a big first import never freezes the screen.
///
/// Create it inside `Task.detached`: a model actor made on the main thread
/// does its work on the main thread too, which would bring the freeze back.
@ModelActor
actor AlbumImporter {
    /// How many photo records to add between two progress updates. Small
    /// enough for a smooth bar, big enough not to flood the main thread.
    private static let progressStep = 250

    /// Imports each album as a gallery and returns the new gallery IDs.
    ///
    /// Each album is saved as soon as it's done, so if the app closes
    /// mid-import, the albums already saved stay whole.
    func importAlbums(
        _ albums: [AlbumImportRequest],
        startingDisplayOrder: Int,
        onProgress: @escaping @MainActor @Sendable (AlbumImportProgress) -> Void
    ) async throws -> [UUID] {
        let service = await PhotoLibraryService.shared
        var progress = AlbumImportProgress(
            albumCount: albums.count,
            photosTotal: albums.reduce(0) { $0 + $1.estimatedPhotoCount }
        )
        var newGalleryIDs: [UUID] = []

        for (index, album) in albums.enumerated() {
            progress.albumName = album.name
            progress.albumIndex = index
            progress.albumPhotosDone = 0
            progress.albumPhotosTotal = album.estimatedPhotoCount
            await onProgress(progress)

            let identifiers = service.fetchAssetIdentifiers(
                from: .distantPast,
                excluding: [],
                inAlbum: album.albumIdentifier
            )
            // The picker's count is only an estimate: swap it for the real one.
            progress.photosTotal += identifiers.count - album.estimatedPhotoCount
            progress.albumPhotosTotal = identifiers.count

            let gallery = Gallery(
                name: album.name,
                displayOrder: startingDisplayOrder + index,
                albumIdentifier: album.albumIdentifier
            )
            modelContext.insert(gallery)

            let photosDoneBefore = progress.photosDone
            for (offset, identifier) in identifiers.enumerated() {
                modelContext.insert(SortedPhoto(assetIdentifier: identifier, gallery: gallery, isImported: true))

                let inserted = offset + 1
                if inserted.isMultiple(of: Self.progressStep) {
                    progress.photosDone = photosDoneBefore + inserted
                    progress.albumPhotosDone = inserted
                    await onProgress(progress)
                }
            }

            do {
                try modelContext.save()
            } catch {
                // Drop this album's half-made records so nothing partial is
                // saved later by accident.
                modelContext.rollback()
                throw AlbumImportFailure(
                    albumName: album.name,
                    importedGalleryIDs: newGalleryIDs,
                    underlying: error
                )
            }

            newGalleryIDs.append(gallery.id)
            progress.photosDone = photosDoneBefore + identifiers.count
            progress.albumPhotosDone = identifiers.count
            progress.albumsFinished = index + 1
            await onProgress(progress)
        }

        return newGalleryIDs
    }
}
