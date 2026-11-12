import Foundation
import SwiftData

/// `nonisolated` so the background `AlbumImporter` can create records too.
/// Without it, the app's main-thread default would tie this type to the screen.
@Model
nonisolated final class SortedPhoto {
    var id: UUID
    var assetIdentifier: String
    var sortedAt: Date
    var gallery: Gallery?

    /// True when the photo came from an album import or gallery sync,
    /// not from the user actually sorting it in the app.
    var isImported: Bool

    init(assetIdentifier: String, gallery: Gallery, isImported: Bool = false) {
        self.id = UUID()
        self.assetIdentifier = assetIdentifier
        self.sortedAt = .now
        self.gallery = gallery
        self.isImported = isImported
    }
}
