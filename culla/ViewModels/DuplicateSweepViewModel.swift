import SwiftUI
import SwiftData
import Photos

@Observable
final class DuplicateSweepViewModel {

    enum Phase { case idle, scanning, comparing, done }

    // MARK: - State

    var phase: Phase = .idle

    /// The photo the user picked as reference.
    var referenceIdentifier: String?

    /// The current duplicate being compared against the reference.
    var currentDuplicateIdentifier: String?

    // Stats
    private(set) var totalDuplicatesFound: Int = 0
    var markedForDeletion: Int { markedIdentifiers.count }
    private(set) var currentIndex: Int = 0

    /// True when the reference photo is landscape (wider than tall).
    private(set) var isLandscape: Bool = false

    // MARK: - Private

    private var duplicateQueue: [String] = []
    /// Photos sent to the trash in this sweep (across every reference photo picked).
    /// "Delete N" deletes only these, not photos trashed earlier in swipe sessions.
    private var markedIdentifiers: [String] = []
    private let scanner = DuplicateScannerService()
    private let photoService = PhotoLibraryService.shared
    private let modelContext: ModelContext

    // Undo: stores (dismissed identifier, previous reference if it changed)
    private(set) var lastAction: DuplicateSweepAction?

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Search

    @MainActor
    func startSearch(for assetIdentifier: String, timeWindow: TimeInterval = 3600) async {
        phase = .scanning
        referenceIdentifier = assetIdentifier
        lastAction = nil

        updateOrientation(for: assetIdentifier)

        // Photos already waiting in the trash don't need a second verdict —
        // and dismissing one again would create a duplicate trash record.
        let dismissedRecords = (try? modelContext.fetch(FetchDescriptor<DismissedPhoto>())) ?? []
        let alreadyDismissed = Set(dismissedRecords.map(\.assetIdentifier))

        let matches = await scanner.findDuplicates(
            of: assetIdentifier,
            timeWindow: timeWindow,
            excluding: alreadyDismissed
        )

        totalDuplicatesFound = matches.count

        if matches.isEmpty {
            phase = .done
            return
        }

        duplicateQueue = matches
        currentDuplicateIdentifier = duplicateQueue.removeFirst()
        currentIndex = 1
        phase = .comparing
    }

    // MARK: - Actions

    /// User taps the reference photo — keep it, dismiss the duplicate.
    @MainActor
    func keepReference() {
        guard let duplicateID = currentDuplicateIdentifier else { return }

        dismiss(identifier: duplicateID)
        lastAction = .dismissedDuplicate(identifier: duplicateID)
        advance()
    }

    /// User taps the duplicate — keep it, dismiss the reference, duplicate becomes new reference.
    @MainActor
    func keepDuplicate() {
        guard let referenceID = referenceIdentifier,
              let duplicateID = currentDuplicateIdentifier else { return }

        dismiss(identifier: referenceID)
        lastAction = .dismissedReference(
            identifier: referenceID,
            newReference: duplicateID
        )
        referenceIdentifier = duplicateID
        updateOrientation(for: duplicateID)
        advance()
    }

    /// Skip this comparison without deciding.
    @MainActor
    func skip() {
        lastAction = nil
        advance()
    }

    /// Undo the last keep/dismiss action.
    @MainActor
    func undo() {
        guard let action = lastAction else { return }

        switch action {
        case .dismissedDuplicate(let identifier):
            removeDismissedRecord(identifier: identifier)
            markedIdentifiers.removeAll { $0 == identifier }
            restoreComparison(showing: identifier)

        case .dismissedReference(let identifier, let newReference):
            removeDismissedRecord(identifier: identifier)
            markedIdentifiers.removeAll { $0 == identifier }
            // Restore the old reference, and the layout that fits its shape
            referenceIdentifier = identifier
            updateOrientation(for: identifier)
            restoreComparison(showing: newReference)
        }

        lastAction = nil
    }

    /// Puts `duplicate` back on screen after an undo. The pair that was
    /// showing (if any) goes back to the front of the queue.
    private func restoreComparison(showing duplicate: String) {
        if let current = currentDuplicateIdentifier {
            duplicateQueue.insert(current, at: 0)
            currentIndex = max(currentIndex - 1, 1)
        }
        // No pair showing means we were on the "done" screen: the counter
        // never moved past the last pair, so it already has the right number.
        currentDuplicateIdentifier = duplicate
        phase = .comparing
    }

    /// Deletes the photos marked in this sweep — and only those, so photos trashed
    /// in swipe sessions keep waiting in the trash for review. Returns the count deleted.
    @MainActor
    func batchDelete() async -> Int {
        guard !markedIdentifiers.isEmpty else { return 0 }

        let marked = markedIdentifiers
        let deletedCount = await photoService.deletePhotos(identifiers: marked)
        // 0 means the user tapped "Don't Allow": keep everything marked.
        guard deletedCount > 0 else { return 0 }

        let descriptor = FetchDescriptor<DismissedPhoto>(
            predicate: #Predicate { marked.contains($0.assetIdentifier) }
        )
        do {
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
            try modelContext.save()
        } catch {
            print("culla: Failed to clear deleted duplicates from the trash: \(error)")
        }
        // Nothing is marked any more, which also hides the "Delete N" button.
        markedIdentifiers.removeAll()
        lastAction = nil

        return deletedCount
    }

    // MARK: - Private

    @MainActor
    private func advance() {
        if duplicateQueue.isEmpty {
            currentDuplicateIdentifier = nil
            phase = .done
            return
        }

        currentDuplicateIdentifier = duplicateQueue.removeFirst()
        currentIndex += 1
    }

    private func updateOrientation(for assetIdentifier: String) {
        if let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier], options: nil
        ).firstObject {
            isLandscape = asset.pixelWidth > asset.pixelHeight
        } else {
            isLandscape = false
        }
    }

    private func dismiss(identifier: String) {
        let dismissed = DismissedPhoto(assetIdentifier: identifier)
        modelContext.insert(dismissed)
        try? modelContext.save()
        markedIdentifiers.append(identifier)
    }

    private func removeDismissedRecord(identifier: String) {
        let predicate = #Predicate<DismissedPhoto> { $0.assetIdentifier == identifier }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let match = try? modelContext.fetch(descriptor).first {
            modelContext.delete(match)
            try? modelContext.save()
        }
    }

}

// MARK: - Action Types

enum DuplicateSweepAction {
    case dismissedDuplicate(identifier: String)
    case dismissedReference(identifier: String, newReference: String)
}
