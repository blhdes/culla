import SwiftUI
import SwiftData
import Photos

/// Removes Culla's records for photos that no longer exist in the iPhone library —
/// deleted through Culla's trash or in the Photos app — so they stop showing up as
/// grey tiles in galleries and in the trash.
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

        let recorded: Set<String>
        do {
            var sortedFetch = FetchDescriptor<SortedPhoto>()
            sortedFetch.propertiesToFetch = [\.assetIdentifier]
            var dismissedFetch = FetchDescriptor<DismissedPhoto>()
            dismissedFetch.propertiesToFetch = [\.assetIdentifier]
            recorded = Set(try modelContext.fetch(sortedFetch).map(\.assetIdentifier))
                .union(try modelContext.fetch(dismissedFetch).map(\.assetIdentifier))
        } catch {
            print("culla: Couldn't read records to check for deleted photos: \(error)")
            return
        }
        guard !recorded.isEmpty else { return }

        let existing = PhotoLibraryService.existingIdentifiers(among: recorded)
        let missing = recorded.subtracting(existing)
        guard !missing.isEmpty else { return }

        // Safety net: if most photos look gone at once, the library is more likely still
        // syncing (e.g. a phone restored from backup) than really emptied. Wait it out.
        if missing.count > 20 && missing.count > recorded.count / 2 {
            print("culla: \(missing.count) of \(recorded.count) photos look missing — skipping cleanup for now")
            return
        }

        let missingIDs = Array(missing)
        do {
            let staleSorted = try modelContext.fetch(FetchDescriptor<SortedPhoto>(
                predicate: #Predicate { missingIDs.contains($0.assetIdentifier) }
            ))
            let staleDismissed = try modelContext.fetch(FetchDescriptor<DismissedPhoto>(
                predicate: #Predicate { missingIDs.contains($0.assetIdentifier) }
            ))
            staleSorted.forEach { modelContext.delete($0) }
            staleDismissed.forEach { modelContext.delete($0) }
            try modelContext.save()
        } catch {
            // Drop the half-made deletes so nothing partial is saved later by accident.
            modelContext.rollback()
            print("culla: Failed to remove records for deleted photos: \(error)")
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
