import Photos
import Observation

/// Which swipe cards get a clutter chip, for one deck.
///
/// It checks the top card and the next two ahead of time, so the chip is
/// usually ready before a card shows, and stops waiting on cards that are
/// no longer coming up. The scoring runs in `PhotoQualityService`, off the
/// main thread, which also keeps the scores on disk for next time.
@Observable
final class ClutterFlagStore {

    /// Flags for the photos checked in this deck. A clean photo has no entry.
    private(set) var flags: [String: ClutterFlag] = [:]

    /// Photos with a final answer (flagged or clean), so they're never redone.
    @ObservationIgnored private var checked: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    func flag(for identifier: String?) -> ClutterFlag? {
        identifier.flatMap { flags[$0] }
    }

    /// Checks these photos and stops waiting on any other. An empty list
    /// stops everything (the Settings switch is off).
    func prefetch(_ identifiers: [String]) {
        let wanted = Set(identifiers)
        for (identifier, task) in tasks where !wanted.contains(identifier) {
            // The analysis itself still finishes and lands in the disk
            // cache, so a card that comes back later gets its chip at once.
            task.cancel()
            tasks[identifier] = nil
        }
        for identifier in identifiers where tasks[identifier] == nil && !checked.contains(identifier) {
            tasks[identifier] = Task { await self.check(identifier) }
        }
    }

    private func check(_ identifier: String) async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              asset.mediaType == .image else {
            // Gone, or a video: videos never get a chip.
            record(nil, for: identifier)
            return
        }

        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let quality = isScreenshot ? nil : await PhotoQualityService.shared.quality(for: identifier)
        // Cancelled means prefetch already dropped this task.
        guard !Task.isCancelled else { return }

        if !isScreenshot && quality == nil {
            // The service already logged why. Not marked as checked, so the
            // next prefetch that still wants this photo tries again.
            tasks[identifier] = nil
            return
        }
        record(ClutterFlag.strongest(isScreenshot: isScreenshot, quality: quality), for: identifier)
    }

    private func record(_ flag: ClutterFlag?, for identifier: String) {
        tasks[identifier] = nil
        checked.insert(identifier)
        if let flag {
            flags[identifier] = flag
        }
    }
}
