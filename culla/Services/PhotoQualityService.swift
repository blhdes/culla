import Vision
import Photos
import UIKit

/// What Vision thinks of one photo. Only these numbers are kept, never pixels.
nonisolated struct PhotoQuality: Codable, Sendable, Equatable {
    /// −1…1. Higher looks better: focus, exposure, framing.
    let score: Float
    /// Screenshots, receipts, documents, whiteboards: photos kept for the
    /// information in them, not as memories.
    let isUtility: Bool
    /// 0…1: how sure Vision is that the lens was dirty. Nil below iOS 26,
    /// which has no smudge check.
    let smudge: Float?
}

/// A photo's pixels ready for Vision, upright or with the rotation to apply.
nonisolated struct AnalysisImage: Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

/// Scores photos for the swipe card's clutter badge (Part Q of the iOS 27
/// kits plan), on the phone, and remembers each score on disk so a photo is
/// analysed only once. An edited photo (new `modificationDate`) is scored again.
///
/// An actor, so the analysis and the cache stay off the main thread.
actor PhotoQualityService {

    static let shared = PhotoQualityService()

    /// Vision's models work on small images; more pixels only cost time.
    nonisolated static let analysisSize = CGSize(width: 512, height: 512)

    /// Bump when the stored numbers change meaning (a new Vision revision, a
    /// new field): the old file is then ignored and photos are scored again.
    private static let cacheVersion = 1

    /// New scores wait this long before the file is rewritten, so a fast
    /// swipe session writes every few seconds instead of after every photo.
    private static let saveDelay: Duration = .seconds(5)

    private nonisolated struct CacheEntry: Codable {
        /// The photo's `modificationDate` when it was scored.
        let modified: Double?
        let quality: PhotoQuality
    }

    private nonisolated struct CacheFile: Codable {
        let version: Int
        let entries: [String: CacheEntry]
    }

    /// ~/Library/Caches: iOS may clear it when space runs low, which only
    /// means photos get scored again.
    private nonisolated static let cacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PhotoQuality.json")

    private var entries: [String: CacheEntry] = [:]
    private var cacheLoaded = false
    /// Analyses running now, so two cards asking for one photo share the work.
    private var inFlight: [String: Task<PhotoQuality?, Never>] = [:]
    private var saveTask: Task<Void, Never>?

    private init() {}

    // MARK: - Scores

    /// The scores for one photo: from the cache, or measured now. Nil for
    /// videos, for photos that are gone, and when the image or Vision fails.
    /// Failures aren't cached, so the next call tries again.
    func quality(for identifier: String) async -> PhotoQuality? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              asset.mediaType == .image else { return nil }

        loadCacheIfNeeded()
        let modified = asset.modificationDate?.timeIntervalSinceReferenceDate
        if let entry = entries[identifier], Self.isFresh(entry, modified: modified) {
            return entry.quality
        }

        if let running = inFlight[identifier] {
            return await running.value
        }
        let task = Task { await Self.analyze(asset) }
        inFlight[identifier] = task
        let quality = await task.value
        inFlight[identifier] = nil

        guard let quality else { return nil }
        entries[identifier] = CacheEntry(modified: modified, quality: quality)
        scheduleSave()
        return quality
    }

    /// A cached score still counts if the photo wasn't edited since, and if
    /// it already has the smudge check whenever this iPhone can run it.
    private static func isFresh(_ entry: CacheEntry, modified: Double?) -> Bool {
        switch (entry.modified, modified) {
        case (nil, nil):
            break
        case let (cached?, current?) where abs(cached - current) < 0.001:
            break
        default:
            return false
        }
        if #available(iOS 26, *), entry.quality.smudge == nil {
            return false
        }
        return true
    }

    // MARK: - Analysis

    @concurrent
    private nonisolated static func analyze(_ asset: PHAsset) async -> PhotoQuality? {
        guard let image = await loadAnalysisImage(for: asset) else { return nil }
        do {
            return try await measure(image)
        } catch {
            print("[quality] Vision failed for \(asset.localIdentifier): \(error)")
            return nil
        }
    }

    /// Both Vision checks in one pass over the same pixels.
    @concurrent
    nonisolated static func measure(_ image: AnalysisImage) async throws -> PhotoQuality {
        let handler = ImageRequestHandler(image.cgImage, orientation: image.orientation)
        if #available(iOS 26, *) {
            let (scores, smudge) = try await handler.perform(
                CalculateImageAestheticsScoresRequest(),
                DetectLensSmudgeRequest()
            )
            return PhotoQuality(score: scores.overallScore, isUtility: scores.isUtility, smudge: smudge.confidence)
        }
        let scores = try await handler.perform(CalculateImageAestheticsScoresRequest())
        return PhotoQuality(score: scores.overallScore, isUtility: scores.isUtility, smudge: nil)
    }

    /// A small, full-quality image. Never the low-resolution preview Photos
    /// shows while an iCloud photo downloads: that would score as blurry.
    @concurrent
    nonisolated static func loadAnalysisImage(for asset: PHAsset) async -> AnalysisImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast

        let identifier = asset.localIdentifier
        // `PHImageManager.default()`, not PhotoLibraryService's caching
        // manager: requests there can cancel the swipe deck's own preloading
        // and drop the callback (see CalendarThumbnailCache).
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: analysisSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !resumed else { return }
                // `.highQualityFormat` should call back once; a preview is skipped anyway.
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                resumed = true

                guard let image, let cgImage = image.cgImage else {
                    let error = info?[PHImageErrorKey] ?? "none"
                    let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
                    print("[quality] no image for \(identifier) (error: \(error), cancelled: \(cancelled))")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: AnalysisImage(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(image.imageOrientation)
                ))
            }
        }
    }

    // MARK: - Disk Cache

    /// Reads the file once, on the first request. Runs on the actor, never
    /// on the main thread.
    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true

        let data: Data
        do {
            data = try Data(contentsOf: Self.cacheURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return   // Nothing scored yet.
        } catch {
            print("[quality] couldn't read the score cache, starting fresh: \(error)")
            return
        }

        do {
            let file = try JSONDecoder().decode(CacheFile.self, from: data)
            guard file.version == Self.cacheVersion else {
                print("[quality] score cache is version \(file.version), starting fresh")
                return
            }
            entries = file.entries
            print("[quality] loaded \(entries.count) cached scores")
        } catch {
            print("[quality] score cache unreadable, starting fresh: \(error)")
        }
    }

    /// Saves at most once every `saveDelay`, however many photos were scored.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task {
            do {
                try await Task.sleep(for: Self.saveDelay)
            } catch {
                print("[quality] save timer cancelled, saving now")
            }
            self.saveNow()
        }
    }

    private func saveNow() {
        saveTask = nil
        let file = CacheFile(version: Self.cacheVersion, entries: entries)
        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            print("[quality] couldn't save \(entries.count) scores: \(error)")
        }
    }
}

nonisolated extension CGImagePropertyOrientation {
    /// Photos can hand back an image whose pixels aren't upright; Vision needs
    /// to know, or it judges the framing of a sideways photo.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
