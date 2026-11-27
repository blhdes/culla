import Photos

/// How much space photos take, for the Insights Storage card and the trash.
extension PhotoLibraryService {

    // MARK: - One Photo

    /// Best-effort byte size of an asset, summed across its files (original,
    /// edited version, Live Photo video…). `nil` means Photos reported no size.
    ///
    /// iOS 27 has a public API for this (`PHAssetResource.dataSize`). Older
    /// systems only have the undocumented `fileSize` value, read through KVC.
    /// Reading a key that doesn't exist crashes (Swift can't catch that), so
    /// it first checks that iOS still has it.
    nonisolated static func assetByteSize(_ asset: PHAsset) -> Int64? {
        if #available(iOS 27, *) {
            return reportedByteSize(asset)
        }
        let fileSizeSelector = NSSelectorFromString("fileSize")
        let sizes = PHAssetResource.assetResources(for: asset).compactMap { resource -> Int64? in
            guard resource.responds(to: fileSizeSelector) else { return nil }
            return (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value
        }
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    /// The sizes Photos reports for the asset's files, added up. Files whose
    /// size isn't known yet are skipped, so the total never overstates.
    @available(iOS 27, *)
    nonisolated static func reportedByteSize(_ asset: PHAsset) -> Int64? {
        let sizes = PHAssetResource.assetResources(for: asset).compactMap(\.dataSize)
        return sizes.isEmpty ? nil : Int64(sizes.reduce(0, +))
    }

    // MARK: - Many Photos

    /// Bytes each photo takes, keyed by identifier (iOS 27 only). A photo that
    /// no longer exists counts as 0, since deleting it frees nothing. A photo
    /// whose size Photos doesn't report is left out, so callers can tell
    /// "unknown" apart from "zero". Slow for big lists: call it off the main thread.
    @available(iOS 27, *)
    nonisolated static func byteSizes(of identifiers: [String]) -> [String: Int64] {
        let started = Date()
        var sizes = [String: Int64](identifiers.map { ($0, 0) }, uniquingKeysWith: { first, _ in first })
        var unknown = 0
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: lookupOptions())
        assets.enumerateObjects { asset, _, _ in
            if let bytes = reportedByteSize(asset) {
                sizes[asset.localIdentifier] = bytes
            } else {
                sizes[asset.localIdentifier] = nil
                unknown += 1
            }
        }
        let total = sizes.values.reduce(0, +)
        let seconds = Date().timeIntervalSince(started)
        print("[storage] measured \(identifiers.count) photos: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)), \(unknown) unknown, in \(String(format: "%.2f", seconds))s")
        return sizes
    }
}
