import Vision
import Photos
import UIKit

/// Finds visually similar photos near a reference photo using Vision's
/// feature prints (a numeric "fingerprint" of what a photo shows).
///
/// One instance lives for one Duplicate Sweep, and so does its fingerprint
/// cache: picking the next photo of the same burst reuses the prints its
/// neighbours already got.
final class DuplicateScannerService {

    private let photoService = PhotoLibraryService.shared

    /// Photos fingerprinted at the same time. Overlaps the thumbnail loads
    /// with Vision's work without flooding the image manager.
    private static let maxConcurrentFingerprints = 4

    /// Fingerprinting doesn't need full resolution.
    private static let thumbnailSize = CGSize(width: 300, height: 300)

    /// Prints made in this sweep, keyed by `localIdentifier`. Only successes
    /// are stored, so a photo that failed to load is tried again next time.
    private var fingerprintCache: [String: FeaturePrintObservation] = [:]

    #if DEBUG
    /// V0 spike: thumbnails printed in the current scan, kept until the old
    /// request has run on exactly the same pixels.
    private var spikeImages: [String: CGImage] = [:]
    /// V0 spike: the old API's prints, kept for the sweep like the new ones.
    private var spikeOldPrints: [String: VNFeaturePrintObservation] = [:]
    #endif

    /// Fingerprint a single photo and find similar photos nearby in time.
    /// Returns identifiers of matching photos, sorted by similarity (closest first).
    func findDuplicates(
        of assetIdentifier: String,
        timeWindow: TimeInterval = 3600,
        distanceThreshold: Double = 0.65,
        excluding: Set<String>
    ) async -> [String] {
        // 1. Get the reference asset and its creation date
        guard let referenceAsset = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier], options: nil
        ).firstObject,
              let referenceDate = referenceAsset.creationDate else {
            return []
        }

        // 2. Nearby photos within the time window (capped at 50 to avoid long
        // hangs). Checked before fingerprinting, so a lone photo costs nothing.
        let neighborIDs = Array(fetchNearbyIdentifiers(
            around: referenceDate,
            timeWindow: timeWindow,
            excluding: excluding.union([assetIdentifier])
        ).prefix(50))

        guard !neighborIDs.isEmpty else { return [] }

        let started = Date()
        let cachedCount = neighborIDs.count(where: { fingerprintCache[$0] != nil })

        // 3. Fingerprint the reference, then its neighbours a few at a time
        guard let referencePrint = await fingerprint(for: assetIdentifier) else {
            return []
        }
        let neighborPrints = await fingerprints(for: neighborIDs)

        // 4. Compare each neighbour to the reference
        var matches: [(identifier: String, distance: Double)] = []

        for neighborID in neighborIDs {
            guard let neighborPrint = neighborPrints[neighborID] else { continue }

            do {
                let distance = try referencePrint.distance(to: neighborPrint)
                if distance < distanceThreshold {
                    matches.append((identifier: neighborID, distance: distance))
                }
            } catch {
                print("[dupes] distance failed for \(neighborID): \(error)")
            }
        }

        let seconds = Date().timeIntervalSince(started)
        print("[dupes] scanned \(neighborIDs.count) neighbours (\(cachedCount) cached) in \(String(format: "%.2f", seconds))s, \(matches.count) matches")

        #if DEBUG
        if DebugFlags.logDuplicateDistances {
            await logOldVersusNew(
                reference: assetIdentifier,
                referencePrint: referencePrint,
                neighborPrints: neighborPrints,
                threshold: distanceThreshold
            )
        }
        #endif

        // 5. Sort by similarity (closest first)
        matches.sort { $0.distance < $1.distance }
        return matches.map(\.identifier)
    }

    // MARK: - Fingerprints

    /// Prints for many photos, at most `maxConcurrentFingerprints` at once.
    /// Photos that couldn't be printed are left out of the result.
    private func fingerprints(for identifiers: [String]) async -> [String: FeaturePrintObservation] {
        var results: [String: FeaturePrintObservation] = [:]
        var pending = identifiers.makeIterator()

        await withTaskGroup(of: (String, FeaturePrintObservation?).self) { group in
            for _ in 0..<Self.maxConcurrentFingerprints {
                guard let identifier = pending.next() else { break }
                group.addTask { (identifier, await self.fingerprint(for: identifier)) }
            }

            // Each time one finishes, start the next, so 4 stay in flight.
            for await (identifier, featurePrint) in group {
                if let featurePrint {
                    results[identifier] = featurePrint
                }
                if let next = pending.next() {
                    group.addTask { (next, await self.fingerprint(for: next)) }
                }
            }
        }

        return results
    }

    /// The print for one photo: from the sweep's cache, or made fresh.
    private func fingerprint(for identifier: String) async -> FeaturePrintObservation? {
        if let cached = fingerprintCache[identifier] {
            return cached
        }

        guard let image = await photoService.loadImage(for: identifier, targetSize: Self.thumbnailSize),
              let cgImage = image.cgImage else {
            print("[dupes] no thumbnail for \(identifier)")
            return nil
        }

        // The same setup as the old `VNGenerateImageFeaturePrintRequest` on
        // iOS 18+: revision 2 (the only one this API offers) and scale-to-fill.
        var request = GenerateImageFeaturePrintRequest()
        request.cropAndScaleAction = .scaleToFill

        do {
            // `perform` is async and runs off the main thread on its own, so
            // the "Finding duplicates…" screen keeps animating.
            let featurePrint = try await request.perform(on: cgImage)
            fingerprintCache[identifier] = featurePrint
            #if DEBUG
            if DebugFlags.logDuplicateDistances {
                spikeImages[identifier] = cgImage
            }
            #endif
            return featurePrint
        } catch {
            print("[dupes] fingerprint failed for \(identifier): \(error)")
            return nil
        }
    }

    // MARK: - Nearby Photos

    /// Fetches photo identifiers within ±timeWindow of a given date.
    private func fetchNearbyIdentifiers(
        around date: Date,
        timeWindow: TimeInterval,
        excluding: Set<String>
    ) -> [String] {
        let startDate = date.addingTimeInterval(-timeWindow)
        let endDate = date.addingTimeInterval(timeWindow)

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
            startDate as NSDate,
            endDate as NSDate,
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let result = PHAsset.fetchAssets(with: options)

        var identifiers: [String] = []
        result.enumerateObjects { asset, _, _ in
            if !excluding.contains(asset.localIdentifier) {
                identifiers.append(asset.localIdentifier)
            }
        }

        return identifiers
    }

    // MARK: - V0 Spike (Debug only)

    #if DEBUG
    /// Runs the old request on the same thumbnails the new one used and logs
    /// both distances per pair, so the device session can confirm the 0.65
    /// threshold still means the same thing. Runs after the timed part.
    private func logOldVersusNew(
        reference: String,
        referencePrint: FeaturePrintObservation,
        neighborPrints: [String: FeaturePrintObservation],
        threshold: Double
    ) async {
        // Old prints for this scan's fresh thumbnails, then free the pixels.
        var samePhotoDistances: [Double] = []
        for (identifier, cgImage) in spikeImages {
            guard let oldPrint = await Self.oldFingerprint(of: cgImage) else { continue }
            spikeOldPrints[identifier] = oldPrint
            guard let newPrint = fingerprintCache[identifier] else { continue }
            // Old and new print of the very same photo: 0 means the same model.
            do {
                samePhotoDistances.append(try FeaturePrintObservation(oldPrint).distance(to: newPrint))
            } catch {
                print("[dupes] spike: same-photo distance failed for \(identifier): \(error)")
            }
        }
        spikeImages.removeAll()

        guard let referenceOld = spikeOldPrints[reference] else {
            print("[dupes] spike: no old print for the reference, skipping")
            return
        }

        var maxDelta = 0.0
        var oldMatches = 0
        var newMatches = 0
        var disagreements = 0

        for (identifier, newPrint) in neighborPrints {
            guard let neighborOld = spikeOldPrints[identifier] else { continue }
            do {
                var oldDistance: Float = 0
                try referenceOld.computeDistance(&oldDistance, to: neighborOld)
                let newDistance = try referencePrint.distance(to: newPrint)
                let delta = abs(Double(oldDistance) - newDistance)
                maxDelta = max(maxDelta, delta)

                let oldMatch = Double(oldDistance) < threshold
                let newMatch = newDistance < threshold
                if oldMatch { oldMatches += 1 }
                if newMatch { newMatches += 1 }
                if oldMatch != newMatch { disagreements += 1 }

                let flag = oldMatch != newMatch ? "  DISAGREE" : ""
                print("[dupes] old=\(String(format: "%.4f", oldDistance)) new=\(String(format: "%.4f", newDistance)) Δ=\(String(format: "%.4f", delta))\(flag)")
            } catch {
                print("[dupes] spike: distance failed for \(identifier): \(error)")
            }
        }

        let samePhotoMax = samePhotoDistances.max() ?? 0
        print("[dupes] spike: max Δ=\(String(format: "%.4f", maxDelta)), matches old=\(oldMatches) new=\(newMatches), disagree=\(disagreements), same-photo max=\(String(format: "%.4f", samePhotoMax)), old revision=\(VNGenerateImageFeaturePrintRequest().revision)")
    }

    /// Today's (pre-V1) fingerprint path, kept only for the spike.
    private static func oldFingerprint(of cgImage: CGImage) async -> VNFeaturePrintObservation? {
        await Task.detached(priority: .userInitiated) {
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                return request.results?.first as? VNFeaturePrintObservation
            } catch {
                print("[dupes] spike: old fingerprint failed: \(error)")
                return nil
            }
        }.value
    }
    #endif
}
