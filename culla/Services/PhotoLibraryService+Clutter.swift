import Photos

extension PhotoLibraryService {

    // MARK: - Clutter Deck

    /// The photos the clutter deck may show, oldest first from `startDate`:
    /// every still image not yet sorted or dismissed, each marked when Photos
    /// already knows it's a screenshot. Videos never count as clutter, so the
    /// "Include videos" setting doesn't apply here.
    nonisolated func clutterCandidates(
        from startDate: Date,
        excluding excludedIDs: Set<String>
    ) -> [ClutterCandidate] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@",
            PHAssetMediaType.image.rawValue, startDate as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)

        var candidates: [ClutterCandidate] = []
        candidates.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            guard !excludedIDs.contains(asset.localIdentifier) else { return }
            candidates.append(ClutterCandidate(
                identifier: asset.localIdentifier,
                isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot)
            ))
        }
        return candidates
    }
}
