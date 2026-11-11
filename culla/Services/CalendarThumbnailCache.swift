import Photos
import UIKit

/// Shared pixel size for all calendar cell thumbnails.
/// The mosaic is 44pt tall; the largest cell (1-photo, widest iPhone) is ~57pt wide.
/// At @3x that's ~171×132px. 160×160px covers that with a small buffer while keeping
/// the 4-photo 2×2 case (78×66px) from fetching excess pixels.
nonisolated let CalendarThumbnailSize = CGSize(width: 160, height: 160)

/// Small square thumbnails for the calendar mosaic and the photo grid picker.
///
/// Looks in three places, fastest first: memory, then disk, then PhotoKit.
/// Only the memory lookup runs on the main thread; reading, requesting and
/// decoding all happen in the background, so the launch warm-up and a
/// fast-scrolled calendar don't stall the UI.
final class CalendarThumbnailCache {

    static let shared = CalendarThumbnailCache()

    private init() {}

    /// In-memory cache — avoids re-fetching when scrolling back.
    /// NSCache auto-evicts under memory pressure, so this is safe.
    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 50_000_000  // ~50 MB
        return cache
    }()

    /// Persistent disk cache for decoded thumbnails — survives app restarts.
    /// Located in ~/Library/Caches/CalendarThumbnails/. iOS auto-evicts under pressure.
    private static let diskCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("CalendarThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Loading

    /// Returns the thumbnail for an asset, or nil if the photo is gone or
    /// can't be loaded.
    func image(for assetIdentifier: String) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        let cacheKey = assetIdentifier as NSString
        if let cached = memory.object(forKey: cacheKey) {
            return cached
        }

        let diskPath = Self.diskPath(for: assetIdentifier)
        if let diskImage = await Self.readFromDisk(at: diskPath) {
            memory.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }

        guard let decoded = await Self.requestFromPhotoKit(for: assetIdentifier) else {
            return nil
        }
        memory.setObject(decoded, forKey: cacheKey)

        // Write to disk in background — don't await, return immediately
        Task.detached(priority: .background) {
            // PHImageManager delivers images with AlphaLast pixel format even for opaque
            // photos. JPEG has no alpha channel, so redraw into an opaque context first
            // to avoid doubled decode memory and bloated file sizes.
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = 1
            let opaque = UIGraphicsImageRenderer(size: decoded.size, format: format)
                .image { _ in decoded.draw(at: .zero) }
            guard let data = opaque.jpegData(compressionQuality: 0.85) else { return }

            // `.atomic` already writes to a temp file and renames it into
            // place, so readers never see a half-written file — and it
            // replaces any unreadable file left from an earlier run.
            do {
                try data.write(to: diskPath, options: .atomic)
            } catch {
                print("culla: Failed to write calendar thumbnail to disk cache: \(error)")
            }
        }

        return decoded
    }

    /// Loads many thumbnails into memory and disk ahead of time, at most 50 at once.
    /// Used at launch so the calendar opens with its cells already filled.
    func preload(_ identifiers: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            for id in identifiers {
                if inFlight >= 50 {
                    await group.next()
                    inFlight -= 1
                }
                group.addTask(priority: .background) { [self] in
                    _ = await self.image(for: id)
                }
                inFlight += 1
            }
        }
    }

    /// Forgets the thumbnails of deleted photos, in memory and on disk.
    func evict(_ identifiers: [String]) {
        for id in identifiers {
            memory.removeObject(forKey: id as NSString)
            // A missing file only means it was never cached, so there is nothing to report.
            try? FileManager.default.removeItem(at: Self.diskPath(for: id))
        }
    }

    // MARK: - Private

    /// Returns the disk cache file path for an asset identifier.
    /// PHAsset identifiers contain "/" — replace with "-" to make filename-safe.
    private static func diskPath(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "-")
        return diskCacheDir.appendingPathComponent("\(safe).jpg")
    }

    /// Reads and decodes a disk-cached thumbnail in the background. A missing
    /// file is the normal "not cached yet" case, and an unreadable one is simply
    /// overwritten by the next fresh write, so both return nil.
    @concurrent
    private nonisolated static func readFromDisk(at url: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        // Decode the pixels now so drawing the cell later is only compositing.
        return image.preparingForDisplay() ?? image
    }

    /// Asks PhotoKit for a thumbnail and decodes it, all in the background.
    /// Uses opportunistic delivery (first usable image wins, no waiting on
    /// iCloud) and aspectFill so the image fills the cell without letterboxing.
    @concurrent
    private nonisolated static func requestFromPhotoKit(for assetIdentifier: String) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else { return nil }

        guard !Task.isCancelled else { return nil }

        let options = PHImageRequestOptions()
        // opportunistic: delivers the best locally-available thumbnail immediately,
        // then a higher-quality version if needed.
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.isSynchronous = false

        // Use PHImageManager.default() rather than PhotoLibraryService's caching
        // manager, which the swipe preloading uses: requests on the caching manager
        // can cancel its own preheat for the same asset and silently drop the callback.
        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CalendarThumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil

                if let image {
                    // Accept first non-nil result (degraded or not) — good enough for
                    // a calendar thumbnail; prevents waiting for a slow iCloud download.
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: image)
                } else if !isDegraded || isCancelled || hasError {
                    // Final callback with nil (truly unavailable) or an error.
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: nil)
                }
                // nil + isDegraded → still downloading; wait for the next callback.
            }
        }

        guard let image else { return nil }
        // Decode the pixels now so drawing the cell later is only compositing.
        return image.preparingForDisplay() ?? image
    }
}
