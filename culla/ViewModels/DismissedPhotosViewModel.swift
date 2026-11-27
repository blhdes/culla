import SwiftUI
import SwiftData

@Observable
final class DismissedPhotosViewModel {

    var dismissedPhotos: [DismissedPhoto] = []
    var selectedIdentifiers: Set<String> = []
    var isDeleting = false

    var hasSelection: Bool { !selectedIdentifiers.isEmpty }
    var selectedCount: Int { selectedIdentifiers.count }

    /// Bytes per dismissed photo, measured once when the trash opens (iOS 27).
    /// A photo whose size Photos doesn't report has no entry.
    private var byteSizes: [String: Int64] = [:]

    /// What the Delete button would free right now: the selection, or the
    /// whole trash when nothing is selected. `nil` (so nothing is shown) below
    /// iOS 27, while measuring, when nothing would be freed, or when any of
    /// the photos has an unknown size, so the number is never a guess.
    var bytesToFree: Int64? {
        let targets = hasSelection ? Array(selectedIdentifiers) : dismissedPhotos.map(\.assetIdentifier)
        var total: Int64 = 0
        for identifier in targets {
            guard let bytes = byteSizes[identifier] else { return nil }
            total += bytes
        }
        return total > 0 ? total : nil
    }

    private let photoService = PhotoLibraryService.shared
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Load

    func loadDismissedPhotos() {
        let descriptor = FetchDescriptor<DismissedPhoto>(
            sortBy: [SortDescriptor(\.dismissedAt, order: .reverse)]
        )
        dismissedPhotos = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Reads every dismissed photo's size off the main thread. Only on iOS 27,
    /// where Photos has a public size API; the older hidden value is too
    /// fragile to show before a delete. The trash only shrinks while it's open,
    /// so one measurement per visit is enough.
    func measureSizes() async {
        guard #available(iOS 27, *) else { return }
        let identifiers = dismissedPhotos.map(\.assetIdentifier)
        guard !identifiers.isEmpty else { return }
        byteSizes = await Task.detached(priority: .utility) {
            PhotoLibraryService.byteSizes(of: identifiers)
        }.value
    }

    // MARK: - Selection

    func toggleSelection(_ identifier: String) {
        if selectedIdentifiers.contains(identifier) {
            selectedIdentifiers.remove(identifier)
        } else {
            selectedIdentifiers.insert(identifier)
        }
    }

    func selectAll() {
        selectedIdentifiers = Set(dismissedPhotos.map(\.assetIdentifier))
    }

    func deselectAll() {
        selectedIdentifiers.removeAll()
    }

    // MARK: - Recover

    /// Removes DismissedPhoto records from SwiftData. Photos stay in the library.
    func recoverSelected() {
        for photo in dismissedPhotos where selectedIdentifiers.contains(photo.assetIdentifier) {
            modelContext.delete(photo)
        }
        try? modelContext.save()
        selectedIdentifiers.removeAll()
        loadDismissedPhotos()
    }

    func recoverAll() {
        for photo in dismissedPhotos {
            modelContext.delete(photo)
        }
        try? modelContext.save()
        selectedIdentifiers.removeAll()
        loadDismissedPhotos()
    }

    // MARK: - Delete

    /// Permanently deletes photos from the library and removes SwiftData records.
    @MainActor
    func deleteSelected() async -> Int {
        guard !isDeleting else { return 0 }
        isDeleting = true
        let targets = dismissedPhotos.filter { selectedIdentifiers.contains($0.assetIdentifier) }
        let identifiers = targets.map(\.assetIdentifier)

        let count = await photoService.deletePhotos(identifiers: identifiers)

        if count > 0 {
            for record in targets {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }

        selectedIdentifiers.removeAll()
        loadDismissedPhotos()
        isDeleting = false
        return count
    }

    @MainActor
    func deleteAll() async -> Int {
        guard !isDeleting else { return 0 }
        isDeleting = true
        let identifiers = dismissedPhotos.map(\.assetIdentifier)

        let count = await photoService.deletePhotos(identifiers: identifiers)

        if count > 0 {
            for record in dismissedPhotos {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }

        selectedIdentifiers.removeAll()
        loadDismissedPhotos()
        isDeleting = false
        return count
    }
}
