import SwiftUI
import SwiftData

@Observable
final class GalleryViewModel {
    var galleries: [Gallery] = []

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchGalleries()
    }

    // MARK: - Fetch

    func fetchGalleries() {
        let descriptor = FetchDescriptor<Gallery>(sortBy: [SortDescriptor(\.displayOrder)])
        galleries = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Create

    func createGallery(name: String, iconName: String = "folder.fill", colorHex: String? = nil) {
        // Other screens add galleries too (album import, the Manage sheet),
        // so refresh first — a stale count would hand the new gallery an
        // order number (and default colour) that's already taken.
        fetchGalleries()
        let gallery = Gallery(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            displayOrder: galleries.count
        )
        modelContext.insert(gallery)
        save()
        fetchGalleries()

        // Create matching iPhone Photos album
        Task {
            let service = PhotoLibraryService.shared
            if let albumID = await service.createAlbum(name: name) {
                await MainActor.run {
                    gallery.albumIdentifier = albumID
                    self.save()
                }
            }
        }
    }

    // MARK: - Delete

    /// Unlinks the gallery from Culla only. iPhone album and photos stay untouched.
    /// The gallery can be re-imported later via "Import from Phone."
    func unlinkGallery(_ gallery: Gallery) {
        modelContext.delete(gallery)
        save()
        fetchGalleries()
        renumberDisplayOrder()
    }

    /// Removes the gallery from Culla AND deletes the iPhone album.
    /// Photos stay in the library but lose their album grouping.
    func deleteGallery(_ gallery: Gallery) {
        let albumID = gallery.albumIdentifier
        modelContext.delete(gallery)
        save()
        fetchGalleries()
        renumberDisplayOrder()

        if let albumID {
            Task {
                await PhotoLibraryService.shared.deleteAlbum(identifier: albumID)
            }
        }
    }

    /// Permanently deletes all the gallery's photos, then removes the gallery and its iPhone album.
    /// Returns `false` — and changes nothing — when the user cancels the iOS prompt.
    @discardableResult
    func deleteGalleryAndPhotos(_ gallery: Gallery) async -> Bool {
        let identifiers = gallery.sortedPhotos.map(\.assetIdentifier)
        let service = PhotoLibraryService.shared

        if !identifiers.isEmpty {
            let deleted = await service.deletePhotos(identifiers: identifiers)
            // Nothing deleted while the photos still exist = "Don't Allow" (or iOS failed).
            // Leave the gallery and its album exactly as they were.
            if deleted == 0 && service.existingPhotoCount(identifiers: identifiers) > 0 {
                return false
            }
            // Recorded here so both entry points — the gallery list and the
            // gallery screen — update Insights the same way.
            if deleted > 0 {
                let defaults = UserDefaults.standard
                defaults.set(
                    defaults.integer(forKey: "totalDeletedPhotos") + deleted,
                    forKey: "totalDeletedPhotos"
                )
                DailyStats.upsert(in: modelContext, deletedDelta: deleted)
            }
        }

        let albumID = gallery.albumIdentifier
        modelContext.delete(gallery)
        save()
        fetchGalleries()
        renumberDisplayOrder()

        // Not awaited, so callers can leave the gallery screen right away.
        if let albumID {
            Task { await service.deleteAlbum(identifier: albumID) }
        }
        return true
    }

    // MARK: - Private

    private func renumberDisplayOrder() {
        for (index, gallery) in galleries.enumerated() {
            gallery.displayOrder = index
        }
        save()
    }

    private func save() {
        try? modelContext.save()
    }
}
