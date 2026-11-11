import SwiftUI
import SwiftData
import Photos

/// Removes Culla's records for photos that no longer exist in the iPhone library —
/// deleted through Culla's trash or in the Photos app — so they stop showing up as
/// grey tiles in galleries and in the trash.
enum MissingPhotoCleaner {

    @MainActor
    static func prune(in context: ModelContext) async {
        // With limited access PhotoKit only sees the photos the user shared, so
        // every other photo would look deleted. Only clean up with full access.
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return }

        let recorded: Set<String>
        do {
            var sortedFetch = FetchDescriptor<SortedPhoto>()
            sortedFetch.propertiesToFetch = [\.assetIdentifier]
            var dismissedFetch = FetchDescriptor<DismissedPhoto>()
            dismissedFetch.propertiesToFetch = [\.assetIdentifier]
            recorded = Set(try context.fetch(sortedFetch).map(\.assetIdentifier))
                .union(try context.fetch(dismissedFetch).map(\.assetIdentifier))
        } catch {
            print("culla: Couldn't read records to check for deleted photos: \(error)")
            return
        }
        guard !recorded.isEmpty else { return }

        // The PhotoKit lookup can take a moment on big libraries — keep it off the main thread.
        let existing = await Task.detached {
            PhotoLibraryService.existingIdentifiers(among: recorded)
        }.value
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
            // Fetch again: records may have changed while PhotoKit was answering.
            let staleSorted = try context.fetch(FetchDescriptor<SortedPhoto>(
                predicate: #Predicate { missingIDs.contains($0.assetIdentifier) }
            ))
            let staleDismissed = try context.fetch(FetchDescriptor<DismissedPhoto>(
                predicate: #Predicate { missingIDs.contains($0.assetIdentifier) }
            ))
            staleSorted.forEach { context.delete($0) }
            staleDismissed.forEach { context.delete($0) }
            try context.save()
        } catch {
            print("culla: Failed to remove records for deleted photos: \(error)")
        }
    }
}

/// Invisible view that runs the cleanup at launch and shortly after every change
/// to the photo library. Kept separate so only it re-renders on library changes.
struct MissingPhotoCleanup: View {
    @Environment(\.modelContext) private var modelContext
    private let photoService = PhotoLibraryService.shared

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
                await MissingPhotoCleaner.prune(in: modelContext)
            }
    }
}
