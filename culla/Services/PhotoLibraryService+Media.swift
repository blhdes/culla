import AVFoundation
import Photos
import UIKit

extension PhotoLibraryService {

    // MARK: - Video Loading

    /// Loads a playable item for a video asset. Streams from iCloud when needed.
    func loadPlayerItem(for assetIdentifier: String) async -> AVPlayerItem? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = result.firstObject, asset.mediaType == .video else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        return await withCheckedContinuation { continuation in
            // requestPlayerItem can call back twice (degraded then final) —
            // resuming a continuation twice crashes, so guard against it.
            var resumed = false
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: item)
            }
        }
    }

    /// Returns the local file URL for a video asset, for sharing.
    /// Nil for images and for iCloud-only videos that can't expose a file URL.
    func loadVideoURL(for assetIdentifier: String) async -> URL? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = result.firstObject, asset.mediaType == .video else { return nil }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    // MARK: - Image Loading

    /// Returns a thumbnail UIImage for the most recent photo in an album.
    func fetchAlbumThumbnail(albumIdentifier: String, targetSize: CGSize) async -> UIImage? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumIdentifier], options: nil
        ).firstObject else { return nil }

        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        guard let asset = assets.firstObject else { return nil }

        return await loadImage(for: asset.localIdentifier, targetSize: targetSize)
    }

    /// Outcome of a single `requestImage` attempt, so the caller can tell a
    /// transient failure (worth retrying) from a permanently unavailable asset.
    private enum ImageRequestOutcome {
        case image(UIImage)
        /// Cancelled or errored mid-flight — usually transient under request
        /// contention, so retrying tends to succeed.
        case transient
        /// Final delivery with no image and no error — the asset has no
        /// renderable thumbnail (e.g. deleted). Retrying won't help.
        case unavailable
    }

    /// Request settings for display-quality images. Shared by `loadImage` and the
    /// swipe preloading (`startCaching`/`stopCaching`), because the caching manager
    /// only reuses a preloaded image when size, content mode and options all match.
    private static func displayImageOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return options
    }

    /// Loads a display-quality UIImage for the given asset identifier.
    func loadImage(
        for assetIdentifier: String,
        targetSize: CGSize
    ) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        ).firstObject else {
            return nil
        }

        let options = Self.displayImageOptions()

        // Flinging to the end of a grid fires many requests at once on the
        // shared caching manager, which can answer some with a cancelled/empty
        // result — leaving those cells stuck on the gray "photo" placeholder.
        // Those failures are transient, so retry a couple of times (with a
        // short backoff for the contention to clear) before giving up.
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }

            switch await requestImageOnce(for: asset, targetSize: targetSize, options: options) {
            case .image(let image):
                return image
            case .unavailable:
                return nil
            case .transient:
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
        return nil
    }

    /// One `requestImage` round-trip, resolving to a single ``ImageRequestOutcome``.
    private func requestImageOnce(
        for asset: PHAsset,
        targetSize: CGSize,
        options: PHImageRequestOptions
    ) async -> ImageRequestOutcome {
        await withCheckedContinuation { continuation in
            // Holds a degraded preview received while waiting for the iCloud download.
            // Used as fallback if the final high-quality delivery fails.
            var degradedFallback: UIImage? = nil
            var resumed = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil

                if isDegraded {
                    // Save as fallback; keep waiting for the high-quality version.
                    degradedFallback = image
                    return
                }

                guard !resumed else { return }
                resumed = true

                if let image {
                    // High-quality delivery succeeded.
                    continuation.resume(returning: .image(image))
                } else if let degradedFallback {
                    // Final delivery had no image, but we saved a preview earlier.
                    continuation.resume(returning: .image(degradedFallback))
                } else if isCancelled || hasError {
                    // Dropped under contention — retryable.
                    continuation.resume(returning: .transient)
                } else {
                    // Genuinely no thumbnail for this asset.
                    continuation.resume(returning: .unavailable)
                }
            }
        }
    }

    // MARK: - Preloading

    /// Tells PHCachingImageManager to start caching images for upcoming identifiers.
    /// Uses the same options as `loadImage`, otherwise the cached copy is never used.
    func startCaching(identifiers: [String], targetSize: CGSize) {
        let assets = fetchAssets(for: identifiers)
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: Self.displayImageOptions()
        )
    }

    /// Stops caching for identifiers that are no longer needed.
    func stopCaching(identifiers: [String], targetSize: CGSize) {
        let assets = fetchAssets(for: identifiers)
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: Self.displayImageOptions()
        )
    }

    private func fetchAssets(for identifiers: [String]) -> [PHAsset] {
        guard !identifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}
