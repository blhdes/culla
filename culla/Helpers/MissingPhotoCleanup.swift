import SwiftUI
import SwiftData
import Photos

/// Removes Culla's records for photos that no longer exist in the iPhone library —
/// deleted through Culla's trash or in the Photos app — so they stop showing up as
/// grey tiles in galleries and in the trash.
///
/// Normally it reads only what changed since its last run, from Photos' change
/// history (`LibraryChangeHistory`). It falls back to the full scan (every record
/// looked up in PhotoKit) the first time, once a day, and whenever the history
/// can't be read.
///
/// Works on its own database context, away from the main thread. With big imported
/// galleries, deleting and saving these records on the main thread froze the app at
/// launch for 10–20 seconds (long enough for iOS to kill it).
///
/// Create it inside `Task.detached`: a model actor made on the main thread does its
/// work on the main thread too, which would bring the freeze back.
@ModelActor
actor MissingPhotoCleaner {

    /// Has no `await` inside, so two calls never overlap: the actor runs them one after the other.
    func prune() {
        // With limited access PhotoKit only sees the photos the user shared, so
        // every other photo would look deleted. Only clean up with full access.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }

        guard let token = LibraryChangeHistory.savedToken() else {
            fullScan(reason: "no bookmark yet")
            return
        }
        guard !LibraryChangeHistory.isFullScanDue else {
            fullScan(reason: "daily check")
            return
        }
        do {
            pruneChanges(try LibraryChangeHistory.delta(since: token))
        } catch {
            fullScan(reason: error.description)
        }
    }

    // MARK: - Only what changed

    private func pruneChanges(_ delta: LibraryChangeHistory.Delta) {
        let summary = "\(delta.changeCount) changes: \(delta.insertedCount) new, \(delta.updated.count) updated, "
            + "\(delta.deleted.count) deleted photos, \(delta.albumChangeCount) album changes"

        // A photo deleted in Photos may first show up as "updated" (moved to Recently
        // Deleted), so updated photos that PhotoKit no longer finds count as gone too.
        let trashed = delta.updated.subtracting(PhotoLibraryService.existingIdentifiers(among: delta.updated))
        let gone = delta.deleted.union(trashed)
        guard !gone.isEmpty else {
            print("[cleanup] no deletions since last check (\(summary))")
            LibraryChangeHistory.save(delta.newestToken)
            return
        }

        // Keep the old bookmark on failure, so the same changes are read again next time.
        // The record count is only needed for the safety net, so only big batches pay for it.
        let total = gone.count > 20 ? recordCount() : nil
        guard let removed = removeRecords(for: gone, safetyNetTotal: total) else { return }
        LibraryChangeHistory.save(delta.newestToken)
        print("[cleanup] \(gone.count) photos gone (\(trashed.count) via updated), \(removed) records removed (\(summary))")
    }

    // MARK: - Full scan

    private func fullScan(reason: String) {
        // Taken before the scan, so a change made during it is read next time.
        let token = PHPhotoLibrary.shared().currentChangeToken
        let start = Date()

        let recorded: Set<String>
        do {
            var sortedFetch = FetchDescriptor<SortedPhoto>()
            sortedFetch.propertiesToFetch = [\.assetIdentifier]
            var dismissedFetch = FetchDescriptor<DismissedPhoto>()
            dismissedFetch.propertiesToFetch = [\.assetIdentifier]
            recorded = Set(try modelContext.fetch(sortedFetch).map(\.assetIdentifier))
                .union(try modelContext.fetch(dismissedFetch).map(\.assetIdentifier))
        } catch {
            print("[cleanup] couldn't read records to check for deleted photos: \(error)")
            return
        }

        let missing = recorded.subtracting(PhotoLibraryService.existingIdentifiers(among: recorded))
        var removed = 0
        if !missing.isEmpty {
            guard let count = removeRecords(for: missing, safetyNetTotal: recorded.count) else { return }
            removed = count
        }
        LibraryChangeHistory.save(token)
        LibraryChangeHistory.markFullScanDone()
        let seconds = String(format: "%.2f", Date().timeIntervalSince(start))
        print("[cleanup] full scan (\(reason)): \(recorded.count) photos checked, \(removed) records removed in \(seconds)s")
    }

    // MARK: - Removing records

    /// How many sorted and dismissed records there are, or nil if it can't tell
    /// (then the safety net is skipped, as the deletions came from Photos itself).
    private func recordCount() -> Int? {
        do {
            return try modelContext.fetchCount(FetchDescriptor<SortedPhoto>())
                + modelContext.fetchCount(FetchDescriptor<DismissedPhoto>())
        } catch {
            print("[cleanup] couldn't count records for the safety net: \(error)")
            return nil
        }
    }

    /// Deletes the sorted and dismissed records for `identifiers`. Returns how many
    /// were removed, or nil when it stopped (an error, or the safety net), in which
    /// case the caller keeps its old bookmark so the work is tried again.
    ///
    /// `safetyNetTotal` is how many photos have records, so a half-synced library
    /// (most photos missing at once) isn't wiped. Nil skips the check.
    private func removeRecords(for identifiers: Set<String>, safetyNetTotal: Int?) -> Int? {
        // Safety net: if most photos look gone at once, the library is more likely still
        // syncing (e.g. a phone restored from backup) than really emptied. Wait it out.
        if let total = safetyNetTotal, identifiers.count > 20, identifiers.count > total / 2 {
            print("[cleanup] \(identifiers.count) of \(total) photos look missing — skipping cleanup for now")
            return nil
        }

        let ids = Array(identifiers)
        do {
            let staleSorted = try modelContext.fetch(FetchDescriptor<SortedPhoto>(
                predicate: #Predicate { ids.contains($0.assetIdentifier) }
            ))
            let staleDismissed = try modelContext.fetch(FetchDescriptor<DismissedPhoto>(
                predicate: #Predicate { ids.contains($0.assetIdentifier) }
            ))
            staleSorted.forEach { modelContext.delete($0) }
            staleDismissed.forEach { modelContext.delete($0) }
            if modelContext.hasChanges { try modelContext.save() }
            return staleSorted.count + staleDismissed.count
        } catch {
            // Drop the half-made deletes so nothing partial is saved later by accident.
            modelContext.rollback()
            print("[cleanup] failed to remove records for deleted photos: \(error)")
            return nil
        }
    }
}

/// Invisible view that runs the cleanup at launch and shortly after every change
/// to the photo library. Kept separate so only it re-renders on library changes.
struct MissingPhotoCleanup: View {
    @Environment(\.modelContext) private var modelContext
    private let photoService = PhotoLibraryService.shared
    /// One cleaner for the whole session, so runs queue up instead of overlapping.
    @State private var cleaner: MissingPhotoCleaner?

    var body: some View {
        Color.clear
            .task(id: photoService.libraryChangeCount) {
                // Changes arrive in bursts while sorting; wait for a quiet moment.
                // A newer change cancels this wait, which is expected — just stop.
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                if cleaner == nil {
                    let container = modelContext.container
                    cleaner = await Task.detached(priority: .utility) {
                        MissingPhotoCleaner(modelContainer: container)
                    }.value
                }
                await cleaner?.prune()
            }
    }
}
