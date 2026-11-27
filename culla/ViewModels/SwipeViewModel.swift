import SwiftUI
import SwiftData
import Photos

@Observable
final class SwipeViewModel {

    // MARK: - State

    var currentIdentifier: String? {
        didSet {
            #if DEBUG
            if let currentIdentifier, currentIdentifier != oldValue {
                PhotoQualitySpike.shared.cardShown(currentIdentifier)
                VideoHighlightSpike.shared.cardShown(currentIdentifier)
            }
            #endif
        }
    }
    var nextIdentifier: String?
    var isLoading = false
    var isEmpty = false

    // Progress
    private(set) var totalCount: Int = 0
    private(set) var processedCount: Int = 0

    // Current photo metadata
    var currentPhotoDate: Date?
    var currentPhotoIsFavorite: Bool = false

    // Focus Session tracking
    private(set) var sessionSortedCount: Int = 0
    private(set) var sessionDismissedCount: Int = 0
    private(set) var sessionGalleries: Set<UUID> = []

    // MARK: - Dependencies

    private let photoService: PhotoLibraryService
    private let modelContext: ModelContext
    private let startDate: Date
    private let albumIdentifier: String?
    private let sortMode: SortMode
    private let isOnThisDay: Bool

    // MARK: - Queue

    private var identifierQueue: [String] = []
    private var cachedIdentifiers: [String] = []

    /// The top card and the two after it, for work that should be ready
    /// before a card shows (the clutter chip's scores).
    var upcomingIdentifiers: [String] {
        [currentIdentifier, nextIdentifier].compactMap { $0 } + identifierQueue.prefix(1)
    }

    // MARK: - Album Sync

    /// The most recent iPhone-album write. Each new write waits for the one
    /// before it, so a sort and its undo always reach Photos in the order the
    /// user made them — even when undo is tapped before the sort has finished.
    private var albumSyncTask: Task<Void, Never>?

    /// The real iPhone album that photos are moved out of — nil when sorting
    /// copies, or when the source is a virtual album with nothing to remove from.
    private var moveSourceAlbum: String? {
        guard sortMode == .move,
              let albumIdentifier,
              albumIdentifier != PhoneAlbum.unsortedIdentifier,
              albumIdentifier != PhoneAlbum.favoritesIdentifier else { return nil }
        return albumIdentifier
    }

    // MARK: - Undo

    private(set) var actionHistory: [SwipeAction] = []
    var canUndo: Bool { !actionHistory.isEmpty }

    // MARK: - Cached Counts

    /// Cached count of dismissed photos — updated only on dismiss/undo/delete, not every frame.
    private(set) var dismissedCount: Int = 0

    // MARK: - Init

    init(
        photoService: PhotoLibraryService,
        modelContext: ModelContext,
        startDate: Date,
        albumIdentifier: String? = nil,
        sortMode: SortMode = .copy,
        isOnThisDay: Bool = false
    ) {
        self.photoService = photoService
        self.modelContext = modelContext
        self.startDate = startDate
        self.albumIdentifier = albumIdentifier
        self.sortMode = sortMode
        self.isOnThisDay = isOnThisDay
        self.dismissedCount = Self.fetchDismissedCount(modelContext: modelContext)
    }

    private static func fetchDismissedCount(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<DismissedPhoto>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Initial Load

    @MainActor
    func loadInitialBatch() async {
        guard !isLoading, identifierQueue.isEmpty, currentIdentifier == nil else { return }
        isLoading = true
        actionHistory.removeAll()

        let excludedIDs = fetchExcludedIdentifiers()
        let service = photoService
        let onThisDay = isOnThisDay
        let start = startDate
        let album = albumIdentifier
        // "From the very first photo" uses no album membership filter — same as culling all photos.
        let effectiveAlbum = album == PhoneAlbum.unsortedIdentifier ? nil : album

        // Walking a big library takes a moment, so do it in the background:
        // the screen keeps showing "Loading photos..." instead of freezing.
        let fetched = await Task.detached(priority: .userInitiated) { () -> [String] in
            if onThisDay {
                return service.fetchOnThisDayIdentifiers(excluding: excludedIDs, inAlbum: album)
            }
            return service.fetchAssetIdentifiers(from: start, excluding: excludedIDs, inAlbum: effectiveAlbum)
        }.value

        totalCount = fetched.count

        guard !fetched.isEmpty else {
            isEmpty = true
            isLoading = false
            return
        }

        // First photo is the top card, second waits behind it, the rest queue up.
        var queue = fetched
        let first = queue.removeFirst()
        currentIdentifier = first
        let info = photoService.assetInfo(for: first)
        currentPhotoDate = info?.creationDate
        currentPhotoIsFavorite = info?.isFavorite ?? false

        if !queue.isEmpty {
            nextIdentifier = queue.removeFirst()
        }
        identifierQueue = queue

        // Preload upcoming photos
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * 2, height: screenSize.height * 2)
        cachedIdentifiers = Array(identifierQueue.prefix(3))
        photoService.startCaching(identifiers: cachedIdentifiers, targetSize: targetSize)

        isLoading = false
    }

    // MARK: - Swipe Actions

    /// Swipe left: dismiss current photo.
    @MainActor
    func dismissCurrent() {
        guard let identifier = currentIdentifier else { return }

        let dismissed = DismissedPhoto(assetIdentifier: identifier)
        modelContext.insert(dismissed)
        try? modelContext.save()

        actionHistory.append(.dismissed(assetIdentifier: identifier, record: dismissed))
        #if DEBUG
        PhotoQualitySpike.shared.record(.dismissed, for: identifier)
        #endif
        dismissedCount += 1
        sessionDismissedCount += 1
        advance()
    }

    /// Double-tap: skip photo without dismissing — it will reappear next session.
    @MainActor
    func skipCurrent() {
        guard let identifier = currentIdentifier else { return }
        actionHistory.append(.skipped(assetIdentifier: identifier))
        #if DEBUG
        PhotoQualitySpike.shared.record(.skipped, for: identifier)
        #endif
        advance()
    }

    /// Called when user sorts a photo into a gallery. Returns what changed,
    /// so the screen can say "Already in …" when the photo was there before
    /// (nil when there was no photo to sort).
    @MainActor
    @discardableResult
    func assignToGallery(_ gallery: Gallery) -> SortChange? {
        guard let identifier = currentIdentifier else { return nil }

        let change = recordSort(of: identifier, into: gallery)

        actionHistory.append(.sorted(assetIdentifier: identifier, gallery: gallery, change: change))
        #if DEBUG
        PhotoQualitySpike.shared.record(.sorted, for: identifier)
        #endif
        sessionSortedCount += 1
        sessionGalleries.insert(gallery.id)
        advance()

        // Sync to iPhone Photos album (background, non-blocking)
        enqueueAlbumSync { [self] in
            if case .added = change, let albumID = await ensureAlbumExists(for: gallery) {
                await photoService.addPhoto(assetIdentifier: identifier, toAlbum: albumID)
            }

            // If moving (not copying), remove from source album
            if let sourceAlbum = moveSourceAlbum {
                await photoService.removePhoto(assetIdentifier: identifier, fromAlbum: sourceAlbum)
            }
        }
        return change
    }

    /// Saves that `identifier` belongs to `gallery`. This Day and imported photos can
    /// show a photo that is already in that gallery: then no second record is made
    /// (it would show twice, and undoing it would take the photo out of the album).
    @MainActor
    private func recordSort(of identifier: String, into gallery: Gallery) -> SortChange {
        let existing = gallery.sortedPhotos.filter { $0.assetIdentifier == identifier }

        if existing.contains(where: { !$0.isImported }) {
            return .unchanged
        }

        if let imported = existing.first {
            // It came in with an album import; from now on it counts as sorted by the user.
            let previousSortedAt = imported.sortedAt
            imported.isImported = false
            imported.sortedAt = .now
            saveContext()
            return .confirmedImport(imported, previousSortedAt: previousSortedAt)
        }

        let sorted = SortedPhoto(assetIdentifier: identifier, gallery: gallery)
        modelContext.insert(sorted)
        saveContext()
        return .added(sorted)
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("culla: Failed to save a sort: \(error)")
        }
    }

    // MARK: - Undo

    @MainActor
    func undo() {
        guard let action = actionHistory.last else { return }
        actionHistory.removeLast()

        switch action {
        case .dismissed(let identifier, let record):
            modelContext.delete(record)
            try? modelContext.save()
            dismissedCount = max(dismissedCount - 1, 0)
            sessionDismissedCount = max(sessionDismissedCount - 1, 0)
            pushBackToFront(identifier: identifier)

        case .sorted(let identifier, let gallery, let change):
            switch change {
            case .added(let record):
                modelContext.delete(record)
                saveContext()
            case .confirmedImport(let record, let previousSortedAt):
                record.isImported = true
                record.sortedAt = previousSortedAt
                saveContext()
            case .unchanged:
                break
            }
            sessionSortedCount = max(sessionSortedCount - 1, 0)
            pushBackToFront(identifier: identifier)
            enqueueAlbumSync { [self] in
                // Only a new sort added the photo to the album; otherwise it was
                // already there and must stay. Read the album ID here, not before
                // queueing: on a gallery's first sort the album may still be being
                // created when undo is tapped, and it only gets its ID once that finishes.
                if case .added = change, let albumID = gallery.albumIdentifier {
                    await photoService.removePhoto(assetIdentifier: identifier, fromAlbum: albumID)
                }
                // A "move" took the photo out of its source album — put it back.
                if let sourceAlbum = moveSourceAlbum {
                    await photoService.addPhoto(assetIdentifier: identifier, toAlbum: sourceAlbum)
                }
            }

        case .skipped(let identifier):
            pushBackToFront(identifier: identifier)
        }
    }

    // MARK: - Batch Delete

    /// Deletes all dismissed photos from the iPhone library.
    /// Returns the number of photos deleted (0 if user denied or nothing to delete).
    @MainActor
    func batchDeleteDismissed() async -> Int {
        let descriptor = FetchDescriptor<DismissedPhoto>()
        guard let dismissed = try? modelContext.fetch(descriptor), !dismissed.isEmpty else {
            return 0
        }

        let identifiers = dismissed.map(\.assetIdentifier)
        let deletedCount = await photoService.deletePhotos(identifiers: identifiers)

        // Only clean up records if the deletion actually happened
        if deletedCount > 0 {
            for record in dismissed {
                modelContext.delete(record)
            }
            try? modelContext.save()
            dismissedCount = 0
        }

        return deletedCount
    }

    // MARK: - Private

    @MainActor
    private func advance() {
        processedCount += 1
        currentIdentifier = nextIdentifier

        if let current = currentIdentifier {
            let info = photoService.assetInfo(for: current)
            currentPhotoDate = info?.creationDate
            currentPhotoIsFavorite = info?.isFavorite ?? false
        } else {
            currentPhotoDate = nil
            currentPhotoIsFavorite = false
        }

        if identifierQueue.isEmpty {
            nextIdentifier = nil
            if currentIdentifier == nil {
                isEmpty = true
            }
            return
        }

        nextIdentifier = identifierQueue.removeFirst()

        // Update cache window — stop caching old images, start caching new ones
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * 2, height: screenSize.height * 2)
        let newWindow = Array(identifierQueue.prefix(3))
        let stale = cachedIdentifiers.filter { !newWindow.contains($0) }
        if !stale.isEmpty {
            photoService.stopCaching(identifiers: stale, targetSize: targetSize)
        }
        cachedIdentifiers = newWindow
        photoService.startCaching(identifiers: newWindow, targetSize: targetSize)
    }

    private func pushBackToFront(identifier: String) {
        #if DEBUG
        PhotoQualitySpike.shared.undo(identifier)
        #endif
        processedCount = max(processedCount - 1, 0)
        // Move next → back to queue front, current → next, restored → current
        if let next = nextIdentifier {
            identifierQueue.insert(next, at: 0)
        }
        nextIdentifier = currentIdentifier
        currentIdentifier = identifier
        let info = photoService.assetInfo(for: identifier)
        currentPhotoDate = info?.creationDate
        currentPhotoIsFavorite = info?.isFavorite ?? false
        isEmpty = false
    }

    private func fetchExcludedIdentifiers() -> Set<String> {
        // Dismissed photos are always left out: they're waiting in the trash.
        // Sorted photos (non-imports) are left out too, except in This Day, which
        // revisits every photo from this date, sorted or not.
        // Imported photos always appear so the user can move/copy them to other galleries.
        var excluded = Set<String>()

        if !isOnThisDay {
            let sortedDescriptor = FetchDescriptor<SortedPhoto>(
                predicate: #Predicate<SortedPhoto> { !$0.isImported }
            )
            if let sorted = try? modelContext.fetch(sortedDescriptor) {
                excluded.formUnion(sorted.map(\.assetIdentifier))
            }
        }

        let dismissedDescriptor = FetchDescriptor<DismissedPhoto>()
        if let dismissed = try? modelContext.fetch(dismissedDescriptor) {
            excluded.formUnion(dismissed.map(\.assetIdentifier))
        }

        return excluded
    }

    /// Queues an iPhone-album write behind any write still in flight.
    private func enqueueAlbumSync(_ work: @escaping @MainActor () async -> Void) {
        let previous = albumSyncTask
        albumSyncTask = Task {
            await previous?.value
            await work()
        }
    }

    /// Creates the iPhone album for a gallery if it doesn't exist yet.
    /// Returns the album identifier.
    private func ensureAlbumExists(for gallery: Gallery) async -> String? {
        if let existing = gallery.albumIdentifier {
            return existing
        }

        let albumID = await photoService.createAlbum(name: gallery.name)
        if let albumID {
            await MainActor.run {
                gallery.albumIdentifier = albumID
                try? modelContext.save()
            }
        }
        return albumID
    }
}

// MARK: - Supporting Types

enum SwipeAction {
    case dismissed(assetIdentifier: String, record: DismissedPhoto)
    case sorted(assetIdentifier: String, gallery: Gallery, change: SortChange)
    case skipped(assetIdentifier: String)
}

/// What sorting a photo changed, so undo reverses exactly that.
enum SortChange {
    /// A new record was saved and the photo added to the gallery's album.
    case added(SortedPhoto)
    /// The photo was in the gallery as an import; it now counts as sorted by the user.
    case confirmedImport(SortedPhoto, previousSortedAt: Date)
    /// The photo was already sorted into this gallery: nothing changed.
    case unchanged
}

/// When sorting from an existing album, determines whether photos
/// are moved out of the source album or kept in both.
enum SortMode {
    case move   // remove from source album after sorting
    case copy   // keep in source album too
}
