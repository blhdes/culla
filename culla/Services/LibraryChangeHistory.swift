import Photos

/// Photos' own history of changes (iOS 16+), read from a saved bookmark (a
/// change token). Lets `MissingPhotoCleaner` look only at what changed since
/// its last run instead of looking up every record. Part C of the iOS 27 kits
/// plan.
///
/// `nonisolated` so the cleaner's background actor can call it directly.
nonisolated enum LibraryChangeHistory {

    /// What happened to photos and albums since the bookmark.
    struct Delta {
        var deleted: Set<String> = []
        var updated: Set<String> = []
        var insertedCount = 0
        var albumChangeCount = 0
        var changeCount = 0
        /// Save this once the delta has been handled.
        var newestToken: PHPersistentChangeToken
    }

    /// Why the history can't be used, so the cleaner falls back to a full scan.
    enum Unavailable: Error, CustomStringConvertible {
        case expired
        case detailsUnavailable
        case failed(any Error)

        var description: String {
            switch self {
            case .expired: "bookmark too old for Photos' history"
            case .detailsUnavailable: "Photos has no details for a change"
            case .failed(let error): "history read failed: \(error)"
            }
        }
    }

    private static let tokenKey = "cleanup.changeToken"
    private static let fullScanKey = "cleanup.lastFullScan"
    /// A full scan still runs at least this often, as a safety net for
    /// anything the history doesn't report (shared-album photos, say).
    private static let fullScanInterval: TimeInterval = 24 * 60 * 60

    // MARK: - Reading the history

    static func delta(since token: PHPersistentChangeToken) throws(Unavailable) -> Delta {
        let changes: PHPersistentChangeFetchResult
        do {
            changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)
        } catch {
            throw unavailable(error)
        }

        var delta = Delta(newestToken: token)
        for change in changes {
            do {
                let assets = try change.changeDetails(for: .asset)
                delta.deleted.formUnion(assets.deletedLocalIdentifiers)
                delta.updated.formUnion(assets.updatedLocalIdentifiers)
                delta.insertedCount += assets.insertedLocalIdentifiers.count
                let albums = try change.changeDetails(for: .assetCollection)
                delta.albumChangeCount += albums.insertedLocalIdentifiers.count
                    + albums.updatedLocalIdentifiers.count
                    + albums.deletedLocalIdentifiers.count
            } catch {
                throw unavailable(error)
            }
            delta.changeCount += 1
            delta.newestToken = change.changeToken
        }
        // A photo added and then deleted in the same stretch only counts as deleted.
        delta.updated.subtract(delta.deleted)
        return delta
    }

    private static func unavailable(_ error: any Error) -> Unavailable {
        switch (error as? PHPhotosError)?.code {
        case .persistentChangeTokenExpired: .expired
        case .persistentChangeDetailsUnavailable: .detailsUnavailable
        default: .failed(error)
        }
    }

    // MARK: - The bookmark

    static func savedToken() -> PHPersistentChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: tokenKey) else { return nil }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
        } catch {
            print("[cleanup] couldn't read the saved change token, doing a full scan: \(error)")
            return nil
        }
    }

    static func save(_ token: PHPersistentChangeToken) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: tokenKey)
        } catch {
            // The old bookmark stays, so the next check just reads a bit more history.
            print("[cleanup] couldn't save the change token: \(error)")
        }
    }

    // MARK: - The daily full scan

    static var isFullScanDue: Bool {
        guard let last = UserDefaults.standard.object(forKey: fullScanKey) as? Date else { return true }
        return Date().timeIntervalSince(last) > fullScanInterval
    }

    static func markFullScanDone() {
        UserDefaults.standard.set(Date(), forKey: fullScanKey)
    }
}
